//! Requester connections: identify the requester, apply policy, wait for approval and run the
//! operation.
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use futures_util::StreamExt;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::UnixListener;
use tokio::sync::{Semaphore, mpsc};
use tokio_util::sync::CancellationToken;
use tokio_vsock::{VMADDR_CID_ANY, VsockAddr, VsockListener};

use crate::audit::{Audit, Event};
use crate::config::Config;
use crate::exec::{Io, Output};
use crate::ops;
use crate::policy::{self, Action};
use crate::proto::{ApprovedBy, ClientMessage, PROTOCOL_VERSION, Request, ServerMessage, decode, encode, transport};
use crate::queue::{NewRequest, Outcome, Queue, new_id};

pub struct Broker {
    pub config: Config,
    pub queue: Queue,
    pub audit: Audit,
}

impl Broker {
    pub fn new(config: Config) -> Result<Broker> {
        config.validate()?;
        let queue = Queue::new(Duration::from_secs(config.timeout), config.max_pending);
        let audit = Audit::new(config.audit_log.as_deref())?;
        Ok(Broker { config, queue, audit })
    }
}

pub const MAX_CONNECTIONS: usize = 128;

pub async fn listen_vsock(broker: Arc<Broker>, port: u32) -> Result<()> {
    let listener = VsockListener::bind(VsockAddr::new(VMADDR_CID_ANY, port)).context("binding vsock")?;
    let slots = Arc::new(Semaphore::new(MAX_CONNECTIONS));

    loop {
        let (stream, address) = listener.accept().await?;
        let Some(requester) = broker.config.requester_by_cid(address.cid()).map(str::to_owned) else {
            broker.audit.log(Event::Unknown { peer: format!("vsock CID {}", address.cid()) });
            continue;
        };

        let Ok(slot) = slots.clone().try_acquire_owned() else { continue };
        let broker = broker.clone();
        tokio::spawn(async move {
            handle(broker, stream, requester).await;
            drop(slot);
        });
    }
}

pub fn bind_unix(path: &Path, mode: u32, gid: Option<u32>) -> Result<UnixListener> {
    let _ = std::fs::remove_file(path);
    let listener = UnixListener::bind(path).with_context(|| format!("binding {}", path.display()))?;
    if let Some(gid) = gid {
        std::os::unix::fs::chown(path, None, Some(gid))?;
    }
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))?;
    Ok(listener)
}

/// Local requesters, identified by the UID the kernel reports for the peer.
pub async fn listen_unix(broker: Arc<Broker>, listener: UnixListener) -> Result<()> {
    let slots = Arc::new(Semaphore::new(MAX_CONNECTIONS));

    loop {
        let (stream, _) = listener.accept().await?;
        let uid = stream.peer_cred()?.uid();
        let Some(requester) = broker.config.requester_by_uid(uid).map(str::to_owned) else {
            broker.audit.log(Event::Unknown { peer: format!("local UID {uid}") });
            continue;
        };

        let Ok(slot) = slots.clone().try_acquire_owned() else { continue };
        let broker = broker.clone();
        tokio::spawn(async move {
            handle(broker, stream, requester).await;
            drop(slot);
        });
    }
}

/// Serves one request from `requester` on `stream`.
pub async fn handle<S: AsyncRead + AsyncWrite + Send + 'static>(broker: Arc<Broker>, stream: S, requester: String) {
    let (mut sink, mut source) = transport(stream).split();
    let (tx, mut rx) = mpsc::channel::<ServerMessage>(64);
    let writer = tokio::spawn(async move {
        use futures_util::SinkExt;
        while let Some(message) = rx.recv().await {
            let terminal = message.is_terminal();
            let Ok(data) = encode(&message) else { break };
            if sink.send(data).await.is_err() || terminal {
                break;
            }
        }
        let _ = sink.close().await;
    });

    let out = Output(tx);

    let first = tokio::time::timeout(Duration::from_secs(10), source.next()).await;
    let request = match first {
        Ok(Some(Ok(frame))) => match decode::<ClientMessage>(&frame) {
            Ok(ClientMessage::Request(request)) => Ok(request),
            Ok(_) => Err(anyhow!("expected a request")),
            Err(error) => Err(error),
        },
        Ok(Some(Err(error))) => Err(error.into()),
        _ => Err(anyhow!("expected a request")),
    };

    // After the request, the requester only sends stdin; anything else, or the connection
    // closing, means it's gone.
    let cancel = CancellationToken::new();
    let (stdin_tx, stdin_rx) = mpsc::channel(16);
    let reader = {
        let cancel = cancel.clone();
        tokio::spawn(async move {
            let mut stdin_tx = Some(stdin_tx);
            while let Some(Ok(frame)) = source.next().await {
                match decode::<ClientMessage>(&frame) {
                    Ok(ClientMessage::Stdin(data)) => {
                        if let Some(tx) = &stdin_tx {
                            let _ = tx.send(data).await;
                        }
                    }
                    Ok(ClientMessage::StdinEnd) => stdin_tx = None,
                    _ => break,
                }
            }
            cancel.cancel();
        })
    };

    let mut io = Io { stdin: stdin_rx, out: out.clone(), cancel };

    let message = match request {
        Ok(request) => process(&broker, &requester, request, &mut io).await,
        Err(error) => Some(ServerMessage::Error(format!("{error:#}"))),
    };
    if let Some(message) = message {
        out.send(message).await;
    }

    drop(io);
    drop(out);
    let _ = writer.await;
    reader.abort();
}

