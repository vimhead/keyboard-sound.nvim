mod engine;
mod output;
mod protocol;

use std::{
    ffi::c_char,
    panic::{AssertUnwindSafe, catch_unwind},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread::{self, JoinHandle},
    time::Instant,
};

use engine::{Click, Control, WorkerInput};
use output::DeviceOutput;
use protocol::{AudioError, MAX_CLICK_AGE, MAX_PENDING_CLICKS, calculate_request_age};

struct AudioRuntime {
    control: Arc<Control>,
    clicks: mpsc::SyncSender<Click>,
    notices: mpsc::Receiver<AudioError>,
    is_stopped: Arc<AtomicBool>,
    thread: JoinHandle<()>,
}

impl AudioRuntime {
    fn start() -> Result<Self, AudioError> {
        let control = Arc::new(Control::create());
        let is_stopped = Arc::new(AtomicBool::new(false));
        let (clicks, receiver) = mpsc::sync_channel(MAX_PENDING_CLICKS);
        let (notice_sender, notices) = mpsc::sync_channel(1);
        let panic_notice = notice_sender.clone();
        let input = WorkerInput {
            control: Arc::clone(&control),
            clicks: receiver,
            notices: notice_sender,
            is_stopped: Arc::clone(&is_stopped),
        };
        let thread = thread::Builder::new()
            .name("keyboard-sound".into())
            .spawn(move || {
                if catch_unwind(AssertUnwindSafe(|| input.run(DeviceOutput::open))).is_err() {
                    let _ = panic_notice.try_send(AudioError::Internal);
                }
            })
            .map_err(|_| AudioError::StartFailed)?;
        Ok(Self {
            control,
            clicks,
            notices,
            is_stopped,
            thread,
        })
    }

    fn play(&self, request: PlayRequest) -> Result<(), AudioError> {
        if request.sound >= 8 {
            return Err(AudioError::InvalidInput);
        }
        let state = self.control.read();
        if state & 255 > 0
            && let Some(transport_age) =
                calculate_request_age(request.queued_at_millis).filter(|age| *age <= MAX_CLICK_AGE)
        {
            match self.clicks.try_send(Click {
                sound: request.sound as usize,
                state,
                received_at: Instant::now(),
                transport_age,
            }) {
                Ok(()) | Err(mpsc::TrySendError::Full(_)) => {}
                Err(mpsc::TrySendError::Disconnected(_)) => return Err(AudioError::Internal),
            }
        }
        Ok(())
    }

    fn stop(self) -> Result<(), AudioError> {
        self.is_stopped.store(true, Ordering::Release);
        drop(self.clicks);
        self.thread.join().map_err(|_| AudioError::Internal)
    }
}

struct PlayRequest {
    sound: u32,
    queued_at_millis: u64,
}

static RUNTIME: OnceLock<Mutex<Option<AudioRuntime>>> = OnceLock::new();

fn access_runtime<Action>(action: Action) -> u32
where
    Action: FnOnce(&mut Option<AudioRuntime>) -> Result<u32, AudioError>,
{
    match catch_unwind(AssertUnwindSafe(|| {
        let mut runtime = RUNTIME
            .get_or_init(|| Mutex::new(None))
            .lock()
            .map_err(|_| AudioError::Internal)?;
        action(&mut runtime)
    })) {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => error as u32,
        Err(_) => AudioError::Internal as u32,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn keyboard_sound_abi_version() -> u32 {
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn keyboard_sound_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr().cast()
}

#[unsafe(no_mangle)]
pub extern "C" fn keyboard_sound_check_samples() -> u32 {
    match catch_unwind(output::load_samples) {
        Ok(Ok(_)) => 0,
        _ => AudioError::Internal as u32,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn keyboard_sound_start() -> u32 {
    access_runtime(|runtime| {
        if runtime.is_none() {
            *runtime = Some(AudioRuntime::start()?);
        }
        Ok(0)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn keyboard_sound_configure(volume: u32) -> u32 {
    access_runtime(|runtime| {
        if volume > 100 {
            return Err(AudioError::InvalidInput);
        }
        let runtime = runtime.as_ref().ok_or(AudioError::NotStarted)?;
        runtime.control.configure(volume as u8);
        Ok(0)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn keyboard_sound_play(sound: u32, queued_at_millis: u64) -> u32 {
    access_runtime(|runtime| {
        runtime
            .as_ref()
            .ok_or(AudioError::NotStarted)?
            .play(PlayRequest {
                sound,
                queued_at_millis,
            })?;
        Ok(0)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn keyboard_sound_poll_error() -> u32 {
    access_runtime(|runtime| {
        let runtime = runtime.as_ref().ok_or(AudioError::NotStarted)?;
        match runtime.notices.try_recv() {
            Ok(error) => Ok(error as u32),
            Err(mpsc::TryRecvError::Empty) => Ok(0),
            Err(mpsc::TryRecvError::Disconnected) => Err(AudioError::Internal),
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn keyboard_sound_shutdown() -> u32 {
    access_runtime(|runtime| {
        if let Some(runtime) = runtime.take() {
            runtime.stop()?;
        }
        Ok(0)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_lifecycle_is_idempotent_validated_and_silent_when_muted() {
        assert_eq!(keyboard_sound_abi_version(), 1);
        assert_eq!(keyboard_sound_check_samples(), 0);
        assert_eq!(keyboard_sound_shutdown(), 0);
        assert_eq!(keyboard_sound_play(0, 0), AudioError::NotStarted as u32);
        assert_eq!(keyboard_sound_start(), 0);
        assert_eq!(keyboard_sound_start(), 0);
        assert_eq!(
            keyboard_sound_configure(101),
            AudioError::InvalidInput as u32
        );
        assert_eq!(keyboard_sound_configure(0), 0);
        assert_eq!(keyboard_sound_play(8, 0), AudioError::InvalidInput as u32);
        for sound in 0..8 {
            assert_eq!(keyboard_sound_play(sound, 0), 0);
        }
        assert_eq!(keyboard_sound_poll_error(), 0);
        assert_eq!(keyboard_sound_shutdown(), 0);
        assert_eq!(keyboard_sound_shutdown(), 0);
    }
}
