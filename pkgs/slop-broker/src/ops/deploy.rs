//! `deploy`: build a pushed commit, show approvers what it changes on each node, then activate it
//! on all of them at once.
//!
//! Before approval nothing runs as root and no agent-written code runs on a node: the builder
//! evaluates and builds, the broker copies the closures to the nodes, and a fixed read-only
//! script compares them with what the nodes have. Activation (deploy-rs's `activate-rs`) runs
//! only once approved, in a transient unit, so it finishes even if the connection drops.
use std::collections::BTreeMap;

use anyhow::{Context, Result, bail, ensure};
use futures_util::future::join_all;
use serde_json::json;
use tokio::process::Command;

use super::{Parsed, shell_quote, ssh};
use crate::builder::{self, BuildRequest, BuildResult, BuiltProfile};
use crate::config::{DeployConfig, SshConfig};
use crate::exec::{self, Io, Output};
use crate::policy::Limits;
use crate::proto::{Destination, Operation};
use crate::server::Broker;
use crate::types::CommitId;

const MAX_TARGETS: usize = 32;

fn configs(broker: &Broker) -> Result<(&SshConfig, &DeployConfig)> {
    let ssh = broker.config.ssh.as_ref().context("SSH is not configured on this broker")?;
    let deploy = broker.config.deploy.as_ref().context("deploys are not configured on this broker")?;
    Ok((ssh, deploy))
}

fn mode(boot: bool) -> &'static str {
    if boot { "boot" } else { "switch" }
}

pub fn plan(broker: &Broker, operation: Operation) -> Result<Parsed> {
    let Operation::Deploy { targets, commit, boot } = &operation else { unreachable!() };
    let (ssh, _) = configs(broker)?;

    ensure!(!targets.is_empty(), "nothing to deploy");
    ensure!(targets.len() <= MAX_TARGETS, "at most {MAX_TARGETS} targets at once");
    for (index, target) in targets.iter().enumerate() {
        ensure!(ssh.targets.contains_key(target.node()), "unknown node {}", target.node());
        ensure!(!targets[..index].contains(target), "{target} is listed twice");
    }

    let mut sorted: Vec<&str> = targets.iter().map(|t| &**t).collect();
    sorted.sort();
    let names = sorted.join(", ");

    // Rules see one scope per target; the strictest answer applies.
    let rule_scopes = targets
        .iter()
        .map(|t| {
            let scope = json!({
                "node": t.node(),
                "profile": t.profile().unwrap_or(""),
                "mode": mode(*boot),
                "commit": &**commit,
            });
            scope.as_object().unwrap().clone()
        })
        .collect();
    let scope = json!({ "targets": names, "mode": mode(*boot), "commit": &**commit });

    Ok(Parsed {
        op: "deploy",
        scope: scope.as_object().unwrap().clone(),
        rule_scopes,
        summary: format!("deploy {names} ({}) at {}", mode(*boot), commit.short()),
        detail: format!("Commit {commit}\n(building; the changes are shown once it's built)"),
        limits: Limits::default(),
        sensitive: false,
        stdin: false,
        builtin: false,
        prepared: None,
        operation,
    })
}

/// Builds, copies and compares; fills in the approval detail.
pub async fn prepare(broker: &Broker, parsed: &mut Parsed, io: &Io) -> Result<()> {
    let Operation::Deploy { targets, commit, boot } = &parsed.operation else { return Ok(()) };
    let (ssh, deploy) = configs(broker)?;

    let request = BuildRequest { commit: commit.clone(), targets: targets.clone() };
    io.out.info(format!("building {} for {}; output follows", commit.short(), parsed.summary)).await;
    let built = builder::build(ssh, deploy, &request, &io.out, &io.cancel).await?;

    io.out.info("copying to the nodes and comparing with what they run").await;
    let by_node = group(&built.profiles);
    let reports = join_all(by_node.iter().map(|(node, profiles)| async move {
        copy(ssh, deploy, node, profiles, &io.out, &io.cancel).await?;

        let mut sections = Vec::new();
        for profile in profiles {
            let changes = inspect(ssh, node, profile, &io.cancel).await?;
            sections.push(format!("{node}.{} ({}):\n{}", profile.profile, mode(*boot), changes.describe()));
        }
        anyhow::Ok(sections.join("\n"))
    }))
    .await;

    let mut detail = describe_commit(commit, &built);
    for report in reports {
        detail += &report?;
        detail.push('\n');
    }

    parsed.detail = super::truncate(detail.trim_end(), 20_000);
    parsed.prepared = Some(built);
    Ok(())
}

