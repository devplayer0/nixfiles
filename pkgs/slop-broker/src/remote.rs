//! Connections to the broker from other boxes, over SSH.
//!
//! A client runs `ssh <destination> request` (or `approve`). On the broker's box, `sshd` maps the
//! client's key to a forced command, `slop-broker remote <role> <name>`, which connects to the
//! broker's remote socket, says who the key belongs to with a [`Hello`] and then copies bytes both
//! ways. Only the configured SSH user can open that socket, so the broker trusts the hello the
//! same way it trusts a vsock CID.
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::Semaphore;

use crate::audit::Event;
use crate::proto::{decode, encode};
use crate::server::{Broker, MAX_CONNECTIONS};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, clap::ValueEnum)]
#[serde(rename_all = "kebab-case")]
pub enum Role {
    Requester,
    Approver,
}

impl Role {
    /// The remote command a client asks for, so a key used for the wrong job fails clearly.
    pub fn command(self) -> &'static str {
        match self {
            Role::Requester => "request",
            Role::Approver => "approve",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Hello {
    pub role: Role,
    /// The requester or approver the key belongs to.
    pub name: String,
}

const MAX_HELLO: usize = 4096;

/// Written without the codec, so nothing after it is read ahead.
pub async fn write_hello<S: AsyncWrite + Unpin>(stream: &mut S, hello: &Hello) -> Result<()> {
    let data = encode(hello)?;
    stream.write_all(&(data.len() as u32).to_be_bytes()).await?;
    stream.write_all(&data).await?;
    Ok(())
}

async fn read_hello<S: AsyncRead + Unpin>(stream: &mut S) -> Result<Hello> {
    let length = stream.read_u32().await? as usize;
    ensure!(length <= MAX_HELLO, "hello too large");
    let mut data = vec![0; length];
    stream.read_exact(&mut data).await?;
    decode(&data)
}

/// The forced command: checks what the client asked for, then joins its SSH session to the broker.
pub async fn bridge(socket: &Path, role: Role, name: String) -> Result<()> {
    let asked = std::env::var("SSH_ORIGINAL_COMMAND").unwrap_or_default();
    if asked.trim() != role.command() {
        let (job, client) = match role {
            Role::Requester => ("sending requests", "slop"),
            Role::Approver => ("answering requests", "slop-approve"),
        };
        bail!("this SSH key is for {job} as {name:?}; use it with `{client}`");
    }

    let mut stream =
        UnixStream::connect(socket).await.with_context(|| format!("connecting to {}", socket.display()))?;
    write_hello(&mut stream, &Hello { role, name }).await?;
    let mut session = tokio::io::join(tokio::io::stdin(), tokio::io::stdout());
    tokio::io::copy_bidirectional(&mut session, &mut stream).await?;
    Ok(())
}

/// Remote connections, from the SSH user's forced commands only.
pub async fn listen(broker: Arc<Broker>, listener: UnixListener, ssh_uid: u32) -> Result<()> {
    let slots = Arc::new(Semaphore::new(MAX_CONNECTIONS));
    loop {
        let (mut stream, _) = listener.accept().await?;
        let uid = stream.peer_cred()?.uid();
        if uid != ssh_uid {
            broker.audit.log(Event::Unknown { peer: format!("local UID {uid} on the remote socket") });
            continue;
        }

        let Ok(slot) = slots.clone().try_acquire_owned() else { continue };
        let broker = broker.clone();
        tokio::spawn(async move {
            let hello = tokio::time::timeout(Duration::from_secs(10), read_hello(&mut stream)).await;
            match hello {
                Ok(Ok(Hello { role: Role::Requester, name })) if broker.config.remote_requester(&name) => {
                    crate::server::handle(broker, stream, name).await
                }
                Ok(Ok(Hello { role: Role::Approver, name })) if broker.config.remote_approver(&name) => {
                    let _ = crate::approve::serve(broker, stream, format!("{name} (ssh)")).await;
                }
                Ok(Ok(Hello { role, name })) => {
                    broker.audit.log(Event::Unknown { peer: format!("SSH key for {name} ({role:?})") })
                }
                _ => {}
            }
            drop(slot);
        });
    }
}

/// The client's own settings, from `~/.config/slop/config.toml` (set up by `my.slop`).
#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct ClientConfig {
    /// Where `slop` sends requests.
    broker: Option<String>,
    /// Where `slop-approve` answers them.
    approve: Option<String>,
}

fn client_config_path() -> Option<std::path::PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|d| !d.is_empty())
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| Path::new(&home).join(".config")))?;
    Some(base.join("slop/config.toml"))
}

