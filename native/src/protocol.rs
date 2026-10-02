use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const MAX_CLICK_AGE: Duration = Duration::from_millis(80);
pub const MAX_PENDING_CLICKS: usize = 8;
pub const MAX_VOICES: usize = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum AudioError {
    StartFailed = 1,
    Unavailable = 2,
    Disconnected = 3,
    Internal = 4,
    InvalidInput = 5,
    NotStarted = 6,
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
    fn rejects_old_and_future_timestamps() {
        assert!(calculate_request_age(0).unwrap() > MAX_CLICK_AGE);
        assert!(calculate_request_age(u64::MAX).is_none());
    }
}
