//! Audit trail of every request, decision and result. Each event goes to the journal as a line of
//! text and, if configured, to a file as a line of JSON. `slop-approve log` reads the file back.
use std::fmt;
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::SystemTime;

use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::proto::ApprovedBy;

/// One line of the audit file.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Record {
    /// UTC, RFC 3339.
    pub time: String,
    #[serde(flatten)]
    pub event: Event,
}

/// `id` is the request's ID, the same one approvers and `slop requests` show.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "kebab-case")]
pub enum Event {
    /// A connection from a peer that isn't a configured requester.
    Unknown {
        peer: String,
    },
    /// A request that couldn't be read or doesn't fit the configuration.
    Invalid {
        id: String,
        requester: String,
        error: String,
    },
    Request {
        id: String,
        requester: String,
        op: String,
        summary: String,
        detail: String,
        /// Agent-supplied.
        label: Option<String>,
    },
    Approved {
        id: String,
        by: ApprovedBy,
        /// Who answered, when an approver did.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        approver: Option<String>,
    },
    /// An approver's answer.
    Decision {
        id: String,
        requester: String,
        summary: String,
        decision: String,
        approver: String,
    },
    Denied {
        id: String,
        reason: String,
    },
    Expired {
        id: String,
    },
    Disconnected {
        id: String,
    },
    Finished {
        id: String,
        exit: i32,
        seconds: f64,
    },
    Failed {
        id: String,
        error: String,
    },
}

impl Event {
    /// Whether the journal should show it as a warning.
    fn is_warning(&self) -> bool {
        matches!(self, Event::Unknown { .. } | Event::Invalid { .. } | Event::Failed { .. })
    }
}

/// Request IDs are long; approvers type a prefix, and logs show the same.
pub fn short(id: &str) -> &str {
    &id[..id.len().min(6)]
}

impl fmt::Display for Event {
    /// One line, for the journal.
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Event::Unknown { peer } => write!(f, "refused connection from {peer}: not a configured requester"),
            Event::Invalid { id, requester, error } => {
                write!(f, "{} invalid request from {requester}: {error}", short(id))
            }
            Event::Request { id, requester, summary, detail, label, .. } => {
                write!(f, "{} {requester} asks: {summary}", short(id))?;
                if let Some(line) = detail.lines().next() {
                    write!(f, "; {line}")?;
                }
                if let Some(label) = label {
                    write!(f, " (label: {label})")?;
                }
                Ok(())
            }
            Event::Approved { id, by, approver } => {
                let by = match (by, approver) {
                    (ApprovedBy::Policy, _) => "policy",
                    (ApprovedBy::Lease, _) => "a lease",
                    (ApprovedBy::Approver, Some(approver)) => approver,
                    (ApprovedBy::Approver, None) => "an approver",
                };
                write!(f, "{} approved by {by}", short(id))
            }
            Event::Decision { id, decision, approver, .. } => {
                write!(f, "{} answered {decision} by {approver}", short(id))
            }
            Event::Denied { id, reason } => write!(f, "{} {reason}", short(id)),
            Event::Expired { id } => write!(f, "{} expired without an answer", short(id)),
            Event::Disconnected { id } => write!(f, "{} cancelled: the requester disconnected", short(id)),
            Event::Finished { id, exit, seconds } => {
                write!(f, "{} finished with exit status {exit} after {seconds:.1}s", short(id))
            }
            Event::Failed { id, error } => write!(f, "{} failed: {error}", short(id)),
        }
    }
}

impl Record {
    /// For reviewing: the journal's line, with the time and the rest of a request's detail.
    pub fn describe(&self) -> String {
        let time = self.time.replace('T', " ").trim_end_matches('Z').to_owned();
        let mut text = format!("{time}  {}\n", self.event);
        if let Event::Request { detail, .. } = &self.event {
            for line in detail.lines().skip(1) {
                text += &format!("{:21}{line}\n", "");
            }
        }
        text
    }
}

pub struct Audit {
    file: Option<(PathBuf, Mutex<File>)>,
}

impl Audit {
    pub fn new(path: Option<&Path>) -> Result<Audit> {
        let file = match path {
            Some(path) => {
                let file = OpenOptions::new().create(true).append(true).open(path)?;
                Some((path.to_owned(), Mutex::new(file)))
            }
            None => None,
        };
        Ok(Audit { file })
    }

    pub fn log(&self, event: Event) {
        // systemd reads the `<N>` prefix as the line's priority.
        eprintln!("{}{event}", if event.is_warning() { "<4>" } else { "<6>" });

        if let Some((_, file)) = &self.file {
            let record = Record { time: humantime::format_rfc3339_seconds(SystemTime::now()).to_string(), event };
            if let Ok(line) = serde_json::to_string(&record) {
                let _ = writeln!(file.lock().unwrap(), "{line}");
            }
        }
    }

    /// The last `count` records of the file, oldest first.
    pub fn tail(&self, count: usize) -> Result<Vec<Record>> {
        const WINDOW: u64 = 4 << 20;
        let Some((path, _)) = &self.file else { anyhow::bail!("the broker has no audit file") };

        let mut file = File::open(path)?;
        let length = file.metadata()?.len();
        let start = length.saturating_sub(WINDOW);
        file.seek(SeekFrom::Start(start))?;
        let mut text = String::new();
        file.take(WINDOW).read_to_string(&mut text)?;

        // A window that starts mid-file starts mid-line.
        let text = if start > 0 { text.split_once('\n').map_or("", |(_, rest)| rest) } else { &text };

        let lines: Vec<&str> = text.lines().collect();
        let skip = lines.len().saturating_sub(count);
        Ok(lines[skip..].iter().filter_map(|line| serde_json::from_str(line).ok()).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_and_reads_back_records() {
        let directory = tempfile::tempdir().unwrap();
        let audit = Audit::new(Some(&directory.path().join("audit.jsonl"))).unwrap();
        for exit in 0..5 {
            audit.log(Event::Finished { id: "0123456789abcdef".into(), exit, seconds: 1.5 });
        }
        let records = audit.tail(2).unwrap();
        assert_eq!(records.len(), 2);
        assert_eq!(records[1].event, Event::Finished { id: "0123456789abcdef".into(), exit: 4, seconds: 1.5 });
        assert!(records[1].describe().ends_with("012345 finished with exit status 4 after 1.5s\n"));
    }

    #[test]
    fn describes_requests_in_full() {
        let record = Record {
            time: "2026-11-19T10:02:13Z".into(),
            event: Event::Request {
                id: "0123456789abcdef".into(),
                requester: "slop-cannon".into(),
                op: "ssh".into(),
                summary: "ssh river".into(),
                detail: "Command: a\nmore".into(),
                label: Some("why".into()),
            },
        };
        assert_eq!(
            record.describe(),
            "2026-11-19 10:02:13  012345 slop-cannon asks: ssh river; Command: a (label: why)\n\
             \x20                    more\n"
        );
    }
}
