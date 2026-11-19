//! `slop`: the agents' client for the broker.
use std::num::NonZeroU16;
use std::process::exit;

use anyhow::{Context, Result, bail};
use clap::{Args, Parser, Subcommand};
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::mpsc;

use slop_broker::proto::{
    ApprovedBy, ClientMessage, DEFAULT_VSOCK_PORT, Destination, HOST_CID, OpResult, Operation, PROTOCOL_VERSION, Query,
    Request, ServerMessage, decode, encode, transport,
};
use slop_broker::types::{Arg, HostName, Lines, NodeName, Since, UnitName, UserName};

/// Exit status when the broker didn't run the operation (denied, expired, invalid or failed).
const NOT_RUN: i32 = 125;

const GUIDE: &str = include_str!("../../slop-tools.md");

#[derive(Parser)]
#[command(
    about = "Ask the slop broker to run privileged operations",
    after_help = "Requests wait up to five minutes for an approver; don't retry them in a loop.\n\
                  Exit status 125 means the broker did not run the operation.\n\
                  SLOP_BROKER selects the broker: vsock:<cid>:<port> or unix:<path>."
)]
struct Cli {
    /// Who is asking and why; shown to the approver as agent-supplied.
    #[arg(long, env = "SLOP_LABEL", global = true)]
    label: Option<String>,
    /// Print structured results as JSON.
    #[arg(long, global = true)]
    json: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Args)]
struct Target {
    /// Deploy node, or user@host with --host.
    target: String,
    /// Treat TARGET as user@host instead of a deploy node.
    #[arg(long)]
    host: bool,
    /// SSH port, with --host.
    #[arg(short, long)]
    port: Option<NonZeroU16>,
}

impl Target {
    fn destination(&self) -> Result<Destination> {
        if !self.host {
            if self.port.is_some() {
                bail!("--port needs --host; deploy nodes use their configured port");
            }
            return Ok(Destination::Node(parse::<NodeName>(&self.target)?));
        }

        let (user, host) = self.target.rsplit_once('@').context("--host needs user@host")?;
        let port = self.port.unwrap_or(NonZeroU16::new(22).unwrap());
        Ok(Destination::Host { user: parse::<UserName>(user)?, host: parse::<HostName>(host)?, port })
    }
}

fn parse<T: std::str::FromStr<Err = String>>(value: &str) -> Result<T> {
    value.parse().map_err(anyhow::Error::msg)
}

#[derive(Subcommand)]
enum Command {
    /// Run a command over SSH on a deploy node, or on any host with --host.
    Ssh {
        #[command(flatten)]
        target: Target,
        /// Remote command, after `--`; joined with spaces and run by the remote shell, as ssh does.
        #[arg(last = true)]
        command: Vec<Arg>,
    },
    /// `systemctl status` on a box, of one unit or overall.
    Status {
        #[command(flatten)]
        target: Target,
        unit: Option<UnitName>,
    },
    /// A unit's journal on a box.
    Logs {
        #[command(flatten)]
        target: Target,
        unit: UnitName,
        /// Lines to show (1-5000).
        #[arg(short = 'n', long, default_value = "200")]
        lines: Lines,
        /// Start time: a duration back from now (30m, 2h, 1d) or a date (2026-01-31 12:00).
        #[arg(long)]
        since: Option<Since>,
    },
    /// Failed units on a box.
    Failed {
        #[command(flatten)]
        target: Target,
    },
    /// Show your pending requests and active leases.
    Requests,
    /// Print the guide for agents.
    Guide,
}

fn operation(command: Command) -> Result<Operation> {
    Ok(match command {
        Command::Ssh { target, command } => Operation::Ssh { destination: target.destination()?, command },
        Command::Status { target, unit } => {
            Operation::Query { destination: target.destination()?, query: Query::Status { unit } }
        }
        Command::Logs { target, unit, lines, since } => {
            Operation::Query { destination: target.destination()?, query: Query::Logs { unit, lines, since } }
        }
        Command::Failed { target } => Operation::Query { destination: target.destination()?, query: Query::Failed },
        Command::Requests => Operation::Requests,
        Command::Guide => unreachable!(),
    })
}

/// The working directory's name, so approvers can tell agents apart.
fn default_label() -> Option<String> {
    let directory = std::env::current_dir().ok()?;
    Some(format!("in {}", directory.file_name()?.to_string_lossy()))
}

trait Stream: AsyncRead + AsyncWrite + Send + Unpin {}
impl<T: AsyncRead + AsyncWrite + Send + Unpin> Stream for T {}

