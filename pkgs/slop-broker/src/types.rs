//! Validated values used in requests. Each type can only be constructed (including by
//! deserializing) from a value that passed its check, so the rest of the broker can rely on it.
use std::fmt;
use std::ops::Deref;
use std::str::FromStr;

use serde::{Deserialize, Serialize};

macro_rules! validated_string {
    ($(#[$doc:meta])* $name:ident, $what:literal, $check:expr) => {
        $(#[$doc])*
        #[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
        #[serde(try_from = "String", into = "String")]
        pub struct $name(String);

        impl TryFrom<String> for $name {
            type Error = String;
            fn try_from(value: String) -> Result<Self, String> {
                let check: fn(&str) -> bool = $check;
                if check(&value) { Ok(Self(value)) } else { Err(format!("invalid {}: {:?}", $what, value)) }
            }
        }

        impl FromStr for $name {
            type Err = String;
            fn from_str(value: &str) -> Result<Self, String> {
                Self::try_from(value.to_owned())
            }
        }

        impl From<$name> for String {
            fn from(value: $name) -> String {
                value.0
            }
        }

        impl Deref for $name {
            type Target = str;
            fn deref(&self) -> &str {
                &self.0
            }
        }

        impl AsRef<str> for $name {
            fn as_ref(&self) -> &str {
                &self.0
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str(&self.0)
            }
        }
    };
}

validated_string!(
    /// A deploy node or other configured name.
    NodeName,
    "name",
    |s| {
        let b = s.as_bytes();
        !b.is_empty()
            && b.len() <= 128
            && b[0].is_ascii_alphanumeric()
            && b.iter().all(|&c| c.is_ascii_alphanumeric() || b"_.-".contains(&c))
    }
);

validated_string!(
    /// A remote login name.
    UserName,
    "user name",
    |s| {
        let b = s.as_bytes();
        !b.is_empty()
            && b.len() <= 32
            && (b[0].is_ascii_lowercase() || b[0] == b'_')
            && b.iter().all(|&c| c.is_ascii_lowercase() || c.is_ascii_digit() || b"_.-".contains(&c))
    }
);

validated_string!(
    /// A DNS name or IP address; never something `ssh` could read as an option.
    HostName,
    "host name",
    |s| {
        if s.parse::<std::net::IpAddr>().is_ok() {
            return true;
        }
        let b = s.as_bytes();
        !b.is_empty() && b.len() <= 253 && b[0].is_ascii_alphanumeric() && b.iter().all(|&c| c.is_ascii_alphanumeric() || b".-".contains(&c))
    }
);

validated_string!(
    /// A systemd unit name, including `\x2d`-style escapes; never an option.
    UnitName,
    "unit name",
    |s| {
        let b = s.as_bytes();
        !b.is_empty()
            && b.len() <= 256
            && b[0] != b'-'
            && b.iter().all(|&c| c.is_ascii_alphanumeric() || b":_.@-\\".contains(&c))
            && !s.contains("\\\\")
    }
);

validated_string!(
    /// One word of a command; anything but NUL.
    Arg,
    "argument",
    |s| !s.contains('\0')
);

validated_string!(
    /// A journal start: a duration back from now (`30m`, `2h`, `1d`) or a date
    /// (`YYYY-MM-DD[ HH:MM[:SS]]`).
    Since,
    "time (use a duration like 2h or a date like 2026-01-31 12:00)",
    |s| {
        if crate::queue::parse_duration(s).is_some() {
            return true;
        }
        let b = s.as_bytes();
        (10..=19).contains(&b.len()) && b[..4].iter().all(u8::is_ascii_digit) && b.iter().all(|&c| c.is_ascii_digit() || b"-: ".contains(&c))
    }
);

impl Since {
    /// The value `journalctl --since` takes.
    pub fn journalctl(&self) -> String {
        match crate::queue::parse_duration(self) {
            Some(seconds) => format!("-{seconds}s"),
            None => self.0.clone(),
        }
    }
}

/// Journal lines to show, 1 to 5000.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "u32", into = "u32")]
pub struct Lines(u32);

impl Lines {
    pub const DEFAULT: Lines = Lines(200);
    pub const MAX: u32 = 5000;

    pub fn get(self) -> u32 {
        self.0
    }
}

impl TryFrom<u32> for Lines {
    type Error = String;
    fn try_from(value: u32) -> Result<Self, String> {
        if (1..=Self::MAX).contains(&value) { Ok(Lines(value)) } else { Err(format!("lines must be 1-{}", Self::MAX)) }
    }
}

impl FromStr for Lines {
    type Err = String;
    fn from_str(value: &str) -> Result<Self, String> {
        value.parse::<u32>().map_err(|e| e.to_string()).and_then(Lines::try_from)
    }
}

impl From<Lines> for u32 {
    fn from(value: Lines) -> u32 {
        value.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        assert!("river".parse::<NodeName>().is_ok());
        assert!("container-hass.x_1".parse::<NodeName>().is_ok());
        assert!("-oProxyCommand=x".parse::<NodeName>().is_err());
        assert!("".parse::<NodeName>().is_err());
        assert!("root".parse::<UserName>().is_ok());
        assert!("Root".parse::<UserName>().is_err());
        assert!("-l".parse::<UserName>().is_err());
        assert!("fergal.h.nul.ie".parse::<HostName>().is_ok());
        assert!("2a0e:97c0:4d2:10::2".parse::<HostName>().is_ok());
        assert!("-oProxyCommand=x".parse::<HostName>().is_err());
        assert!("a b".parse::<HostName>().is_err());
    }

    #[test]
    fn units() {
        assert!("nginx.service".parse::<UnitName>().is_ok());
        assert!("container@hass.service".parse::<UnitName>().is_ok());
        assert!(r"dev-disk-by\x2duuid-1.device".parse::<UnitName>().is_ok());
        assert!("-H".parse::<UnitName>().is_err());
        assert!("a;b".parse::<UnitName>().is_err());
        assert!(r"a\\b".parse::<UnitName>().is_err());
    }

    #[test]
    fn since_and_lines() {
        assert_eq!("2h".parse::<Since>().unwrap().journalctl(), "-7200s");
        assert_eq!("2026-01-31 12:00".parse::<Since>().unwrap().journalctl(), "2026-01-31 12:00");
        assert!("yesterday; reboot".parse::<Since>().is_err());
        assert!("-1h".parse::<Since>().is_err());
        assert!("0".parse::<Lines>().is_err());
        assert!("5001".parse::<Lines>().is_err());
        assert_eq!("50".parse::<Lines>().unwrap().get(), 50);
    }

    #[test]
    fn deserializing_validates() {
        let ok: Result<NodeName, _> = serde_json::from_str("\"river\"");
        assert!(ok.is_ok());
        let bad: Result<NodeName, _> = serde_json::from_str("\"-x\"");
        assert!(bad.is_err());
        let bad: Result<Lines, _> = serde_json::from_str("0");
        assert!(bad.is_err());
    }
}
