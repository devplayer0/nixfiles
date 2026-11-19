//! Per-requester, per-operation policy: `auto`, `ask` or `deny`, with the lease lengths an
//! approver may grant. Rules match fields of a request's scope with simple globs.
use std::collections::BTreeMap;

use serde::Deserialize;
use serde_json::{Map, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Action {
    Auto,
    Ask,
    Deny,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OpPolicy {
    pub action: Action,
    /// Lease lengths in seconds that approvers are offered.
    #[serde(default, deserialize_with = "crate::config::durations")]
    pub leases: Vec<u64>,
    /// First matching rule wins; otherwise `action` and `leases` apply.
    #[serde(default)]
    pub rules: Vec<Rule>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rule {
    #[serde(rename = "match")]
    pub matches: BTreeMap<String, String>,
    pub action: Action,
    #[serde(default, deserialize_with = "crate::config::optional_durations")]
    pub leases: Option<Vec<u64>>,
}

/// What policy decided for one request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Verdict {
    pub action: Action,
    pub leases: Vec<u64>,
}

/// Limits an operation puts on its own requests, whatever the policy says.
#[derive(Debug, Clone, Copy, Default)]
pub struct Limits {
    /// Never approved by policy alone.
    pub never_auto: bool,
    /// Never covered by a lease.
    pub never_lease: bool,
}

pub fn evaluate(policy: Option<&OpPolicy>, scope: &Map<String, Value>, limits: Limits) -> Verdict {
    let Some(policy) = policy else {
        return Verdict { action: Action::Deny, leases: vec![] };
    };

    let (mut action, mut leases) = (policy.action, policy.leases.clone());
    if let Some(rule) = policy.rules.iter().find(|r| matches(&r.matches, scope)) {
        action = rule.action;
        if let Some(rule_leases) = &rule.leases {
            leases = rule_leases.clone();
        }
    }

    if limits.never_auto && action == Action::Auto {
        action = Action::Ask;
    }
    if limits.never_lease {
        leases.clear();
    }
    Verdict { action, leases }
}

fn matches(patterns: &BTreeMap<String, String>, scope: &Map<String, Value>) -> bool {
    patterns.iter().all(|(field, pattern)| {
        let value = match scope.get(field) {
            Some(Value::String(s)) => s.clone(),
            Some(Value::Null) | None => return false,
            Some(other) => other.to_string(),
        };
        glob(pattern.as_bytes(), value.as_bytes())
    })
}

/// `*` matches any run of characters, `?` one character; everything else is literal.
pub fn glob(pattern: &[u8], text: &[u8]) -> bool {
    let (mut p, mut t) = (0, 0);
    let mut backtrack = None;
    while t < text.len() {
        match pattern.get(p) {
            Some(b'*') => {
                backtrack = Some((p, t));
                p += 1;
            }
            Some(&c) if c == b'?' || c == text[t] => {
                p += 1;
                t += 1;
            }
            _ => match backtrack {
                Some((bp, bt)) => {
                    p = bp + 1;
                    t = bt + 1;
                    backtrack = Some((bp, bt + 1));
                }
                None => return false,
            },
        }
    }
    pattern[p..].iter().all(|&c| c == b'*')
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn scope(value: Value) -> Map<String, Value> {
        value.as_object().unwrap().clone()
    }

    #[test]
    fn globs() {
        assert!(glob(b"*", b""));
        assert!(glob(b"river", b"river"));
        assert!(!glob(b"river", b"rivers"));
        assert!(glob(b"r*r", b"river"));
        assert!(glob(b"*.nul.ie", b"a.b.nul.ie"));
        assert!(!glob(b"*.nul.ie", b"nul.ie"));
        assert!(glob(b"?iver", b"river"));
        assert!(glob(b"a*b*c", b"aXbYbZc"));
    }

    #[test]
    fn missing_policy_denies() {
        let verdict = evaluate(None, &Map::new(), Limits::default());
        assert_eq!(verdict.action, Action::Deny);
    }

    #[test]
    fn first_matching_rule_wins() {
        let policy: OpPolicy = serde_json::from_value(json!({
            "action": "ask",
            "leases": [300, 3600],
            "rules": [
                {"match": {"target": "river"}, "action": "deny"},
                {"match": {"target": "r*"}, "action": "auto", "leases": []},
            ],
        }))
        .unwrap();

        let verdict = |s| evaluate(Some(&policy), &scope(s), Limits::default());
        assert_eq!(verdict(json!({"target": "river"})).action, Action::Deny);
        assert_eq!(verdict(json!({"target": "rain"})), Verdict { action: Action::Auto, leases: vec![] });
        assert_eq!(verdict(json!({"target": "sfh"})), Verdict { action: Action::Ask, leases: vec![300, 3600] });
        assert_eq!(verdict(json!({"host": "river"})).action, Action::Ask);
        assert_eq!(verdict(json!({"target": 5})).action, Action::Ask);
    }

    #[test]
    fn limits_override_policy() {
        let policy: OpPolicy = serde_json::from_value(json!({"action": "auto", "leases": [300]})).unwrap();
        let limits = Limits { never_auto: true, never_lease: true };
        let verdict = evaluate(Some(&policy), &Map::new(), limits);
        assert_eq!(verdict, Verdict { action: Action::Ask, leases: vec![] });
    }
}
