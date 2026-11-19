//! Commands over SSH with the broker's key, to configured targets or explicit `user@host`s.
use anyhow::{Result, bail};
use serde_json::{Map, Value, json};
use tokio::process::Command;

use crate::config::{SshConfig, SshTarget, credential};
use crate::exec::{self, Io};
use crate::proto::Destination;
use crate::server::Broker;
use crate::types::Arg;

/// Fails if `destination` names a target the broker doesn't know.
pub fn check(config: &SshConfig, destination: &Destination) -> Result<()> {
    if let Destination::Node(node) = destination
        && !config.targets.contains_key(&**node)
    {
        bail!("unknown node {node}; use --host for other boxes");
    }
    Ok(())
}

pub fn scope(destination: &Destination) -> Map<String, Value> {
    let value = match destination {
        Destination::Node(node) => json!({ "target": node }),
        Destination::Host { user, host, port } => json!({ "host": format!("{user}@{host}"), "port": port.get() }),
    };
    value.as_object().unwrap().clone()
}

pub fn describe(destination: &Destination) -> String {
    match destination {
        Destination::Node(node) => node.to_string(),
        Destination::Host { user, host, port } => format!("{user}@{host} port {port} (host)"),
    }
}

/// Options for every connection; they come before any from target config, so they win.
pub fn options(config: &SshConfig) -> Vec<String> {
    let mut options: Vec<String> = vec!["-F".into(), "none".into(), "-i".into()];
    options.push(credential(&config.key).to_string_lossy().into_owned());
    for option in [
        "IdentitiesOnly=yes",
        "IdentityAgent=none",
        "BatchMode=yes",
        "StrictHostKeyChecking=accept-new",
        "UpdateHostKeys=no",
        "ForwardAgent=no",
        "ForwardX11=no",
        "ClearAllForwardings=yes",
        "PermitLocalCommand=no",
        "ConnectTimeout=15",
        // Keeps notices like "Permanently added … to the list of known hosts" out of the output
        "LogLevel=ERROR",
    ] {
        options.extend(["-o".into(), option.into()]);
    }
    options.extend(["-o".into(), format!("UserKnownHostsFile={}", config.known_hosts.display())]);
    options
}

/// The `ssh` invocation; every option comes from here or trusted target config.
pub fn command<S: AsRef<str>>(config: &SshConfig, destination: &Destination, remote: &[S]) -> Command {
    let mut command = Command::new(&config.ssh);
    command.env_clear().env("PATH", "/run/current-system/sw/bin").env("HOME", "/var/empty");
    command.arg("-T").args(options(config));

    match destination {
        Destination::Node(node) => {
            let target = &config.targets[&**node];
            command.args(&target.ssh_opts).args(["-l", &target.user, "--", &target.hostname]);
        }
        Destination::Host { user, host, port } => {
            command.args(["-p", &port.to_string(), "-l", user, "--", host]);
        }
    }

    command.args(remote.iter().map(AsRef::as_ref));
    command
}

/// The same, to a target that isn't a node (such as the builder).
pub fn command_to<S: AsRef<str>>(config: &SshConfig, target: &SshTarget, remote: &[S]) -> Command {
    let mut command = Command::new(&config.ssh);
    command.env_clear().env("PATH", "/run/current-system/sw/bin").env("HOME", "/var/empty");
    command.arg("-T").args(options(config));
    command.args(&target.ssh_opts).args(["-l", &target.user, "--", &target.hostname]);
    command.args(remote.iter().map(AsRef::as_ref));
    command
}

pub async fn execute(broker: &Broker, destination: &Destination, remote: &[Arg], io: &mut Io) -> Result<i32> {
    let config = broker.config.ssh.as_ref().unwrap();
    exec::run(command(config, destination, remote), io, true).await
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::collections::BTreeMap;

    pub fn config() -> SshConfig {
        let mut targets = BTreeMap::new();
        targets.insert(
            "river".into(),
            SshTarget {
                hostname: "river.h.nul.ie".into(),
                user: "deploy".into(),
                ssh_opts: vec!["-p".into(), "2222".into()],
                sudo: "doas -u".into(),
            },
        );
        SshConfig { ssh: "ssh".into(), key: "/key".into(), known_hosts: "/kh".into(), targets }
    }

    #[test]
    fn unknown_nodes_are_refused() {
        assert!(check(&config(), &Destination::Node("river".parse().unwrap())).is_ok());
        assert!(check(&config(), &Destination::Node("sfh".parse().unwrap())).is_err());
    }

    #[test]
    fn trusted_options_come_before_the_destination() {
        let command = command(&config(), &Destination::Node("river".parse().unwrap()), &["-oProxyCommand=x"]);
        let args: Vec<_> = command.as_std().get_args().map(|a| a.to_string_lossy().into_owned()).collect();
        let separator = args.iter().position(|a| a == "--").unwrap();
        assert_eq!(&args[separator - 3..], ["2222", "-l", "deploy", "--", "river.h.nul.ie", "-oProxyCommand=x"]);
        assert!(args.contains(&"IdentityAgent=none".to_owned()));
    }
}
