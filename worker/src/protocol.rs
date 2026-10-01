use serde::Deserialize;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const MAX_CLICK_AGE: Duration = Duration::from_millis(80);
pub const MAX_PENDING_CLICKS: usize = 8;
pub const MAX_VOICES: usize = 8;

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Message {
    Configure { is_enabled: bool, volume: u8 },
    Click { sound: usize, queued_at_millis: u64 },
}

impl Message {
    pub fn parse(line: &str) -> Result<Self, String> {
        let message: Self = serde_json::from_str(line).map_err(|error| error.to_string())?;
        match message {
            Self::Configure { volume, .. } if volume > 100 => Err("volume exceeds 100".into()),
            Self::Click { sound, .. } if sound >= 8 => Err("unknown sound".into()),
            _ => Ok(message),
        }
    }
}

pub fn calculate_request_age(queued_at_millis: u64) -> Option<Duration> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?;
    let queued_at = Duration::from_millis(queued_at_millis);
    now.checked_sub(queued_at).or_else(|| {
        (queued_at.saturating_sub(now) < Duration::from_millis(1)).then_some(Duration::ZERO)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_out_of_range_and_unknown_fields() {
        for line in [
            r#"{"type":"configure","is_enabled":true,"volume":101}"#,
            r#"{"type":"click","sound":8,"queued_at_millis":0}"#,
            r#"{"type":"configure","is_enabled":true,"volume":50,"extra":0}"#,
            r#"{"type":"click","sound":-1,"queued_at_millis":0}"#,
            r#"{"type":"configure","is_enabled":true,"volume":1.5}"#,
        ] {
            assert!(Message::parse(line).is_err(), "{line}");
        }
    }

    #[test]
    fn accepts_every_sound_and_volume_boundary() {
        for sound in 0..8 {
            assert!(
                Message::parse(&format!(
                    r#"{{"type":"click","sound":{sound},"queued_at_millis":0}}"#
                ))
                .is_ok()
            );
        }
        for volume in [0, 50, 100] {
            assert!(
                Message::parse(&format!(
                    r#"{{"type":"configure","is_enabled":true,"volume":{volume}}}"#
                ))
                .is_ok()
            );
        }
        assert!(calculate_request_age(0).unwrap() > MAX_CLICK_AGE);
        assert!(calculate_request_age(u64::MAX).is_none());
    }
}