pub async fn execute(broker: &Broker, parsed: &Parsed, io: &mut Io) -> Result<i32> {
    let Operation::Deploy { boot, .. } = &parsed.operation else { unreachable!() };
    let (ssh, _) = configs(broker)?;
    let built = parsed.prepared.as_ref().context("nothing was built")?;

    let run = &crate::queue::new_id();
    let (out, cancel) = (&io.out, &io.cancel);
    let results = join_all(group(&built.profiles).into_iter().map(|(node, profiles)| async move {
        for profile in profiles {
            let remote = [shell_quote(&activate_command(ssh, &node, profile, *boot, run))];
            let command = ssh::command(ssh, &Destination::Node(node.parse().unwrap()), &remote);
            let prefix = format!("[{node}.{}] ", profile.profile);

            let exit = exec::run_prefixed(command, out, &prefix, cancel).await?;
            if exit != 0 {
                return anyhow::Ok((node, format!("{} failed (exit status {exit})", profile.profile), exit));
            }
        }
        anyhow::Ok((node, "done".to_owned(), 0))
    }))
    .await;

    let mut status = 0;
    for result in results {
        let (node, outcome, exit) = result?;
        io.out.info(format!("{node}: {outcome}")).await;
        if status == 0 {
            status = exit;
        }
    }
    Ok(status)
}

/// Profiles by node, nodes in request order.
fn group(profiles: &[BuiltProfile]) -> Vec<(String, Vec<&BuiltProfile>)> {
    let mut groups: Vec<(String, Vec<&BuiltProfile>)> = Vec::new();
    for profile in profiles {
        match groups.iter_mut().find(|(node, _)| *node == profile.node) {
            Some((_, list)) => list.push(profile),
            None => groups.push((profile.node.clone(), vec![profile])),
        }
    }
    groups
}

fn describe_commit(commit: &CommitId, built: &BuildResult) -> String {
    let mut text = format!("Commit {commit}\nCommits (agent-written messages):\n");
    for line in built.log.lines().chain(built.stat.lines()) {
        text += &format!("  {line}\n");
    }
    text
}

/// Copies closures to a node like deploy-rs does, letting it substitute what caches have. Its
/// progress (one line per path) goes to the requester.
async fn copy(
    ssh: &SshConfig,
    deploy: &DeployConfig,
    node: &str,
    profiles: &[&BuiltProfile],
    out: &Output,
    cancel: &tokio_util::sync::CancellationToken,
) -> Result<()> {
    let target = &ssh.targets[node];
    let options = copy_options(ssh, node);
    ensure!(!options.iter().any(|o| o.contains(char::is_whitespace)), "SSH options can't contain spaces for nix copy");

    let ssh_directory = ssh.ssh.parent().map(|p| p.display().to_string()).unwrap_or_default();
    let mut command = Command::new(&deploy.nix);
    command
        .env_clear()
        .env("PATH", format!("{ssh_directory}:/run/current-system/sw/bin"))
        .env("HOME", &deploy.cache)
        .env("XDG_CACHE_HOME", &deploy.cache)
        .env("NIX_SSHOPTS", options.join(" "))
        .args([
            "--extra-experimental-features",
            "nix-command",
            "copy",
            "--no-check-sigs",
            "--substitute-on-destination",
        ])
        .arg("--to")
        .arg(format!("ssh://{}@{}", target.user, target.hostname))
        .args(profiles.iter().map(|p| &p.path));

    let exit = exec::run_prefixed(command, out, &format!("[{node}] "), cancel).await?;
    ensure!(exit == 0, "copying to {node} failed; its output is above");
    Ok(())
}

