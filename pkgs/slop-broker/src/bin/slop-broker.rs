//! The broker daemon, and `slop-approve` (the same binary, by name) for approvers.
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result};
use clap::Parser;

use slop_broker::config::{Config, credential, group_id};
use slop_broker::server::{self, Broker};
use slop_broker::{approve, ha};

#[derive(Parser)]
#[command(about = "Approval broker for coding agents")]
enum Command {
    /// Run the broker.
    Serve {
        #[arg(long)]
        config: PathBuf,
    },
    /// Answer requests (also available as `slop-approve`).
    Approve {
        #[arg(long, default_value = DEFAULT_APPROVE_SOCKET)]
        socket: PathBuf,
        args: Vec<String>,
    },
}

const DEFAULT_APPROVE_SOCKET: &str = "/run/slop-broker/approve.sock";

#[tokio::main]
async fn main() {
    let mut args: Vec<String> = std::env::args().collect();
    let name = args.first().and_then(|a| a.rsplit('/').next()).unwrap_or_default().to_owned();

    let result = if name == "slop-approve" {
        let socket =
            std::env::var_os("SLOP_APPROVE_SOCKET").map(PathBuf::from).unwrap_or(DEFAULT_APPROVE_SOCKET.into());
        approve_cli();
        approve::main(&socket, &args.split_off(1)).await
    } else {
        match Command::parse() {
            Command::Serve { config } => serve(&config).await,
            Command::Approve { socket, args } => {
                approve_cli();
                approve::main(&socket, &args).await
            }
        }
    };

    if let Err(error) = result {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}

/// Lets `slop-approve … | head` end quietly, like other command-line tools. Not for the daemon,
/// which must survive peers closing sockets.
fn approve_cli() {
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_DFL) };
}

async fn serve(path: &Path) -> Result<()> {
    let config = Config::load(path)?;
    let _ = rustls::crypto::ring::default_provider().install_default();

    let home_assistant = match &config.home_assistant {
        Some(settings) => {
            ha::validate(settings)?;
            let token = std::fs::read_to_string(credential(&settings.token)).context("reading Home Assistant token")?;
            let token = token.trim().to_owned();
            anyhow::ensure!(!token.is_empty(), "Home Assistant token is empty");
            Some((settings.clone(), token))
        }
        None => None,
    };

    server::check_runtime_dir(&config.approve_socket)?;
    let approve_listener = server::bind_unix(&config.approve_socket, 0o660, Some(group_id(&config.approver_group)?))?;
    let request_listener = match &config.request_socket {
        Some(path) => {
            server::check_runtime_dir(path)?;
            Some(server::bind_unix(path, 0o666, None)?)
        }
        None => None,
    };

    let broker = Arc::new(Broker::new(config)?);
    let mut tasks = tokio::task::JoinSet::new();
    tasks.spawn(approve::listen(broker.clone(), approve_listener));
    if let Some(listener) = request_listener {
        tasks.spawn(server::listen_unix(broker.clone(), listener));
    }
    if let Some(port) = broker.config.vsock_port {
        tasks.spawn(server::listen_vsock(broker.clone(), port));
    }
    if let Some((settings, token)) = home_assistant {
        let broker = broker.clone();
        tasks.spawn(async move {
            ha::run(broker, settings, token).await;
            Ok(())
        });
    }

    eprintln!("<6>slop-broker ready");
    // Any listener failing is fatal; systemd restarts the broker.
    tasks.join_next().await.context("no listeners")???;
    anyhow::bail!("a listener stopped")
}
