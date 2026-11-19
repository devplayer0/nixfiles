//! The broker daemon, and `slop-approve` (the same binary, by name) for approvers.
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result};
use clap::Parser;

use slop_broker::config::{Config, credential, group_id, user_id};
use slop_broker::remote::{self, Role};
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
        /// unix:<path> or ssh:<destination>; defaults like `slop-approve`'s.
        #[arg(long)]
        broker: Option<String>,
        args: Vec<String>,
    },
    /// Forced command for the builder's SSH key: builds one request read from stdin.
    Builder {
        #[arg(long)]
        config: PathBuf,
    },
    /// Forced command for SSH keys: joins the session to the broker as the key's owner.
    Remote {
        #[arg(long, default_value = "/run/slop-broker/remote.sock")]
        socket: PathBuf,
        role: Role,
        name: String,
    },
}

#[tokio::main]
async fn main() {
    let mut args: Vec<String> = std::env::args().collect();
    let name = args.first().and_then(|a| a.rsplit('/').next()).unwrap_or_default().to_owned();

    let result = if name == "slop-approve" {
        approve_cli();
        match remote::address(Role::Approver, approve::DEFAULT_ADDRESS) {
            Ok(address) => approve::main(&address, &args.split_off(1)).await,
            Err(error) => Err(error),
        }
    } else {
        match Command::parse() {
            Command::Serve { config } => serve(&config).await,
            Command::Approve { broker, args } => {
                approve_cli();
                match broker.map_or_else(|| remote::address(Role::Approver, approve::DEFAULT_ADDRESS), Ok) {
                    Ok(address) => approve::main(&address, &args).await,
                    Err(error) => Err(error),
                }
            }
            Command::Remote { socket, role, name } => remote::bridge(&socket, role, name).await,
            Command::Builder { config } => slop_broker::builder::worker(&config).await,
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

    let remote_listener = match &config.remote {
        Some(settings) => {
            server::check_runtime_dir(&settings.socket)?;
            // Open to the SSH user's group; connections from anyone but the user are refused.
            let (uid, gid) = user_id(&settings.user)?;
            Some((server::bind_unix(&settings.socket, 0o660, Some(gid))?, uid))
        }
        None => None,
    };

    let broker = Arc::new(Broker::new(config)?);
    let mut tasks = tokio::task::JoinSet::new();
    tasks.spawn(approve::listen(broker.clone(), approve_listener));
    if let Some(listener) = request_listener {
        tasks.spawn(server::listen_unix(broker.clone(), listener));
    }
    if let Some((listener, uid)) = remote_listener {
        tasks.spawn(remote::listen(broker.clone(), listener, uid));
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
