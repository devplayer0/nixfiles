//! Runs processes for approved requests, wired to the requester's stdin, stdout and stderr
//! (carried as messages).
use std::process::{ExitStatus, Stdio};
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use crate::proto::ServerMessage;

/// Messages on their way back to the requester.
#[derive(Clone)]
pub struct Output(pub mpsc::Sender<ServerMessage>);

impl Output {
    pub async fn send(&self, message: ServerMessage) {
        let _ = self.0.send(message).await;
    }

    pub async fn info(&self, message: impl Into<String>) {
        self.send(ServerMessage::Info(message.into())).await;
    }
}

/// The requester's side of an approved operation.
pub struct Io {
    /// Chunks of the requester's stdin; closed at EOF.
    pub stdin: mpsc::Receiver<Vec<u8>>,
    pub out: Output,
    /// Cancelled when the requester disconnects.
    pub cancel: CancellationToken,
}

pub fn exit_code(status: ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(0))
}

/// Runs `command` in its own process group with the requester's stdio. If the requester goes
/// away, the whole group is terminated.
pub async fn run(mut command: Command, io: &mut Io, with_stdin: bool) -> Result<i32> {
    command
        .stdin(if with_stdin { Stdio::piped() } else { Stdio::null() })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .kill_on_drop(true);

    let mut child = spawn(&mut command).await?;
    let pid = child.id().context("process exited immediately")? as i32;

    let stdout = tokio::spawn(pump(child.stdout.take().unwrap(), io.out.clone(), ServerMessage::Stdout));
    let stderr = tokio::spawn(pump(child.stderr.take().unwrap(), io.out.clone(), ServerMessage::Stderr));

    let mut child_stdin = child.stdin.take();
    let stdin_rx = &mut io.stdin;
    let feed = async move {
        if let Some(pipe) = child_stdin.as_mut() {
            while let Some(chunk) = stdin_rx.recv().await {
                if chunk.is_empty() || pipe.write_all(&chunk).await.is_err() {
                    break;
                }
            }
        }
        drop(child_stdin);
        std::future::pending::<()>().await
    };
    tokio::pin!(feed);

    let status = tokio::select! {
        status = child.wait() => status?,
        _ = &mut feed => unreachable!(),
        _ = io.cancel.cancelled() => {
            terminate(pid, &mut child).await;
            bail!("requester disconnected");
        }
    };

    // Output still buffered in the pipes belongs before the exit status.
    let _ = tokio::time::timeout(Duration::from_secs(5), async {
        let _ = stdout.await;
        let _ = stderr.await;
    })
    .await;
    Ok(exit_code(status))
}

/// Runs `command` without the requester's stdio and returns its stdout.
pub async fn capture(mut command: Command, cancel: &CancellationToken) -> Result<(i32, Vec<u8>, Vec<u8>)> {
    command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0).kill_on_drop(true);
    let child = spawn(&mut command).await?;
    tokio::select! {
        output = child.wait_with_output() => {
            let output = output?;
            Ok((exit_code(output.status), output.stdout, output.stderr))
        }
        _ = cancel.cancelled() => bail!("requester disconnected"),
    }
}

/// Spawns, retrying briefly if the executable is still open for writing in a forked child.
async fn spawn(command: &mut Command) -> Result<tokio::process::Child> {
    for _ in 0..20 {
        match command.spawn() {
            Err(error) if error.raw_os_error() == Some(libc::ETXTBSY) => {
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
            result => return result.context("failed to start process"),
        }
    }
    command.spawn().context("failed to start process")
}

async fn terminate(pid: i32, child: &mut tokio::process::Child) {
    unsafe { libc::killpg(pid, libc::SIGTERM) };
    if tokio::time::timeout(Duration::from_secs(5), child.wait()).await.is_err() {
        unsafe { libc::killpg(pid, libc::SIGKILL) };
        let _ = child.wait().await;
    }
}

async fn pump(mut reader: impl AsyncRead + Unpin, out: Output, wrap: fn(Vec<u8>) -> ServerMessage) {
    let mut buffer = vec![0; 64 * 1024];
    loop {
        match reader.read(&mut buffer).await {
            Ok(0) | Err(_) => break,
            Ok(n) => out.send(wrap(buffer[..n].to_vec())).await,
        }
    }
}
