use std::{
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc::{Receiver, RecvTimeoutError, SyncSender},
    },
    time::{Duration, Instant},
};

use crate::{
    output::AudioOutput,
    protocol::{AudioError, MAX_CLICK_AGE},
};

pub struct Control {
    state: AtomicU64,
}

impl Control {
    pub fn create() -> Self {
        Self {
            state: AtomicU64::new(0),
        }
    }

    pub fn configure(&self, volume: u8) {
        let mut previous = self.state.load(Ordering::Acquire);
        loop {
            let next = ((previous & !255).wrapping_add(256)) | u64::from(volume);
            match self.state.compare_exchange_weak(
                previous,
                next,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => break,
                Err(current) => previous = current,
            }
        }
    }

    pub fn read(&self) -> u64 {
        self.state.load(Ordering::Acquire)
    }
}

pub struct Click {
    pub sound: usize,
    pub state: u64,
    pub received_at: Instant,
    pub transport_age: Duration,
}

impl Click {
    fn is_current(&self, state: u64) -> bool {
        self.state == state
            && self
                .transport_age
                .saturating_add(self.received_at.elapsed())
                <= MAX_CLICK_AGE
    }
}

pub struct Playback<Output> {
    output: Option<Output>,
    state: u64,
    is_unavailable: bool,
    is_device_failed: Arc<AtomicBool>,
}

impl<Output: AudioOutput> Playback<Output> {
    pub fn create(is_device_failed: Arc<AtomicBool>) -> Self {
        Self {
            output: None,
            state: 0,
            is_unavailable: false,
            is_device_failed,
        }
    }

    pub fn update<Factory>(
        &mut self,
        state: u64,
        open_output: &mut Factory,
    ) -> Result<(), AudioError>
    where
        Factory: FnMut(Arc<AtomicBool>) -> Result<Output, String>,
    {
        if self.state != state {
            self.is_unavailable = false;
            self.state = state;
        }
        if self.is_device_failed.swap(false, Ordering::AcqRel) {
            self.output = None;
            self.is_unavailable = true;
            return Err(AudioError::Disconnected);
        }
        let volume = (state & 255) as u8;
        if volume == 0 {
            self.output = None;
        } else if self.output.is_none() && !self.is_unavailable {
            match open_output(Arc::clone(&self.is_device_failed)) {
                Ok(output) => self.output = Some(output),
                Err(_) => {
                    self.is_unavailable = true;
                    return Err(AudioError::Unavailable);
                }
            }
        }
        if let Some(output) = &mut self.output {
            output.set_volume(volume);
        }
        Ok(())
    }

    pub fn play(&mut self, click: Click) {
        if click.is_current(self.state)
            && let Some(output) = &mut self.output
        {
            output.play(click.sound);
        }
    }
}

pub struct WorkerInput {
    pub control: Arc<Control>,
    pub clicks: Receiver<Click>,
    pub notices: SyncSender<AudioError>,
    pub is_stopped: Arc<AtomicBool>,
}

impl WorkerInput {
    pub fn run<Output, Factory>(self, mut open_output: Factory)
    where
        Output: AudioOutput,
        Factory: FnMut(Arc<AtomicBool>) -> Result<Output, String>,
    {
        let mut playback = Playback::create(Arc::new(AtomicBool::new(false)));
        while !self.is_stopped.load(Ordering::Acquire) {
            if let Err(notice) = playback.update(self.control.read(), &mut open_output) {
                let _ = self.notices.try_send(notice);
            }
            match self.clicks.recv_timeout(Duration::from_millis(10)) {
                Ok(click) => {
                    if let Err(notice) = playback.update(self.control.read(), &mut open_output) {
                        let _ = self.notices.try_send(notice);
                    }
                    if !self.is_stopped.load(Ordering::Acquire) {
                        playback.play(click);
                    }
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{cell::RefCell, rc::Rc};

    struct FakeOutput {
        played: Rc<RefCell<Vec<usize>>>,
        volumes: Rc<RefCell<Vec<u8>>>,
    }

    impl AudioOutput for FakeOutput {
        fn set_volume(&mut self, volume: u8) {
            self.volumes.borrow_mut().push(volume);
        }
        fn play(&mut self, sound: usize) {
            self.played.borrow_mut().push(sound);
        }
    }

    #[test]
    fn discards_stale_and_previous_configuration_clicks() {
        let played = Rc::new(RefCell::new(Vec::new()));
        let volumes = Rc::new(RefCell::new(Vec::new()));
        let mut factory = |_| {
            Ok(FakeOutput {
                played: played.clone(),
                volumes: volumes.clone(),
            })
        };
        let mut playback = Playback::create(Arc::new(AtomicBool::new(false)));
        let control = Control::create();
        control.configure(50);
        let old_state = control.read();
        control.configure(25);
        let state = control.read();
        playback.update(state, &mut factory).unwrap();
        for (sound, click_state, age) in [
            (0, old_state, 0),
            (1, state, 81),
            (7, state, 0),
            (6, state, 0),
        ] {
            playback.play(Click {
                sound,
                state: click_state,
                received_at: Instant::now(),
                transport_age: Duration::from_millis(age),
            });
        }
        assert_eq!(*played.borrow(), [7, 6]);
        assert_eq!(*volumes.borrow(), [25]);
        control.configure(0);
        playback.update(control.read(), &mut factory).unwrap();
        playback.play(Click {
            sound: 2,
            state: control.read(),
            received_at: Instant::now(),
            transport_age: Duration::ZERO,
        });
        assert_eq!(*played.borrow(), [7, 6]);
    }

    #[test]
    fn muted_worker_never_opens_output_and_failures_require_configuration_to_retry() {
        let mut attempts = 0;
        let mut factory = |_| -> Result<FakeOutput, String> {
            attempts += 1;
            Err("missing device".into())
        };
        let is_device_failed = Arc::new(AtomicBool::new(false));
        let mut playback = Playback::create(is_device_failed.clone());
        let control = Control::create();
        playback.update(control.read(), &mut factory).unwrap();
        control.configure(50);
        assert!(playback.update(control.read(), &mut factory).is_err());
        playback.update(control.read(), &mut factory).unwrap();
        control.configure(50);
        assert!(playback.update(control.read(), &mut factory).is_err());
        is_device_failed.store(true, Ordering::Release);
        assert!(playback.update(control.read(), &mut factory).is_err());
        assert_eq!(attempts, 2);
    }

    #[test]
    fn bounded_queue_drops_overflow_without_blocking() {
        let (sender, _receiver) =
            std::sync::mpsc::sync_channel(crate::protocol::MAX_PENDING_CLICKS);
        for sound in 0..8 {
            sender
                .try_send(Click {
                    sound,
                    state: 50,
                    received_at: Instant::now(),
                    transport_age: Duration::ZERO,
                })
                .unwrap();
        }
        assert!(
            sender
                .try_send(Click {
                    sound: 0,
                    state: 50,
                    received_at: Instant::now(),
                    transport_age: Duration::ZERO
                })
                .is_err()
        );
    }
}
