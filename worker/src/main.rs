mod engine;
mod output;
mod protocol;

use std::{
    io::{self, BufRead},
    sync::{Arc, mpsc},
    thread,
    time::Instant,
};

use engine::{Click, Control, WorkerInput};
use output::{DeviceOutput, load_samples};
use protocol::{MAX_CLICK_AGE, MAX_PENDING_CLICKS, Message, calculate_request_age};

fn read_requests(control: Arc<Control>, sender: mpsc::SyncSender<Click>) -> Result<(), String> {
    for line in io::stdin().lock().lines() {
        let line = line.map_err(|error| error.to_string())?;
        match Message::parse(&line)? {
            Message::Configure { is_enabled, volume } => {
                control.configure(if is_enabled { volume } else { 0 })
            }
            Message::Click {
                sound,
                queued_at_millis,
            } => {
                if let Some(transport_age) =
                    calculate_request_age(queued_at_millis).filter(|age| *age <= MAX_CLICK_AGE)
                {
                    let state = control.read();
                    if state & 255 > 0 {
                        let _ = sender.try_send(Click {
                            sound,
                            state,
                            received_at: Instant::now(),
                            transport_age,
                        });
                    }
                }
            }
        }
    }
    Ok(())
}

fn run() -> Result<(), String> {
    let arguments: Vec<_> = std::env::args().skip(1).collect();
    if arguments == ["--check"] {
        let samples = load_samples()?;
        println!("Decoded {} keyboard samples.", samples.len());
        return Ok(());
    }
    if !arguments.is_empty() {
        return Err("Usage: keyboard-sound-worker [--check]".into());
    }
    let control = Arc::new(Control::create());
    let (sender, clicks) = mpsc::sync_channel(MAX_PENDING_CLICKS);
    let reader_control = Arc::clone(&control);
    let reader = thread::spawn(move || read_requests(reader_control, sender));
    WorkerInput { control, clicks }.run(DeviceOutput::open);
    reader
        .join()
        .map_err(|_| "Input reader failed".to_string())?
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
