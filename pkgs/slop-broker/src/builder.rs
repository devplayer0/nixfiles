//! Builds commits for deploys. The broker runs `slop-broker builder` over SSH as a user without
//! keys (the key's forced command). It sends a [`BuildRequest`] on stdin and gets a
//! [`BuildResult`] back on stdout, each one frame like the rest of the protocol; build logs come
//! on stderr and go to the requester.
//!
//! The builder fetches the commit from the Git server itself, so the requester never supplies
//! the source, and evaluates it there: evaluation runs agent-written Nix, which is why it happens
//! here and not in the broker.
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio_util::codec::{FramedRead, FramedWrite};
use tokio_util::sync::CancellationToken;

use crate::exec::Output;
use crate::proto::{ServerMessage, codec, decode, encode};
use crate::types::{CommitId, DeployTarget};

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BuilderConfig {
    /// Where commits are fetched from, such as `git@git.nul.ie:dev/nixfiles.git`.
    pub repository: String,
    /// Read-only key for the repository.
    pub key: PathBuf,
    /// Branch that commit lists are shown relative to.
    #[serde(default = "default_branch")]
    pub branch: String,
    /// Writable state: the repository mirror, `known_hosts` and caches.
    pub directory: PathBuf,
    /// Directories with `git`, `nix` and `ssh`.
    pub path: Vec<PathBuf>,
}

