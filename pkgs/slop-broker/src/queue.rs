//! Pending approvals, leases and rate limits. Everything is in memory: a restart drops pending
//! requests and leases.
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow, bail};
use serde::{Deserialize, Serialize};
use tokio::sync::{oneshot, watch};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Decision {
    Once,
    Lease(u64),
    Deny,
}

impl Decision {
    pub fn parse(text: &str) -> Result<Decision> {
        match text {
            "once" => Ok(Decision::Once),
            "deny" => Ok(Decision::Deny),
            _ => parse_duration(text)
                .map(Decision::Lease)
                .ok_or_else(|| anyhow!("decision must be once, deny or a duration like 5m")),
        }
    }

    pub fn name(&self) -> String {
        match self {
            Decision::Once => "once".into(),
            Decision::Deny => "deny".into(),
            Decision::Lease(seconds) => format_duration(*seconds),
        }
    }

    pub fn title(&self) -> String {
        match self {
            Decision::Once => "Once".into(),
            Decision::Deny => "Deny".into(),
            Decision::Lease(seconds) => format_duration(*seconds),
        }
    }
}

/// A new request ID.
pub fn new_id() -> String {
    hex::encode(rand::random::<[u8; 8]>())
}

pub fn parse_duration(text: &str) -> Option<u64> {
    let split = text.find(|c: char| !c.is_ascii_digit())?;
    let (number, unit) = text.split_at(split);
    let number: u64 = number.parse().ok()?;
    let scale = match unit {
        "s" => 1,
        "m" | "min" => 60,
        "h" => 3600,
        "d" => 86400,
        _ => return None,
    };
    number.checked_mul(scale).filter(|&s| s > 0)
}

pub fn format_duration(seconds: u64) -> String {
    match seconds {
        s if s % 86400 == 0 => format!("{}d", s / 86400),
        s if s % 3600 == 0 => format!("{}h", s / 3600),
        s if s % 60 == 0 => format!("{}m", s / 60),
        s => format!("{s}s"),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Approved {
        decision: Decision,
        /// Who answered, as the audit log names them.
        approver: String,
    },
    Denied,
    Expired,
}

/// What approvers see of a pending request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingInfo {
    pub id: String,
    pub requester: String,
    pub op: String,
    pub summary: String,
    pub detail: String,
    /// Agent-supplied; never trusted.
    pub label: Option<String>,
    /// Marks requests that reveal a secret or change who can read one.
    pub sensitive: bool,
    pub offers: Vec<Decision>,
    pub expires_in: u64,
}

pub struct NewRequest {
    pub requester: String,
    pub op: String,
    pub lease_key: String,
    pub summary: String,
    pub detail: String,
    pub label: Option<String>,
    pub sensitive: bool,
    pub leases: Vec<u64>,
}

struct Entry {
    request: NewRequest,
    deadline: Instant,
    reply: Option<oneshot::Sender<Outcome>>,
}

#[derive(Default)]
struct State {
    sequence: u64,
    pending: BTreeMap<String, Entry>,
    leases: HashMap<(String, String), Instant>,
    auto: HashMap<String, VecDeque<Instant>>,
}

pub struct Queue {
    state: Mutex<State>,
    timeout: Duration,
    max_pending: usize,
    changed: watch::Sender<u64>,
}

impl Queue {
    pub fn new(timeout: Duration, max_pending: usize) -> Queue {
        Queue { state: Mutex::default(), timeout, max_pending, changed: watch::channel(0).0 }
    }

    pub fn timeout(&self) -> Duration {
        self.timeout
    }

    /// Fires whenever the pending set changes.
    pub fn subscribe(&self) -> watch::Receiver<u64> {
        self.changed.subscribe()
    }

    fn bump(&self, state: &mut State) {
        state.sequence += 1;
        self.changed.send_replace(state.sequence);
    }

    pub fn leased(&self, requester: &str, key: &str) -> bool {
        let mut state = self.state.lock().unwrap();
        let now = Instant::now();
        state.leases.retain(|_, until| *until > now);
        state.leases.contains_key(&(requester.to_owned(), key.to_owned()))
    }