/// Where a client connects: `$SLOP_BROKER` (or `$SLOP_APPROVE`), else the client config file,
/// else `fallback`.
pub fn address(role: Role, fallback: &str) -> Result<String> {
    let variable = match role {
        Role::Requester => "SLOP_BROKER",
        Role::Approver => "SLOP_APPROVE",
    };
    if let Ok(address) = std::env::var(variable) {
        return Ok(address);
    }

    let config = match client_config_path() {
        Some(path) if path.exists() => {
            let text = std::fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
            toml::from_str(&text).with_context(|| format!("parsing {}", path.display()))?
        }
        _ => ClientConfig::default(),
    };
    let configured = match role {
        Role::Requester => config.broker,
        Role::Approver => config.approve,
    };
    Ok(configured.unwrap_or_else(|| fallback.to_owned()))
}

/// A stream to the broker, as a client.
pub trait Stream: AsyncRead + AsyncWrite + Send + Unpin {}
impl<T: AsyncRead + AsyncWrite + Send + Unpin> Stream for T {}

/// Connects a client to `target`: `vsock:<cid>:<port>`, `unix:<path>` or `ssh:<destination>`.
/// Over SSH the destination is given to `ssh` as is, so a `Host` entry in the SSH configuration
/// can choose the key; `SLOP_SSH` can replace the `ssh` command and add options instead.
pub async fn connect(target: &str, role: Role) -> Result<Box<dyn Stream>> {
    let failed = || format!("connecting to the broker at {target}");
    if let Some(path) = target.strip_prefix("unix:") {
        return Ok(Box::new(UnixStream::connect(path).await.with_context(failed)?));
    }

    if let Some((cid, port)) = target.strip_prefix("vsock:").and_then(|a| a.split_once(':')) {
        let address = tokio_vsock::VsockAddr::new(cid.parse()?, port.parse()?);
        return Ok(Box::new(tokio_vsock::VsockStream::connect(address).await.with_context(failed)?));
    }

    if let Some(destination) = target.strip_prefix("ssh:") {
        ensure!(!destination.is_empty() && !destination.starts_with('-'), "invalid SSH destination {destination:?}");

        // Like `GIT_SSH_COMMAND`: a command and options, split on whitespace.
        let command = std::env::var("SLOP_SSH").unwrap_or_else(|_| "ssh".into());
        let mut words = command.split_whitespace();
        let mut child = tokio::process::Command::new(words.next().context("SLOP_SSH is empty")?)
            .args(words)
            .args(["-T", "--", destination, role.command()])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .spawn()
            .with_context(failed)?;

        let (stdout, stdin) = (child.stdout.take().unwrap(), child.stdin.take().unwrap());
        // ssh exits once its stdin closes; reap it then.
        tokio::spawn(async move { child.wait().await });
        return Ok(Box::new(tokio::io::join(stdout, stdin)));
    }

    bail!("the broker address must be vsock:<cid>:<port>, unix:<path> or ssh:<destination>")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn hello_leaves_the_rest_of_the_stream() {
        let (mut a, mut b) = tokio::io::duplex(1024);
        let hello = Hello { role: Role::Approver, name: "laptop".into() };
        write_hello(&mut a, &hello).await.unwrap();
        a.write_all(b"rest").await.unwrap();
        assert_eq!(read_hello(&mut b).await.unwrap(), hello);
        let mut rest = [0; 4];
        b.read_exact(&mut rest).await.unwrap();
        assert_eq!(&rest, b"rest");
    }

    #[test]
    fn reads_client_config() {
        let config: ClientConfig = toml::from_str("broker = \"ssh:slop-request\"\n").unwrap();
        assert_eq!((config.broker.as_deref(), config.approve), (Some("ssh:slop-request"), None));
        assert!(toml::from_str::<ClientConfig>("brokr = \"x\"\n").is_err());
    }

    #[tokio::test]
    async fn oversized_hellos_are_rejected() {
        let (mut a, mut b) = tokio::io::duplex(1024);
        a.write_all(&u32::MAX.to_be_bytes()).await.unwrap();
        assert!(read_hello(&mut b).await.is_err());
    }
}
