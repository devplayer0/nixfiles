//! Approvers' connections and the `slop-approve` client, using the same framing and encoding as
//! requesters: any number of [`ApproveRequest`]s, each answered with an [`ApproveResponse`].
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::UnixListener;

use crate::audit::{Event, short};
use crate::config::user_name;
use crate::proto::{ApproveRequest, ApproveResponse, MAX_LOG_RECORDS, Transport, receive, send, transport};
use crate::queue::{Decision, PendingInfo};
use crate::remote::{Role, Stream, connect};
use crate::server::Broker;

pub const DEFAULT_ADDRESS: &str = "unix:/run/slop-broker/approve.sock";

/// The local approve socket. Its permissions admit approvers; requesters are refused even if
/// misconfigured into the group.
pub async fn listen(broker: Arc<Broker>, listener: UnixListener) -> Result<()> {
    loop {
        let (stream, _) = listener.accept().await?;
        let uid = stream.peer_cred()?.uid();
        if let Some(requester) = broker.config.requester_by_uid(uid) {
            broker.audit.log(Event::Unknown { peer: format!("requester {requester} on the approve socket") });
            continue;
        }

        let broker = broker.clone();
        tokio::spawn(async move {
            let _ = serve(broker, stream, user_name(uid)).await;
        });
    }
}

/// Answers `approver`'s requests until it disconnects.
pub async fn serve<S: AsyncRead + AsyncWrite + Unpin>(broker: Arc<Broker>, stream: S, approver: String) -> Result<()> {
    let mut transport = transport(stream);
    let first = tokio::time::timeout(Duration::from_secs(10), receive::<_, ApproveRequest>(&mut transport)).await;
    let mut request = first.unwrap_or(Ok(None));

    loop {
        let response = match request {
            Ok(Some(request)) => {
                answer(&broker, &approver, request).unwrap_or_else(|e| ApproveResponse::Error(format!("{e:#}")))
            }
            Ok(None) => return Ok(()),
            Err(error) => {
                // The stream can't be trusted after a bad frame.
                return send(&mut transport, &ApproveResponse::Error(format!("{error:#}"))).await;
            }
        };

        send(&mut transport, &response).await?;
        request = receive(&mut transport).await;
    }
}

fn answer(broker: &Broker, approver: &str, request: ApproveRequest) -> Result<ApproveResponse> {
    match request {
        ApproveRequest::List => Ok(ApproveResponse::Pending(broker.queue.list())),
        ApproveRequest::Decide { id, decision } => {
            approve(broker, &id, decision, approver)?;
            Ok(ApproveResponse::Recorded)
        }
        ApproveRequest::Log { count } => Ok(ApproveResponse::Log(broker.audit.tail(count.min(MAX_LOG_RECORDS))?)),
    }
}

/// Records a decision from any approver (terminal or phone).
pub fn approve(broker: &Broker, id: &str, decision: Decision, approver: &str) -> Result<()> {
    let info = broker.queue.decide(id, decision, approver)?;
    broker.audit.log(Event::Decision {
        id: id.to_owned(),
        requester: info.requester,
        summary: info.summary,
        decision: decision.name(),
        approver: approver.to_owned(),
    });
    Ok(())
}

/// The client's one connection to the broker.
pub struct Client(Transport<Box<dyn Stream>>);

impl Client {
    pub async fn connect(address: &str) -> Result<Client> {
        Ok(Client(transport(connect(address, Role::Approver).await?)))
    }

    async fn call(&mut self, request: ApproveRequest) -> Result<ApproveResponse> {
        send(&mut self.0, &request).await?;
        match receive(&mut self.0).await? {
            Some(ApproveResponse::Error(error)) => bail!("{error}"),
            Some(response) => Ok(response),
            None => bail!("the broker closed the connection"),
        }
    }

    async fn list(&mut self) -> Result<Vec<PendingInfo>> {
        match self.call(ApproveRequest::List).await? {
            ApproveResponse::Pending(entries) => Ok(entries),
            _ => bail!("unexpected response from the broker"),
        }
    }
}