    /// Counts a request that policy approves by itself.
    pub fn take_auto(&self, requester: &str, per_minute: usize) -> Result<()> {
        let mut state = self.state.lock().unwrap();
        let now = Instant::now();

        let window = state.auto.entry(requester.to_owned()).or_default();
        while window.front().is_some_and(|t| now.duration_since(*t) >= Duration::from_secs(60)) {
            window.pop_front();
        }

        if window.len() >= per_minute {
            bail!("rate limit reached; try again in a minute");
        }

        window.push_back(now);
        Ok(())
    }

    pub fn submit(
        &self,
        id: &str,
        request: NewRequest,
        max_for_requester: usize,
    ) -> Result<oneshot::Receiver<Outcome>> {
        let mut state = self.state.lock().unwrap();

        if state.pending.len() >= self.max_pending {
            bail!("approval queue is full");
        }
        if state.pending.values().filter(|e| e.request.requester == request.requester).count() >= max_for_requester {
            bail!("too many pending requests");
        }

        let (reply, receiver) = oneshot::channel();
        state
            .pending
            .insert(id.to_owned(), Entry { request, deadline: Instant::now() + self.timeout, reply: Some(reply) });

        self.bump(&mut state);
        Ok(receiver)
    }

    /// Drops a request whose client went away or timed out.
    pub fn cancel(&self, id: &str) {
        let mut state = self.state.lock().unwrap();
        if state.pending.remove(id).is_some() {
            self.bump(&mut state);
        }
    }

    pub fn decide(&self, id: &str, decision: Decision, approver: &str) -> Result<PendingInfo> {
        let mut state = self.state.lock().unwrap();
        let entry = state.pending.get(id).ok_or_else(|| anyhow!("unknown or expired request"))?;

        if let Decision::Lease(seconds) = decision
            && !entry.request.leases.contains(&seconds)
        {
            bail!("lease not offered for this request");
        }

        let info = info(id, entry, Instant::now());
        let mut entry = state.pending.remove(id).unwrap();
        if Instant::now() >= entry.deadline {
            self.bump(&mut state);
            bail!("request expired");
        }

        if let Decision::Lease(seconds) = decision {
            let key = (entry.request.requester.clone(), entry.request.lease_key.clone());
            state.leases.insert(key, Instant::now() + Duration::from_secs(seconds));
        }

        let outcome = match decision {
            Decision::Deny => Outcome::Denied,
            decision => Outcome::Approved { decision, approver: approver.to_owned() },
        };
        if let Some(reply) = entry.reply.take() {
            let _ = reply.send(outcome);
        }

        self.bump(&mut state);
        Ok(info)
    }

    pub fn list(&self) -> Vec<PendingInfo> {
        let state = self.state.lock().unwrap();
        let now = Instant::now();
        state.pending.iter().filter(|(_, e)| e.deadline > now).map(|(id, e)| info(id, e, now)).collect()
    }

    /// Active leases for one requester, as (scope key, seconds left).
    pub fn leases(&self, requester: &str) -> Vec<(String, u64)> {
        let state = self.state.lock().unwrap();
        let now = Instant::now();

        let mut leases: Vec<_> = state
            .leases
            .iter()
            .filter(|((r, _), until)| r == requester && **until > now)
            .map(|((_, key), until)| (key.clone(), until.duration_since(now).as_secs()))
            .collect();

        leases.sort();
        leases
    }
}