fn default_branch() -> String {
    "master".into()
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BuildRequest {
    pub commit: CommitId,
    pub targets: Vec<DeployTarget>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BuildResult {
    /// `git log` of the commits since the branch, one per line (agent-written messages).
    pub log: String,
    /// `git diff --stat` since the branch.
    pub stat: String,
    /// Every profile to activate, nodes in request order and profiles in deploy-rs's order.
    pub profiles: Vec<BuiltProfile>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BuiltProfile {
    pub node: String,
    pub profile: String,
    /// The built profile (deploy-rs's activation wrapper around the system).
    pub path: String,
    /// Where it's installed on the node.
    pub profile_path: String,
}

/// Store paths, checked so the broker can put them in remote commands.
pub fn is_store_path(path: &str) -> bool {
    let Some(name) = path.strip_prefix("/nix/store/") else { return false };
    let b = name.as_bytes();
    b.len() > 33
        && b[..32].iter().all(|c| c.is_ascii_digit() || c.is_ascii_lowercase())
        && b[32] == b'-'
        && b[33..].iter().all(|&c| c.is_ascii_alphanumeric() || b"+-._?=".contains(&c))
}

/// Profile paths, checked the same way; deploy-rs installs into `/nix/var/nix/profiles`.
pub fn is_profile_path(path: &str) -> bool {
    let Some(rest) = path.strip_prefix("/nix/var/nix/profiles/") else { return false };
    !rest.is_empty()
        && rest.split('/').all(|part| !part.is_empty() && part != "." && part != "..")
        && rest.bytes().all(|c| c.is_ascii_alphanumeric() || b"/_-.".contains(&c))
}

impl BuildResult {
    fn check(&self) -> Result<()> {
        for profile in &self.profiles {
            ensure!(is_store_path(&profile.path), "the builder returned an invalid path {:?}", profile.path);
            ensure!(is_profile_path(&profile.profile_path), "invalid profile path {:?}", profile.profile_path);
        }
        Ok(())
    }
}

// The broker's side

/// Runs a build and returns what to deploy. Build output goes to `out` as it happens.
pub async fn build(
    ssh: &crate::config::SshConfig,
    deploy: &crate::config::DeployConfig,
    request: &BuildRequest,
    out: &Output,
    cancel: &CancellationToken,
) -> Result<BuildResult> {
    let mut command = crate::ops::ssh::command_to(ssh, &deploy.builder, &["build"]);
    command.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).kill_on_drop(true);
    let mut child = command.spawn().context("starting the builder")?;

    // Stdin stays open afterwards: the builder stops when it closes.
    let mut stdin = FramedWrite::new(child.stdin.take().unwrap(), codec());
    stdin.send(encode(request)?).await?;

    let mut stderr = child.stderr.take().unwrap();
    let out = out.clone();
    let logs = tokio::spawn(async move {
        let mut buffer = vec![0; 64 * 1024];
        while let Ok(n @ 1..) = stderr.read(&mut buffer).await {
            out.send(ServerMessage::Stderr(buffer[..n].to_vec())).await;
        }
    });

    let mut stdout = FramedRead::new(child.stdout.take().unwrap(), codec());
    let (frame, status) = tokio::select! {
        result = async {
            let frame = stdout.next().await.transpose()?;
            anyhow::Ok((frame, child.wait().await?))
        } => result?,
        _ = cancel.cancelled() => bail!("requester disconnected"),
    };
    drop(stdin);
    let _ = tokio::time::timeout(Duration::from_secs(5), logs).await;

    ensure!(status.success(), "the build failed; its output is above");
    let result: BuildResult = decode(&frame.context("the builder sent no result")?)?;
    result.check()?;
    Ok(result)
}

// The builder's side

/// The forced command: one build per connection, one at a time.
pub async fn worker(config: &Path) -> Result<()> {
    let text = std::fs::read_to_string(config).with_context(|| format!("reading {}", config.display()))?;
    let config: BuilderConfig = toml::from_str(&text)?;

    let mut stdin = FramedRead::new(tokio::io::stdin(), codec());
    let request: BuildRequest = decode(&stdin.next().await.context("no request")??)?;
    // Nothing else comes on stdin; it closing means the broker gave up.
    let closed = async move { while let Some(Ok(_)) = stdin.next().await {} };

    tokio::select! {
        result = async {
            let _lock = lock(&config.directory.join("build.lock")).await?;
            run(&config, &request).await
        } => {
            let mut stdout = FramedWrite::new(tokio::io::stdout(), codec());
            stdout.send(encode(&result?)?).await?;
            // Not a return: the runtime would wait for the blocked read of stdin, which the broker
            // keeps open until this exits.
            std::process::exit(0)
        }
        _ = closed => bail!("the broker went away"),
    }
}

/// Waits for the lock, saying so if it's held.
async fn lock(path: &Path) -> Result<std::fs::File> {
    use std::os::fd::AsRawFd;

    let file = std::fs::File::create(path)?;
    let mut said = false;
    while unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        if !said {
            eprintln!("Waiting for another build to finish…");
            said = true;
        }
        tokio::time::sleep(Duration::from_secs(2)).await;
    }
    Ok(file)
}

fn command(config: &BuilderConfig, program: &str) -> Command {
    let path = std::env::join_paths(&config.path).unwrap_or_default();
    let ssh = format!(
        "ssh -F none -i {} -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes \
         -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile={}",
        config.key.display(),
        config.directory.join("known_hosts").display()
    );

    let mut command = Command::new(program);
    command
        .env_clear()
        .env("PATH", path)
        .env("HOME", &config.directory)
        .env("XDG_CACHE_HOME", config.directory.join("cache"))
        .env("GIT_SSH_COMMAND", ssh)
        .stdin(Stdio::null())
        .kill_on_drop(true);
    command
}

/// Runs a command for its output; its stderr goes along with the error if it fails.
async fn output(command: &mut Command) -> Result<String> {
    let output = command.stderr(Stdio::piped()).output().await?;
    if !output.status.success() {
        bail!("{}", String::from_utf8_lossy(&output.stderr).trim());
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn git(config: &BuilderConfig, repository: &Path) -> Command {
    let mut command = command(config, "git");
    command.arg("-C").arg(repository);
    command
}

const NIX_OPTIONS: [&str; 6] = [
    "--extra-experimental-features",
    "nix-command flakes",
    "--option",
    "accept-flake-config",
    "false",
    "--no-write-lock-file",
];

/// A deploy-rs node's profiles, as `nix eval --json` prints them.
#[derive(Deserialize)]
struct NodeProfiles {
    order: Vec<String>,
    profiles: BTreeMap<String, ProfileInfo>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProfileInfo {
    profile_path: Option<String>,
    user: Option<String>,
}

/// What deploy-rs would deploy for `target`: the node's profiles in its order, or the one named.
fn select(target: &DeployTarget, node: &NodeProfiles) -> Result<Vec<(String, String)>> {
    let names: Vec<&String> = match target.profile() {
        Some(profile) => {
            vec![node.profiles.keys().find(|p| *p == profile).with_context(|| format!("{target}: no such profile"))?]
        }
        None => {
            let mut names: Vec<&String> = node.order.iter().filter(|p| node.profiles.contains_key(*p)).collect();
            names.extend(node.profiles.keys().filter(|p| !node.order.contains(p)));
            names
        }
    };

    names
        .into_iter()
        .map(|name| {
            let info = &node.profiles[name];
            ensure!(
                info.user.as_deref().unwrap_or("root") == "root",
                "{}.{name}: only profiles deployed as root are supported",
                target.node()
            );

            let path = info.profile_path.clone().unwrap_or_else(|| format!("/nix/var/nix/profiles/{name}"));
            ensure!(is_profile_path(&path), "{}.{name}: invalid profile path {path:?}", target.node());
            Ok((name.clone(), path))
        })
        .collect()
}

async fn run(config: &BuilderConfig, request: &BuildRequest) -> Result<BuildResult> {
    let commit = &request.commit;
    let repository = config.directory.join("nixfiles.git");
    if !repository.exists() {
        output(command(config, "git").args(["init", "--quiet", "--bare"]).arg(&repository)).await?;
    }

    eprintln!("Fetching {}…", config.repository);
    output(git(config, &repository).args([
        "fetch",
        "--quiet",
        "--prune",
        "--no-tags",
        &config.repository,
        "+refs/heads/*:refs/remotes/origin/*",
    ]))
    .await
    .context("fetching")?;
    if output(git(config, &repository).args(["cat-file", "-e", &format!("{commit}^{{commit}}")])).await.is_err() {
        bail!("commit {commit} isn't on any branch of {}; push it first", config.repository);
    }

    // What approvers see of the commits
    let branch = format!("refs/remotes/origin/{}", config.branch);
    let base = output(git(config, &repository).args(["merge-base", commit, &branch])).await.ok();
    let (log, stat) = match base.as_deref().map(str::trim) {
        Some(base) if base != &**commit => {
            let range = format!("{base}..{commit}");
            let log =
                output(git(config, &repository).args(["log", "--format=%h %s", "--max-count=30", &range])).await?;
            let stat =
                output(git(config, &repository).args(["diff", "--stat=100", "--stat-count=40", base, commit])).await?;
            (log, stat)
        }
        Some(_) => (format!("(on {})\n", config.branch), String::new()),
        None => (format!("(not based on {})\n", config.branch), String::new()),
    };

    // Which profiles each target means
    let flake = format!("git+file://{}?rev={commit}", repository.display());
    let apply = "n: { order = n.profilesOrder or [ ]; profiles = builtins.mapAttrs (_: p: \
                 { profilePath = p.profilePath or null; user = p.user or n.user or null; }) n.profiles; }";
    let mut profiles = Vec::new();
    for target in &request.targets {
        eprintln!("Evaluating {target}…");
        let node = output(
            command(config, "nix")
                .args(["eval", "--json"])
                .args(NIX_OPTIONS)
                .arg(format!("{flake}#deploy.nodes.\"{}\"", target.node()))
                .args(["--apply", apply]),
        )
        .await
        .with_context(|| format!("evaluating {}", target.node()))?;
        let node: NodeProfiles = serde_json::from_str(&node)?;

        for (profile, profile_path) in select(target, &node)? {
            if !profiles.iter().any(|p: &BuiltProfile| p.node == target.node() && p.profile == profile) {
                profiles.push(BuiltProfile { node: target.node().into(), profile, path: String::new(), profile_path });
            }
        }
    }

    // Logs go to the broker as they happen; only the result is read.
    eprintln!("Building…");
    let installables =
        profiles.iter().map(|p| format!("{flake}#deploy.nodes.\"{}\".profiles.\"{}\".path", p.node, p.profile));
    // Not `output()`, which would capture stderr too, whatever it's set to.
    let built = command(config, "nix")
        .args(["build", "--no-link", "--json", "--print-build-logs"])
        .args(NIX_OPTIONS)
        .args(installables)
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?
        .wait_with_output()
        .await?;
    ensure!(built.status.success(), "nix build failed");

    #[derive(Deserialize)]
    struct Built {
        outputs: BTreeMap<String, String>,
    }
    let built: Vec<Built> = serde_json::from_slice(&built.stdout).context("reading nix build's result")?;
    ensure!(
        built.len() == profiles.len(),
        "nix build returned {} results for {} profiles",
        built.len(),
        profiles.len()
    );
    for (profile, built) in profiles.iter_mut().zip(built) {
        profile.path = built.outputs.get("out").context("no out output")?.clone();
    }

    let result = BuildResult { log, stat, profiles };
    result.check()?;
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checks_paths() {
        assert!(is_store_path("/nix/store/0123456789abcdfghijklmnpqrsvwxyz-activatable-nixos-system-sfh"));
        for bad in [
            "/nix/store/0123456789abcdfghijklmnpqrsvwxyz",
            "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-a b",
            "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-a;b",
            "/tmp/x",
        ] {
            assert!(!is_store_path(bad), "{bad}");
        }

        assert!(is_profile_path("/nix/var/nix/profiles/per-container/hass/system"));
        for bad in ["/nix/var/nix/profiles/../../etc", "/nix/var/nix/profiles/", "/etc/x", "/nix/var/nix/profiles/a b"]
        {
            assert!(!is_profile_path(bad), "{bad}");
        }
    }

    #[test]
    fn selects_profiles_like_deploy_rs() {
        let node: NodeProfiles = serde_json::from_str(
            r#"{ "order": ["system"], "profiles": {
                "container-b": { "profilePath": "/nix/var/nix/profiles/per-container/b/system", "user": "root" },
                "container-a": { "profilePath": "/nix/var/nix/profiles/per-container/a/system", "user": "root" },
                "system": { "profilePath": null, "user": "root" } } }"#,
        )
        .unwrap();

        let all = select(&"shill".parse().unwrap(), &node).unwrap();
        assert_eq!(all.iter().map(|(p, _)| p.as_str()).collect::<Vec<_>>(), ["system", "container-a", "container-b"]);
        assert_eq!(all[0].1, "/nix/var/nix/profiles/system");
        assert_eq!(select(&"shill.container-b".parse().unwrap(), &node).unwrap().len(), 1);
        assert!(select(&"shill.nope".parse().unwrap(), &node).is_err());

        let user: NodeProfiles =
            serde_json::from_str(r#"{ "order": [], "profiles": { "home": { "profilePath": null, "user": "dev" } } }"#)
                .unwrap();
        assert!(select(&"castle".parse().unwrap(), &user).is_err());
    }
}
