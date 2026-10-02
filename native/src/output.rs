use rodio::{Decoder, OutputStream, OutputStreamBuilder, Sink, Source, buffer::SamplesBuffer};
use std::{
    collections::VecDeque,
    io::Cursor,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use crate::protocol::MAX_VOICES;

const SAMPLES: [&[u8]; 8] = [
    include_bytes!("../../assets/sounds/click-08.wav"),
    include_bytes!("../../assets/sounds/click-01.wav"),
    include_bytes!("../../assets/sounds/click-09.wav"),
    include_bytes!("../../assets/sounds/click-06.wav"),
    include_bytes!("../../assets/sounds/click-05.wav"),
    include_bytes!("../../assets/sounds/click-04.wav"),
    include_bytes!("../../assets/sounds/click-07.wav"),
    include_bytes!("../../assets/sounds/click-02.wav"),
];

pub fn load_samples() -> Result<Vec<SamplesBuffer>, String> {
    SAMPLES
        .iter()
        .map(|bytes| {
            let decoder =
                Decoder::try_from(Cursor::new(*bytes)).map_err(|error| error.to_string())?;
            Ok(SamplesBuffer::new(
                decoder.channels(),
                decoder.sample_rate(),
                decoder.collect::<Vec<_>>(),
            ))
        })
        .collect()
}

pub trait AudioOutput {
    fn set_volume(&mut self, volume: u8);
    fn play(&mut self, sound: usize);
}

pub struct DeviceOutput {
    stream: OutputStream,
    voices: VecDeque<Sink>,
    samples: Vec<SamplesBuffer>,
    volume: f32,
}

impl DeviceOutput {
    pub fn open(is_failed: Arc<AtomicBool>) -> Result<Self, String> {
        let samples = load_samples()?;
        let mut stream = OutputStreamBuilder::from_default_device()
            .map_err(|error| error.to_string())?
            .with_error_callback(move |_| is_failed.store(true, Ordering::Release))
            .with_buffer_size(rodio::cpal::BufferSize::Fixed(256))
            .open_stream_or_fallback()
            .map_err(|error| error.to_string())?;
        stream.log_on_drop(false);
        Ok(Self {
            stream,
            voices: VecDeque::new(),
            samples,
            volume: 0.0,
        })
    }
}

impl AudioOutput for DeviceOutput {
    fn set_volume(&mut self, volume: u8) {
        self.volume = f32::from(volume) / 100.0;
        self.voices.retain(|voice| !voice.empty());
        for voice in &self.voices {
            voice.set_volume(self.volume);
        }
    }

    fn play(&mut self, sound: usize) {
        self.voices.retain(|voice| !voice.empty());
        if self.voices.len() == MAX_VOICES {
            self.voices.pop_front().unwrap().stop();
        }
        let voice = Sink::connect_new(self.stream.mixer());
        voice.set_volume(self.volume);
        voice.append(self.samples[sound].clone());
        self.voices.push_back(voice);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_eight_distinct_mono_samples() {
        let samples = load_samples().unwrap();
        assert_eq!(samples.len(), 8);
        let fingerprints: std::collections::HashSet<_> = samples
            .into_iter()
            .map(|sample| {
                assert_eq!(sample.channels(), 1);
                assert_eq!(sample.sample_rate(), 44100);
                let frames: Vec<_> = sample.map(f32::to_bits).collect();
                assert!(!frames.is_empty());
                frames
            })
            .collect();
        assert_eq!(fingerprints.len(), 8);
    }
}