/// `NIX_SSHOPTS` for `nix copy`. It adds `-oPermitLocalCommand=yes -oLocalCommand=echo started`
/// and waits for that line, but ssh keeps the first value of an option, so the broker's
/// `PermitLocalCommand=no` would leave it waiting forever. With `-F none`, nothing else can set a
/// local command anyway.
fn copy_options(ssh: &SshConfig, node: &str) -> Vec<String> {
    let mut options = ssh::options(ssh);
    if let Some(index) = options.windows(2).position(|w| w == ["-o", "PermitLocalCommand=no"]) {
        options.drain(index..index + 2);
    }
    options.extend(ssh.targets[node].ssh_opts.iter().cloned());
    options
}

/// Compares a profile's current and new closures on the node; reads only.
const INSPECT: &str = r#"old=$1 new=$2
if [ -e "$old" ]; then
  echo @@packages
  nix --extra-experimental-features nix-command store diff-closures "$old" "$new" 2>&1 | head -n 500
  echo @@boot
  for f in kernel initrd; do
    [ -e "$old/$f" ] && [ -e "$new/$f" ] && [ "$(readlink -f "$old/$f")" != "$(readlink -f "$new/$f")" ] && echo "$f"
  done
fi
# /etc entries are links into the store, so a link's target changes with its contents. Units are
# one link to a directory of them, so that one is followed.
list() {
  [ -d "$1/etc" ] && cd "$1/etc" || return 0
  find . -path ./systemd/system -prune -o -type l -printf "%p\t%l\n" -o -type f -printf "%p\t%s\n"
  [ -d systemd/system ] || return 0
  units=$(find -L systemd/system/ -mindepth 1 -maxdepth 2 -type f | LC_ALL=C sort)
  [ -n "$units" ] || return 0
  paste <(printf "%s\n" "$units" | sed "s|^|./|") <(printf "%s\n" "$units" | xargs -d "\n" realpath --)
}
echo @@old
[ -e "$old" ] && (list "$old")
echo @@new
(list "$new")
"#;

async fn inspect(
    ssh: &SshConfig,
    node: &str,
    profile: &BuiltProfile,
    cancel: &tokio_util::sync::CancellationToken,
) -> Result<Changes> {
    let words = ["bash", "-c", INSPECT, "bash", &profile.profile_path, &profile.path];
    let command = ssh::command(ssh, &Destination::Node(node.parse().unwrap()), &[shell_quote(&words)]);

    let (exit, stdout, stderr) = exec::capture(command, cancel).await?;
    if exit != 0 {
        bail!("comparing on {node} failed: {}", String::from_utf8_lossy(&stderr).trim());
    }
    Ok(Changes::parse(&String::from_utf8_lossy(&stdout)))
}

fn activate_command(ssh: &SshConfig, node: &str, profile: &BuiltProfile, boot: bool, run: &str) -> Vec<String> {
    let mut words: Vec<String> = ssh.targets[node].sudo.split_whitespace().map(Into::into).collect();
    words.push("root".into());

    // A transient unit, so activation finishes even if this connection drops
    words.extend(
        [
            "/run/current-system/sw/bin/systemd-run",
            "--quiet",
            "--wait",
            "--pipe",
            "--collect",
            "--service-type=exec",
            "--setenv=PATH=/run/current-system/sw/bin",
        ]
        .map(Into::into),
    );
    words.push(format!("--unit=slop-deploy-{}-{}", &run[..8], profile.profile));

    // What deploy-rs runs, without magic rollback
    words.push(format!("{}/activate-rs", profile.path));
    words.extend(["activate".into(), profile.path.clone(), "--profile-path".into(), profile.profile_path.clone()]);
    words.extend(["--temp-path", "/tmp", "--confirm-timeout", "30"].map(Into::into));
    if boot {
        words.push("--boot".into());
    }
    words
}