fn info(id: &str, entry: &Entry, now: Instant) -> PendingInfo {
    let r = &entry.request;

    let mut offers = vec![Decision::Once];
    offers.extend(r.leases.iter().map(|&s| Decision::Lease(s)));
    offers.push(Decision::Deny);

    PendingInfo {
        id: id.to_owned(),
        requester: r.requester.clone(),
        op: r.op.clone(),
        summary: r.summary.clone(),
        detail: r.detail.clone(),
        label: r.label.clone(),
        sensitive: r.sensitive,
        offers,
        expires_in: entry.deadline.saturating_duration_since(now).as_secs(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(requester: &str, key: &str) -> NewRequest {
        NewRequest {
            requester: requester.into(),
            op: "ssh".into(),
            lease_key: key.into(),
            summary: "ssh river".into(),
            detail: String::new(),
            label: None,
            sensitive: false,
            leases: vec![300],
        }
    }

    fn submit(queue: &Queue, requester: &str, max: usize) -> Result<(String, oneshot::Receiver<Outcome>)> {
        let id = new_id();
        queue.submit(&id, request(requester, "k"), max).map(|reply| (id, reply))
    }

    #[test]
    fn decisions_parse() {
        assert_eq!(Decision::parse("once").unwrap(), Decision::Once);
        assert_eq!(Decision::parse("5m").unwrap(), Decision::Lease(300));
        assert_eq!(Decision::parse("1h").unwrap(), Decision::Lease(3600));
        assert!(Decision::parse("0m").is_err());
        assert!(Decision::parse("5").is_err());
        assert!(Decision::parse("5x").is_err());
        assert_eq!(Decision::Lease(300).name(), "5m");
    }

    #[tokio::test]
    async fn lease_covers_the_same_scope_only() {
        let queue = Queue::new(Duration::from_secs(60), 64);
        let (id, reply) = submit(&queue, "a", 4).unwrap();
        queue.decide(&id, Decision::Lease(300), "dev").unwrap();
        assert_eq!(reply.await.unwrap(), Outcome::Approved { decision: Decision::Lease(300), approver: "dev".into() });
        assert!(queue.leased("a", "k"));
        assert!(!queue.leased("a", "other"));
        assert!(!queue.leased("b", "k"));
    }

    #[tokio::test]
    async fn once_and_deny_leave_no_lease() {
        let queue = Queue::new(Duration::from_secs(60), 64);
        let (id, reply) = submit(&queue, "a", 4).unwrap();
        queue.decide(&id, Decision::Once, "dev").unwrap();
        assert_eq!(reply.await.unwrap(), Outcome::Approved { decision: Decision::Once, approver: "dev".into() });
        let (id, reply) = submit(&queue, "a", 4).unwrap();
        queue.decide(&id, Decision::Deny, "dev").unwrap();
        assert_eq!(reply.await.unwrap(), Outcome::Denied);
        assert!(!queue.leased("a", "k"));
        assert!(queue.decide(&id, Decision::Once, "dev").is_err());
    }

    #[test]
    fn unoffered_leases_are_refused() {
        let queue = Queue::new(Duration::from_secs(60), 64);
        let (id, _reply) = submit(&queue, "a", 4).unwrap();
        assert!(queue.decide(&id, Decision::Lease(3600), "dev").is_err());
        assert_eq!(queue.list().len(), 1);
    }

    #[test]
    fn limits_pending_requests() {
        let queue = Queue::new(Duration::from_secs(60), 3);
        let _held: Vec<_> = (0..2).map(|_| submit(&queue, "a", 2).unwrap()).collect();
        assert!(submit(&queue, "a", 2).is_err());
        let _b = submit(&queue, "b", 2).unwrap();
        assert!(submit(&queue, "c", 2).is_err());
    }

    #[test]
    fn rate_limits_auto_requests() {
        let queue = Queue::new(Duration::from_secs(60), 64);
        assert!(queue.take_auto("a", 2).is_ok());
        assert!(queue.take_auto("a", 2).is_ok());
        assert!(queue.take_auto("a", 2).is_err());
        assert!(queue.take_auto("b", 2).is_ok());
    }

    #[test]
    fn cancel_removes_and_notifies() {
        let queue = Queue::new(Duration::from_secs(60), 64);
        let mut changes = queue.subscribe();
        let (id, _reply) = submit(&queue, "a", 4).unwrap();
        assert!(changes.has_changed().unwrap());
        changes.mark_unchanged();
        queue.cancel(&id);
        assert!(changes.has_changed().unwrap());
        assert!(queue.list().is_empty());
    }
}