async fn connect() -> Result<Box<dyn Stream>> {
    let target = std::env::var("SLOP_BROKER").unwrap_or_else(|_| format!("vsock:{HOST_CID}:{DEFAULT_VSOCK_PORT}"));
    let failed = || format!("connecting to the broker at {target}");
    if let Some(path) = target.strip_prefix("unix:") {
        return Ok(Box::new(tokio::net::UnixStream::connect(path).await.with_context(failed)?));
    }
    if let Some((cid, port)) = target.strip_prefix("vsock:").and_then(|a| a.split_once(':')) {
        let address = tokio_vsock::VsockAddr::new(cid.parse()?, port.parse()?);
        return Ok(Box::new(tokio_vsock::VsockStream::connect(address).await.with_context(failed)?));
    }
    bail!("SLOP_BROKER must be vsock:<cid>:<port> or unix:<path>")
}

#[tokio::main]
async fn main() {
    // Usage errors also mean nothing ran; help and version are not errors.
    let cli = Cli::try_parse().unwrap_or_else(|error| {
        let _ = error.print();
        exit(if error.use_stderr() { NOT_RUN } else { 0 })
    });

    let status = match run(cli).await {
        Ok(status) => status,
        Err(error) => {
            eprintln!("slop: {error:#}");
            NOT_RUN
        }
    };

    // Don't wait for a blocked read of our stdin.
    exit(status);
}

async fn run(cli: Cli) -> Result<i32> {
    if let Command::Guide = cli.command {
        print!("{GUIDE}");
        return Ok(0);
    }

    let request = Request {
        version: PROTOCOL_VERSION,
        label: cli.label.or_else(default_label),
        operation: operation(cli.command)?,
    };

    let (mut sink, mut source) = transport(connect().await?).split();

    // One writer for the request and any stdin.
    let (tx, mut rx) = mpsc::channel::<ClientMessage>(16);
    tokio::spawn(async move {
        while let Some(message) = rx.recv().await {
            let Ok(data) = encode(&message) else { break };
            if sink.send(data).await.is_err() {
                break;
            }
        }
    });
    tx.send(ClientMessage::Request(request)).await?;

    let (mut stdout, mut stderr) = (tokio::io::stdout(), tokio::io::stderr());
    loop {
        let frame = source.next().await.context("the broker closed the connection")??;
        match decode::<ServerMessage>(&frame)? {
            ServerMessage::Pending { id, summary } => {
                eprintln!("slop: waiting for approval of `{summary}` (request {id})…")
            }
            ServerMessage::Approved { by, stdin } => {
                match by {
                    ApprovedBy::Lease => eprintln!("slop: approved (lease)"),
                    ApprovedBy::Approver => eprintln!("slop: approved"),
                    ApprovedBy::Policy => {}
                }
                if stdin {
                    tokio::spawn(forward_stdin(tx.clone()));
                }
            }
            ServerMessage::Info(message) => eprintln!("slop: {message}"),
            ServerMessage::Stdout(data) => {
                stdout.write_all(&data).await?;
                stdout.flush().await?;
            }
            ServerMessage::Stderr(data) => {
                stderr.write_all(&data).await?;
                stderr.flush().await?;
            }
            ServerMessage::Finished { exit, result } => {
                if let Some(result) = result {
                    show(&result, cli.json)?;
                }
                return Ok(exit);
            }
            ServerMessage::Denied(reason) => {
                eprintln!("slop: {reason}");
                return Ok(NOT_RUN);
            }
            ServerMessage::Expired => {
                eprintln!("slop: no answer from an approver in time");
                return Ok(NOT_RUN);
            }
            ServerMessage::Error(message) => {
                eprintln!("slop: {message}");
                return Ok(NOT_RUN);
            }
        }
    }
}

fn show(result: &OpResult, json: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(result)?);
        return Ok(());
    }

    match result {
        OpResult::Requests { pending, leases } => {
            if pending.is_empty() && leases.is_empty() {
                println!("No pending requests or leases.");
            }
            for entry in pending {
                println!("pending {}  {}  (expires in {}s)", entry.id, entry.summary, entry.expires_in);
            }
            for lease in leases {
                println!("lease    {}  ({}s left)", lease.scope, lease.remaining);
            }
        }
    }
    Ok(())
}

async fn forward_stdin(tx: mpsc::Sender<ClientMessage>) {
    let mut stdin = tokio::io::stdin();
    let mut buffer = vec![0; 64 * 1024];
    loop {
        match stdin.read(&mut buffer).await {
            Ok(0) | Err(_) => {
                let _ = tx.send(ClientMessage::StdinEnd).await;
                return;
            }
            Ok(n) => {
                if tx.send(ClientMessage::Stdin(buffer[..n].to_vec())).await.is_err() {
                    return;
                }
            }
        }
    }
}
