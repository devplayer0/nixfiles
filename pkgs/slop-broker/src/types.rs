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
    /// One word of a command; anything but NUL.
    Arg,
    "argument",
    |s| !s.contains('\0')
);

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
    fn deserializing_validates() {
        let ok: Result<NodeName, _> = serde_json::from_str("\"river\"");
        assert!(ok.is_ok());
        let bad: Result<NodeName, _> = serde_json::from_str("\"-x\"");
        assert!(bad.is_err());
    }
}