/// Drops terminal escape sequences, which `nix` can print even into a pipe.
fn strip_escapes(text: &str) -> String {
    let mut result = String::with_capacity(text.len());
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            if chars.next() == Some('[') {
                for c in chars.by_ref() {
                    if c.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
        } else {
            result.push(c);
        }
    }
    result
}

/// What a deploy changes on one profile.
#[derive(Debug, Default, PartialEq)]
struct Changes {
    /// No current profile: everything is new.
    new: bool,
    packages: Vec<String>,
    /// `kernel` or `initrd`, if they changed.
    boot: Vec<String>,
    units: Diff,
    files: Diff,
}

#[derive(Debug, Default, PartialEq)]
struct Diff {
    changed: Vec<String>,
    added: Vec<String>,
    removed: Vec<String>,
}

impl Changes {
    fn parse(output: &str) -> Changes {
        let output = strip_escapes(output);
        let mut changes = Changes { new: !output.contains("@@packages"), ..Changes::default() };

        // Sections start with `@@name` lines; the /etc listings are `path<TAB>target`.
        let (mut old, mut new) = (BTreeMap::new(), BTreeMap::new());
        let mut section = "";
        for line in output.lines() {
            if let Some(name) = line.strip_prefix("@@") {
                section = match name {
                    "packages" => "packages",
                    "boot" => "boot",
                    "old" => "old",
                    "new" => "new",
                    _ => "",
                };
                continue;
            }
            match section {
                "packages" if !line.trim().is_empty() => changes.packages.push(line.trim().to_owned()),
                "boot" if !line.is_empty() => changes.boot.push(line.to_owned()),
                "old" | "new" => {
                    if let Some((name, target)) = line.split_once('\t') {
                        let map = if section == "old" { &mut old } else { &mut new };
                        map.insert(format!("/{}", name.trim_start_matches("./")), target.to_owned());
                    }
                }
                _ => {}
            }
        }

        for (name, target) in &new {
            match old.get(name) {
                Some(previous) if previous == target => {}
                Some(_) => changes.record(name, |d| &mut d.changed),
                None => changes.record(name, |d| &mut d.added),
            }
        }
        for name in old.keys().filter(|n| !new.contains_key(*n)) {
            changes.record(name, |d| &mut d.removed);
        }
        changes
    }

    /// Files under `systemd/system` count as their unit; links in `.wants` and the like only
    /// repeat the unit they point to.
    fn record(&mut self, name: &str, list: fn(&mut Diff) -> &mut Vec<String>) {
        match name.strip_prefix("/systemd/system/") {
            Some(rest) => {
                let first = rest.split('/').next().unwrap_or(rest);
                if rest.contains('/') && [".wants", ".requires", ".upholds"].iter().any(|s| first.ends_with(s)) {
                    return;
                }

                let unit = first.strip_suffix(".d").unwrap_or(first);
                let units = list(&mut self.units);
                if !units.iter().any(|u| u == unit) {
                    units.push(unit.to_owned());
                }
            }
            None => list(&mut self.files).push(format!("/etc{name}")),
        }
    }

