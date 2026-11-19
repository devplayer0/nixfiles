//! Fixed read-only queries on boxes over SSH. The broker builds and quotes the remote command
//! from validated values, so policy can safely approve these by itself.
use anyhow::Result;

use super::{shell_quote, ssh};
use crate::exec::{self, Io};
use crate::proto::{Destination, Query};
use crate::server::Broker;

pub fn name(query: &Query) -> &'static str {
    match query {
        Query::Status { .. } => "status",
        Query::Logs { .. } => "logs",
        Query::Failed => "failed",
    }
}

pub fn remote_command(query: &Query) -> Vec<String> {
    let mut words: Vec<String> = match query {
        Query::Status { .. } => vec!["systemctl".into(), "status".into(), "--no-pager".into()],
        Query::Failed => vec!["systemctl".into(), "list-units".into(), "--failed".into(), "--no-pager".into()],
        Query::Logs { .. } => vec!["journalctl".into(), "--no-pager".into(), "--output=short-iso".into()],
    };
    match query {
        Query::Status { unit: Some(unit) } => words.extend(["--".into(), unit.to_string()]),
        Query::Logs { unit, lines, since } => {
            words.push(format!("--lines={}", lines.get()));
            if let Some(since) = since {
                words.push(format!("--since={}", since.journalctl()));
            }
            words.push(format!("--unit={unit}"));
        }
        _ => {}
    }
    words
}

pub async fn execute(broker: &Broker, destination: &Destination, query: &Query, io: &mut Io) -> Result<i32> {
    let config = broker.config.ssh.as_ref().unwrap();
    // One quoted string, so the remote login shell (POSIX or fish) sees exactly these words.
    let remote = [shell_quote(&remote_command(query))];
    exec::run(ssh::command(config, destination, &remote), io, false).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Lines;

    #[test]
    fn commands() {
        let logs = Query::Logs {
            unit: "nginx.service".parse().unwrap(),
            lines: Lines::try_from(50).unwrap(),
            since: Some("2026-01-31 12:00".parse().unwrap()),
        };
        assert_eq!(
            shell_quote(&remote_command(&logs)),
            "journalctl --no-pager --output=short-iso --lines=50 '--since=2026-01-31 12:00' --unit=nginx.service"
        );
        let status = Query::Status { unit: Some("nginx.service".parse().unwrap()) };
        assert_eq!(shell_quote(&remote_command(&status)), "systemctl status --no-pager -- nginx.service");
        assert_eq!(shell_quote(&remote_command(&Query::Failed)), "systemctl list-units --failed --no-pager");
    }
}