pub fn format(entry: &PendingInfo, full: bool) -> String {
    let marker = if entry.sensitive { "  [SENSITIVE]" } else { "" };
    let mut text =
        format!("{}  {}  {}{marker}  (expires in {}s)\n", entry.id, entry.requester, entry.summary, entry.expires_in);

    let lines: Vec<_> = entry.detail.lines().collect();
    let shown = if full { lines.len() } else { lines.len().min(6) };
    for line in &lines[..shown] {
        text += &format!("    {line}\n");
    }

    if shown < lines.len() {
        text += &format!("    … {} more lines; slop-approve show {}\n", lines.len() - shown, short(&entry.id));
    }
    if let Some(label) = &entry.label {
        text += &format!("    Label (agent-supplied): {label}\n");
    }
    text
}

fn offers(entry: &PendingInfo) -> String {
    entry.offers.iter().map(Decision::name).collect::<Vec<_>>().join("|")
}

/// Finds the pending request whose ID starts with `prefix`.
fn resolve<'a>(entries: &'a [PendingInfo], prefix: &str) -> Result<&'a PendingInfo> {
    let mut matches = entries.iter().filter(|e| !prefix.is_empty() && e.id.starts_with(prefix));
    match (matches.next(), matches.next()) {
        (Some(entry), None) => Ok(entry),
        (None, _) => bail!("no pending request matches {prefix:?}"),
        (Some(_), Some(_)) => bail!("{prefix:?} matches more than one request; give more of the ID"),
    }
}

const USAGE: &str = "usage: slop-approve                    answer requests one by one, waiting for new ones
                                       (lists them instead when not on a terminal or piped)
       slop-approve list               list pending requests
       slop-approve show <id>          show a request in full
       slop-approve <id> <decision>    answer a request: once, deny or an offered lease (e.g. 5m)
       slop-approve <decision>         answer the only pending request
       slop-approve log [-n 50] [--json]
                                       recent requests, decisions and results
IDs can be shortened to any unique prefix. SLOP_APPROVE, or approve in ~/.config/slop/config.toml,
selects the broker: unix:<path> (the default is unix:/run/slop-broker/approve.sock) or
ssh:<destination>.";

pub async fn main(address: &str, args: &[String]) -> Result<()> {
    use std::io::IsTerminal;

    if let [help] = args
        && ["help", "--help", "-h"].contains(&help.as_str())
    {
        println!("{USAGE}");
        return Ok(());
    }

    let client = &mut Client::connect(address).await?;
    match args {
        [] if std::io::stdin().is_terminal() && std::io::stdout().is_terminal() => interactive(client).await?,
        [] => print_list(client).await?,
        [list] if list == "list" => print_list(client).await?,
        [log, options @ ..] if log == "log" => print_log(client, options).await?,
        [show, id] if show == "show" => {
            let entries = client.list().await?;
            print!("{}", format(resolve(&entries, id)?, true));
        }
        [decision] => {
            let decision = Decision::parse(decision).map_err(|_| anyhow!("{USAGE}"))?;
            let entries = client.list().await?;
            let [entry] = entries.as_slice() else {
                bail!("{} requests are pending; give an ID", entries.len());
            };
            decide(client, &entry.id, decision).await?;
        }
        [id, decision] => {
            let decision = Decision::parse(decision)?;
            let entries = client.list().await?;
            decide(client, &resolve(&entries, id)?.id, decision).await?;
        }
        _ => bail!("{USAGE}"),
    }
    Ok(())
}

async fn print_list(client: &mut Client) -> Result<()> {
    let entries = client.list().await?;
    if entries.is_empty() {
        println!("No pending requests.");
    }
    for entry in entries {
        print!("{}", format(&entry, false));
        println!("    Answer: slop-approve {} {}", short(&entry.id), offers(&entry));
    }
    Ok(())
}

