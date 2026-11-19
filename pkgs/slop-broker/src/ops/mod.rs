//! Operations the broker carries out. [`plan`] checks a request against the broker's
//! configuration and works out its scope and what approvers are shown; [`execute`] runs it.
use anyhow::{Context, Result};
use serde_json::{Map, Value};

use crate::exec::Io;
use crate::policy::Limits;
use crate::proto::{LeaseSummary, OpResult, Operation, PendingSummary};
use crate::server::Broker;

pub mod ssh;

pub struct Parsed {
    pub op: &'static str,
    /// What an approval covers; also what policy rules match against.
    pub scope: Map<String, Value>,
    pub summary: String,
    pub detail: String,
    pub limits: Limits,
    /// Reveals a secret or changes who can read one.
    pub sensitive: bool,
    /// Whether the operation reads the requester's stdin.
    pub stdin: bool,
    /// Needs no policy or approval.
    pub builtin: bool,
    pub operation: Operation,
}

impl Parsed {
    pub fn lease_key(&self) -> String {
        format!("{} {}", self.op, Value::Object(self.scope.clone()))
    }
}

/// What an operation produced: its exit status and any structured result.
pub struct Outcome {
    pub exit: i32,
    pub result: Option<OpResult>,
}

impl From<i32> for Outcome {
    fn from(exit: i32) -> Outcome {
        Outcome { exit, result: None }
    }
}

pub fn plan(broker: &Broker, operation: Operation) -> Result<Parsed> {
    match &operation {
        Operation::Ssh { destination, command } => {
            let config = broker.config.ssh.as_ref().context("SSH is not configured on this broker")?;
            ssh::check(config, destination)?;
            let shown =
                if command.is_empty() { "(no command)".to_owned() } else { truncate(&shell_quote(command), 1000) };

            Ok(Parsed {
                op: "ssh",
                scope: ssh::scope(destination),
                summary: format!("ssh {}", ssh::describe(destination)),
                detail: format!("Command: {shown}"),
                limits: Limits::default(),
                sensitive: false,
                stdin: true,
                builtin: false,
                operation,
            })
        }
        Operation::Requests => Ok(Parsed {
            op: "requests",
            scope: Map::new(),
            summary: "list requests".into(),
            detail: String::new(),
            limits: Limits::default(),
            sensitive: false,
            stdin: false,
            builtin: true,
            operation,
        }),
    }
}

pub async fn execute(broker: &Broker, requester: &str, parsed: Parsed, io: &mut Io) -> Result<Outcome> {
    match parsed.operation {
        Operation::Ssh { destination, command } => {
            ssh::execute(broker, &destination, &command, io).await.map(Into::into)
        }
        Operation::Requests => {
            let pending = broker
                .queue
                .list()
                .into_iter()
                .filter(|e| e.requester == requester)
                .map(|e| PendingSummary { id: e.id, summary: e.summary, expires_in: e.expires_in })
                .collect();
            let leases = broker
                .queue
                .leases(requester)
                .into_iter()
                .map(|(scope, remaining)| LeaseSummary { scope, remaining })
                .collect();
            Ok(Outcome { exit: 0, result: Some(OpResult::Requests { pending, leases }) })
        }
    }
}

/// Quotes words for a POSIX shell, for showing commands and for remote commands built here.
pub fn shell_quote<S: AsRef<str>>(words: &[S]) -> String {
    words
        .iter()
        .map(|w| {
            let w = w.as_ref();
            if !w.is_empty() && w.bytes().all(|c| c.is_ascii_alphanumeric() || b"_-./=:@%+,".contains(&c)) {
                w.to_owned()
            } else {
                format!("'{}'", w.replace('\'', r"'\''"))
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn truncate(text: &str, limit: usize) -> String {
    match text.char_indices().nth(limit) {
        Some((index, _)) => format!("{}…", &text[..index]),
        None => text.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_for_the_shell() {
        assert_eq!(shell_quote(&["systemctl", "status", "a b", "it's", ""]), r"systemctl status 'a b' 'it'\''s' ''");
    }
}