    fn describe(&self) -> String {
        fn listing(label: &str, items: &[String], limit: usize) -> String {
            if items.is_empty() {
                return String::new();
            }

            let mut shown = items.iter().take(limit).cloned().collect::<Vec<_>>().join(", ");
            if items.len() > limit {
                shown += &format!(", … {} more", items.len() - limit);
            }
            format!("  {label}: {shown}\n")
        }

        let mut text = String::new();
        if self.new {
            text += "  new profile: nothing to compare with\n";
        } else if self.packages.is_empty() {
            text += "  packages: no version changes\n";
        } else {
            text += "  packages:\n";
            for line in self.packages.iter().take(40) {
                text += &format!("    {line}\n");
            }
            if self.packages.len() > 40 {
                text += &format!("    … {} more\n", self.packages.len() - 40);
            }
        }
        if !self.boot.is_empty() {
            text += &format!("  {} changed: takes effect after a reboot\n", self.boot.join(" and "));
        }

        text += &listing("changed units", &self.units.changed, 40);
        text += &listing("added units", &self.units.added, 40);
        text += &listing("removed units", &self.units.removed, 40);
        text += &listing("changed files", &self.files.changed, 30);
        text += &listing("added files", &self.files.added, 30);
        text += &listing("removed files", &self.files.removed, 30);
        if !self.new && self.units == Diff::default() && self.files == Diff::default() {
            text += "  no unit or /etc changes\n";
        }
        text
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compares_etc_trees() {
        let output = "@@packages\nhome-assistant: 2026.11.1 → 2026.11.2, +3.4 MiB\n@@boot\nkernel\n@@old\n\
                      ./systemd/system/a.service\t/nix/store/x-a\n\
                      ./systemd/system/b.service\t/nix/store/x-b\n\
                      ./systemd/system/multi-user.target.wants/a.service\t/nix/store/x-a\n\
                      ./hosts\t/nix/store/x-hosts\n\
                      ./gone\t/nix/store/x-gone\n\
                      @@new\n\
                      ./systemd/system/a.service\t/nix/store/y-a\n\
                      ./systemd/system/multi-user.target.wants/a.service\t/nix/store/y-a\n\
                      ./systemd/system/c.service.d/overrides.conf\t/nix/store/y-c\n\
                      ./hosts\t/nix/store/x-hosts\n\
                      ./new.conf\t/nix/store/y-new\n";

        let changes = Changes::parse(output);
        assert_eq!(changes.packages, ["home-assistant: 2026.11.1 → 2026.11.2, +3.4 MiB"]);
        assert_eq!(strip_escapes("source: \x1b[31;1m3.6 GiB\x1b[0m"), "source: 3.6 GiB");
        assert_eq!(changes.boot, ["kernel"]);
        assert_eq!(changes.units.changed, ["a.service"]);
        assert_eq!(changes.units.added, ["c.service"]);
        assert_eq!(changes.units.removed, ["b.service"]);
        assert_eq!(changes.files.added, ["/etc/new.conf"]);
        assert_eq!(changes.files.removed, ["/etc/gone"]);
        assert!(changes.files.changed.is_empty());

        let text = changes.describe();
        assert!(text.contains("changed units: a.service\n") && text.contains("kernel changed"), "{text}");

        let fresh = Changes::parse("@@old\n@@new\n./hosts\t/nix/store/x\n");
        assert!(fresh.new && fresh.describe().contains("new profile"));
    }

    #[test]
    fn copies_can_run_their_local_command() {
        let options = copy_options(&ssh::tests::config(), "river");
        assert!(!options.iter().any(|o| o.starts_with("PermitLocalCommand")), "{options:?}");
        assert!(options.contains(&"IdentitiesOnly=yes".to_owned()));
        assert_eq!(&options[options.len() - 2..], ["-p", "2222"]);
    }

    #[test]
    fn activation_runs_in_a_transient_unit() {
        let mut config = ssh::tests::config();
        config.targets.get_mut("river").unwrap().sudo = "doas -u".into();
        let profile = BuiltProfile {
            node: "river".into(),
            profile: "system".into(),
            path: "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-system".into(),
            profile_path: "/nix/var/nix/profiles/system".into(),
        };
        let words = activate_command(&config, "river", &profile, true, "0123456789abcdef");
        assert_eq!(&words[..3], ["doas", "-u", "root"]);
        assert!(words.contains(&"--unit=slop-deploy-01234567-system".to_owned()));
        assert_eq!(words.last().unwrap(), "--boot");
    }
}