async fn print_log(client: &mut Client, options: &[String]) -> Result<()> {
    let (mut count, mut json) = (50, false);
    let mut options = options.iter();
    while let Some(option) = options.next() {
        match option.as_str() {
            "--json" => json = true,
            "-n" => {
                count = options
                    .next()
                    .and_then(|n| n.parse().ok())
                    .filter(|n| (1..=MAX_LOG_RECORDS).contains(n))
                    .ok_or_else(|| anyhow!("-n needs a number from 1 to {MAX_LOG_RECORDS}"))?
            }
            _ => bail!("{USAGE}"),
        }
    }

    let ApproveResponse::Log(records) = client.call(ApproveRequest::Log { count }).await? else {
        bail!("unexpected response from the broker");
    };

    for record in records {
        if json {
            println!("{}", serde_json::to_string(&record)?);
        } else {
            print!("{}", record.describe());
        }
    }
    Ok(())
}

async fn decide(client: &mut Client, id: &str, decision: Decision) -> Result<()> {
    client.call(ApproveRequest::Decide { id: id.to_owned(), decision }).await?;
    println!("Recorded: {} for {}.", decision.name(), short(id));
    Ok(())
}

/// Shows pending requests one at a time and asks for an answer, then waits for more.
async fn interactive(client: &mut Client) -> Result<()> {
    use tokio::io::{AsyncBufReadExt, BufReader};
    let mut input = BufReader::new(tokio::io::stdin()).lines();
    let mut skipped = std::collections::HashSet::new();
    let mut waiting = false;

    loop {
        let entries = client.list().await?;
        skipped.retain(|id| entries.iter().any(|e| &e.id == id));
        let Some(entry) = entries.iter().find(|e| !skipped.contains(&e.id)) else {
            if !waiting {
                println!("Waiting for requests (Ctrl-C to quit)…");
                waiting = true;
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
            continue;
        };

        waiting = false;

        // Bell, so a new request is noticed in another window.
        print!("\x07\n{}", format(entry, true));

        let leases: Vec<String> =
            entry.offers.iter().filter(|d| matches!(d, Decision::Lease(_))).map(Decision::name).collect();
        let mut choices = vec!["[o]nce".to_owned()];
        choices.extend(leases);
        choices.extend(["[d]eny".into(), "[s]kip".into(), "[q]uit".into()]);

        loop {
            print!("Answer {}: ", choices.join(", "));
            std::io::Write::flush(&mut std::io::stdout())?;
            let Some(line) = input.next_line().await? else { return Ok(()) };

            let decision = match line.trim() {
                "q" | "quit" => return Ok(()),
                "s" | "skip" => {
                    skipped.insert(entry.id.clone());
                    break;
                }
                "o" => Decision::Once,
                "d" => Decision::Deny,
                "" => continue,
                other => match Decision::parse(other) {
                    Ok(decision) if entry.offers.contains(&decision) => decision,
                    _ => {
                        println!("Not an option.");
                        continue;
                    }
                },
            };

            // The request may have expired or been answered elsewhere while waiting.
            if let Err(error) = decide(client, &entry.id, decision).await {
                println!("{error:#}");
            }
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str) -> PendingInfo {
        PendingInfo {
            id: id.into(),
            requester: "r".into(),
            op: "ssh".into(),
            summary: "ssh river".into(),
            detail: String::new(),
            label: None,
            sensitive: false,
            offers: vec![Decision::Once, Decision::Deny],
            expires_in: 60,
        }
    }

    #[test]
    fn resolves_unique_prefixes() {
        let entries = [entry("abc123"), entry("abd456")];
        assert_eq!(resolve(&entries, "abc").unwrap().id, "abc123");
        assert_eq!(resolve(&entries, "abd456").unwrap().id, "abd456");
        assert!(resolve(&entries, "ab").is_err());
        assert!(resolve(&entries, "x").is_err());
        assert!(resolve(&entries, "").is_err());
    }
}