/// Returns the final message, or `None` if the requester went away.
async fn process(broker: &Broker, requester: &str, request: Request, io: &mut Io) -> Option<ServerMessage> {
    if request.version != PROTOCOL_VERSION {
        return Some(ServerMessage::Error(format!(
            "protocol version {} is not supported (the broker uses {PROTOCOL_VERSION}); update slop",
            request.version
        )));
    }

    let id = new_id();
    let label = request.label.as_deref().map(|l| ops::truncate(l.trim(), 200)).filter(|l| !l.is_empty());
    let parsed = match ops::plan(broker, request.operation) {
        Ok(parsed) => parsed,
        Err(error) => {
            let error = format!("{error:#}");
            broker.audit.log(Event::Invalid { id, requester: requester.to_owned(), error: error.clone() });
            return Some(ServerMessage::Error(error));
        }
    };

    // Built-in operations only read the broker's own state, so they aren't logged.
    let log = |event| {
        if !parsed.builtin {
            broker.audit.log(event)
        }
    };

    log(Event::Request {
        id: id.clone(),
        requester: requester.to_owned(),
        op: parsed.op.to_owned(),
        summary: parsed.summary.clone(),
        detail: parsed.detail.clone(),
        label: label.clone(),
    });

    let (approved_by, approver) = match authorize(broker, &id, requester, &parsed, label, io).await {
        Ok(Some(approval)) => approval,
        Ok(None) => {
            log(Event::Disconnected { id });
            return None;
        }
        Err(message) => {
            log(match &message {
                ServerMessage::Expired => Event::Expired { id },
                ServerMessage::Denied(reason) | ServerMessage::Error(reason) => {
                    Event::Denied { id, reason: reason.clone() }
                }
                other => Event::Denied { id, reason: format!("{other:?}") },
            });
            return Some(message);
        }
    };

    log(Event::Approved { id: id.clone(), by: approved_by, approver });
    io.out.send(ServerMessage::Approved { by: approved_by, stdin: parsed.stdin }).await;

    let (start, builtin) = (std::time::Instant::now(), parsed.builtin);
    let result = ops::execute(broker, requester, parsed, io).await;

    let log = |event| {
        if !builtin {
            broker.audit.log(event)
        }
    };

    if io.cancel.is_cancelled() {
        log(Event::Disconnected { id });
        return None;
    }

    match result {
        Ok(outcome) => {
            log(Event::Finished { id, exit: outcome.exit, seconds: start.elapsed().as_secs_f64() });
            Some(ServerMessage::Finished { exit: outcome.exit, result: outcome.result })
        }
        Err(error) => {
            let error = format!("{error:#}");
            log(Event::Failed { id, error: error.clone() });
            Some(ServerMessage::Error(error))
        }
    }
}

/// Applies policy and waits for an approver if needed, returning who approved it (and the
/// approver's name). `Ok(None)` means the requester left.
async fn authorize(
    broker: &Broker,
    id: &str,
    requester: &str,
    parsed: &ops::Parsed,
    label: Option<String>,
    io: &mut Io,
) -> Result<Option<(ApprovedBy, Option<String>)>, ServerMessage> {
    if parsed.builtin {
        return Ok(Some((ApprovedBy::Policy, None)));
    }

    let settings = broker.config.policy(requester).ok_or_else(|| denied("unknown requester"))?;
    let verdict = policy::evaluate(settings.ops.get(parsed.op), &parsed.scope, parsed.limits);
    match verdict.action {
        Action::Deny => Err(denied("denied by policy")),
        Action::Auto => {
            broker
                .queue
                .take_auto(requester, settings.auto_per_minute)
                .map_err(|e| ServerMessage::Error(e.to_string()))?;
            Ok(Some((ApprovedBy::Policy, None)))
        }
        Action::Ask => {
            let key = parsed.lease_key();
            if !verdict.leases.is_empty() && broker.queue.leased(requester, &key) {
                return Ok(Some((ApprovedBy::Lease, None)));
            }

            let pending = NewRequest {
                requester: requester.to_owned(),
                op: parsed.op.to_owned(),
                lease_key: key,
                summary: parsed.summary.clone(),
                detail: parsed.detail.clone(),
                label,
                sensitive: parsed.sensitive,
                leases: verdict.leases,
            };

            let reply = broker
                .queue
                .submit(id, pending, settings.max_pending)
                .map_err(|e| ServerMessage::Error(e.to_string()))?;
            io.out.send(ServerMessage::Pending { id: id.to_owned(), summary: parsed.summary.clone() }).await;

            let outcome = tokio::select! {
                outcome = reply => outcome.unwrap_or(Outcome::Expired),
                _ = tokio::time::sleep(broker.queue.timeout()) => Outcome::Expired,
                _ = io.cancel.cancelled() => {
                    broker.queue.cancel(id);
                    return Ok(None);
                }
            };

            broker.queue.cancel(id);
            match outcome {
                Outcome::Approved { approver, .. } => Ok(Some((ApprovedBy::Approver, Some(approver)))),
                Outcome::Denied => Err(denied("denied by approver")),
                Outcome::Expired => Err(ServerMessage::Expired),
            }
        }
    }
}

fn denied(reason: &str) -> ServerMessage {
    ServerMessage::Denied(reason.into())
}

/// Makes sure configured sockets' parent directories aren't writable by requesters.
pub fn check_runtime_dir(path: &Path) -> Result<()> {
    use std::os::unix::fs::MetadataExt;
    let parent = path.parent().context("socket path has no parent")?;
    let metadata = std::fs::metadata(parent)?;
    if metadata.uid() != unsafe { libc::geteuid() } || metadata.mode() & 0o022 != 0 {
        bail!("{} must be owned by the broker and not group or world writable", parent.display());
    }
    Ok(())
}
