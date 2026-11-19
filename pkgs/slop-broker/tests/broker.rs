//! End-to-end tests of the request handler with a fake `ssh`.
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use tokio::io::DuplexStream;

use slop_broker::config::Config;
use slop_broker::proto::{ApproveRequest, ApproveResponse, receive, send};
use slop_broker::proto::{
    ApprovedBy, ClientMessage, Destination, OpResult, Operation, PROTOCOL_VERSION, Query, Request, ServerMessage,
    Transport, decode, encode, transport,
};
use slop_broker::queue::Decision;
use slop_broker::remote::{Hello, Role, write_hello};
use slop_broker::server::{Broker, handle};
use slop_broker::types::{Arg, Lines};

const FAKE_SSH: &str = r#"#!/bin/sh
echo $$ > "${0%/*}/pid"
echo "args: $*"
while read -r line; do
  [ "$line" = block ] && while read -r _; do :; done
  echo "in: $line"
done
echo done >&2
exit 3
"#;

fn broker(directory: &Path, ops: serde_json::Value) -> Arc<Broker> {
    let ssh = directory.join("ssh");
    std::fs::write(&ssh, FAKE_SSH).unwrap();
    std::fs::set_permissions(&ssh, std::fs::Permissions::from_mode(0o755)).unwrap();

    let config: Config = serde_json::from_value(json!({
        "requesters": { "agent": { "remote": true, "policy": "agent" } },
        "policies": { "agent": { "ops": ops } },
        "timeout": 2,
        "approve_socket": "/unused",
        "approver_group": "root",
        "audit_log": directory.join("audit.jsonl"),
        "remote": { "socket": "/unused", "user": "root", "approvers": ["laptop"] },
        "ssh": {
            "ssh": ssh,
            "key": "/key",
            "known_hosts": "/kh",
            "targets": { "river": { "hostname": "river.h.nul.ie", "user": "deploy", "ssh_opts": [] } },
        },
    }))
    .unwrap();

    Arc::new(Broker::new(config).unwrap())
}

struct Client {
    transport: Transport<DuplexStream>,
}

impl Client {
    async fn start(broker: &Arc<Broker>, operation: Operation) -> Client {
        Client::start_with(broker, Request { version: PROTOCOL_VERSION, label: Some("test".into()), operation }).await
    }

    async fn start_with(broker: &Arc<Broker>, request: Request) -> Client {
        let (client, server) = tokio::io::duplex(1 << 16);
        tokio::spawn(handle(broker.clone(), server, "agent".into()));
        let mut client = Client { transport: transport(client) };
        client.send(ClientMessage::Request(request)).await;
        client
    }

    async fn send(&mut self, message: ClientMessage) {
        self.transport.send(encode(&message).unwrap()).await.unwrap();
    }

    /// Reads until the next message other than output, collecting output.
    async fn next(&mut self, output: &mut String) -> ServerMessage {
        loop {
            let frame =
                tokio::time::timeout(Duration::from_secs(10), self.transport.next()).await.unwrap().unwrap().unwrap();
            match decode::<ServerMessage>(&frame).unwrap() {
                ServerMessage::Stdout(data) | ServerMessage::Stderr(data) => {
                    output.push_str(&String::from_utf8_lossy(&data))
                }
                message => return message,
            }
        }
    }
}

fn ssh(command: &[&str]) -> Operation {
    Operation::Ssh {
        destination: Destination::Node("river".parse().unwrap()),
        command: command.iter().map(|c| c.parse::<Arg>().unwrap()).collect(),
    }
}

fn finished(exit: i32) -> ServerMessage {
    ServerMessage::Finished { exit, result: None }
}

#[tokio::test]
async fn auto_runs_with_stdio_and_exit_status() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "auto" } }));

    let mut client = Client::start(&broker, ssh(&["uptime", "-p"])).await;
    let mut output = String::new();
    assert_eq!(client.next(&mut output).await, ServerMessage::Approved { by: ApprovedBy::Policy, stdin: true });

    client.send(ClientMessage::Stdin(b"hello\n".to_vec())).await;
    client.send(ClientMessage::StdinEnd).await;

    assert_eq!(client.next(&mut output).await, finished(3));
    assert!(output.contains("-l deploy -- river.h.nul.ie uptime -p"), "{output}");
    assert!(output.contains("-o IdentityAgent=none"), "{output}");
    assert!(output.contains("in: hello"), "{output}");
    assert!(output.contains("done"), "{output}");
}

#[tokio::test]
async fn policy_can_deny_and_unlisted_operations_are_denied() {
    let directory = tempfile::tempdir().unwrap();
    let ops = json!({ "ssh": { "action": "auto", "rules": [{ "match": { "target": "river" }, "action": "deny" }] } });
    let broker = broker(directory.path(), ops);

    let mut client = Client::start(&broker, ssh(&["true"])).await;
    assert!(matches!(client.next(&mut String::new()).await, ServerMessage::Denied(_)));

    let query = Operation::Query { destination: Destination::Node("river".parse().unwrap()), query: Query::Failed };
    let mut client = Client::start(&broker, query).await;
    assert!(matches!(client.next(&mut String::new()).await, ServerMessage::Denied(_)));
}

#[tokio::test]
async fn unknown_nodes_and_versions_are_rejected() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "auto" } }));

    let operation = Operation::Ssh { destination: Destination::Node("sfh".parse().unwrap()), command: vec![] };
    let mut client = Client::start(&broker, operation).await;
    assert!(matches!(client.next(&mut String::new()).await, ServerMessage::Error(e) if e.contains("unknown node")));

    let request = Request { version: PROTOCOL_VERSION + 1, label: None, operation: ssh(&["true"]) };
    let mut client = Client::start_with(&broker, request).await;
    assert!(matches!(client.next(&mut String::new()).await, ServerMessage::Error(e) if e.contains("protocol version")));
}

#[tokio::test]
async fn invalid_messages_are_rejected() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "auto" } }));

    let raw = |node: &str, extra: bool| {
        let mut ssh = json!({ "destination": { "node": node }, "command": [] });
        if extra {
            ssh["unexpected"] = json!(true);
        }
        json!({ "request": { "version": PROTOCOL_VERSION, "label": null, "operation": { "ssh": ssh } } })
    };

    for (message, valid) in
        [(raw("river", false), true), (raw("-oProxyCommand=x", false), false), (raw("river", true), false)]
    {
        let (client, server) = tokio::io::duplex(1 << 16);
        tokio::spawn(handle(broker.clone(), server, "agent".into()));
        let mut client = Client { transport: transport(client) };
        client.transport.send(encode(&message).unwrap()).await.unwrap();
        let reply = client.next(&mut String::new()).await;
        assert_eq!(matches!(reply, ServerMessage::Approved { .. }), valid, "{message} → {reply:?}");
    }
}

async fn pending_id(client: &mut Client) -> String {
    match client.next(&mut String::new()).await {
        ServerMessage::Pending { id, summary } => {
            assert_eq!(summary, "ssh river");
            id
        }
        other => panic!("expected pending, got {other:?}"),
    }
}

#[tokio::test]
async fn ask_waits_for_an_approver_and_leases_cover_repeats() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "ask", "leases": [300] } }));

    let mut client = Client::start(&broker, ssh(&["true"])).await;
    let id = pending_id(&mut client).await;

    let listed = broker.queue.list();
    assert_eq!(listed[0].label.as_deref(), Some("test"));
    assert_eq!(listed[0].offers, [Decision::Once, Decision::Lease(300), Decision::Deny]);

    slop_broker::approve::approve(&broker, &id, Decision::Lease(300), "test").unwrap();
    let mut output = String::new();
    assert_eq!(client.next(&mut output).await, ServerMessage::Approved { by: ApprovedBy::Approver, stdin: true });

    client.send(ClientMessage::StdinEnd).await;
    assert_eq!(client.next(&mut output).await, finished(3));

    // Same scope, different command: covered by the lease.
    let mut client = Client::start(&broker, ssh(&["reboot"])).await;
    assert_eq!(client.next(&mut output).await, ServerMessage::Approved { by: ApprovedBy::Lease, stdin: true });

    // Every step is in the audit log under the request's ID.
    let records = broker.audit.tail(10).unwrap();
    let events: Vec<String> = records.iter().map(|r| r.event.to_string()).collect();
    let short = &id[..6];

    assert_eq!(events[0], format!("{short} agent asks: ssh river; Command: true (label: test)"));
    assert_eq!(events[1], format!("{short} answered 5m by test"));
    assert_eq!(events[2], format!("{short} approved by test"));
    assert!(events[3].starts_with(&format!("{short} finished with exit status 3 after ")), "{events:?}");
    assert!(events[4].ends_with("agent asks: ssh river; Command: reboot (label: test)"), "{events:?}");
    assert!(events[5].ends_with("approved by a lease"), "{events:?}");
}

#[tokio::test]
async fn denial_and_expiry() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "ask" } }));
    let mut client = Client::start(&broker, ssh(&["true"])).await;
    let id = pending_id(&mut client).await;
    assert!(slop_broker::approve::approve(&broker, &id, Decision::Lease(300), "test").is_err(), "lease not offered");
    slop_broker::approve::approve(&broker, &id, Decision::Deny, "test").unwrap();
    assert!(matches!(client.next(&mut String::new()).await, ServerMessage::Denied(_)));

    let mut client = Client::start(&broker, ssh(&["true"])).await;
    pending_id(&mut client).await;
    assert_eq!(client.next(&mut String::new()).await, ServerMessage::Expired);
    assert!(broker.queue.list().is_empty());
}

#[tokio::test]
async fn disconnecting_drops_the_request() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "ask" } }));
    let mut client = Client::start(&broker, ssh(&["true"])).await;
    pending_id(&mut client).await;
    drop(client);
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(broker.queue.list().is_empty());
}

#[tokio::test]
async fn disconnecting_kills_the_process() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "auto" } }));

    let mut client = Client::start(&broker, ssh(&["true"])).await;
    client.next(&mut String::new()).await;
    client.send(ClientMessage::Stdin(b"block\n".to_vec())).await;

    let pid_file = directory.path().join("pid");
    let mut pid = None;
    for _ in 0..50 {
        tokio::time::sleep(Duration::from_millis(50)).await;
        pid = std::fs::read_to_string(&pid_file).ok().and_then(|p| p.trim().parse::<i32>().ok());
        if pid.is_some() {
            break;
        }
    }
    let pid = pid.expect("fake ssh started");

    drop(client);
    tokio::time::sleep(Duration::from_millis(500)).await;
    let alive = unsafe { libc::kill(pid, 0) } == 0;
    assert!(!alive, "process {pid} survived its requester");
}

#[tokio::test]
async fn queries_run_a_fixed_quoted_command_without_stdin() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "query": { "action": "auto" } }));

    let query = Query::Logs {
        unit: "nginx.service".parse().unwrap(),
        lines: Lines::try_from(50).unwrap(),
        since: Some("2h".parse().unwrap()),
    };
    let operation = Operation::Query { destination: Destination::Node("river".parse().unwrap()), query };

    let mut client = Client::start(&broker, operation).await;
    let mut output = String::new();

    assert_eq!(client.next(&mut output).await, ServerMessage::Approved { by: ApprovedBy::Policy, stdin: false });
    assert_eq!(client.next(&mut output).await, finished(3));
    assert!(
        output.contains(
            "river.h.nul.ie journalctl --no-pager --output=short-iso --lines=50 --since=-7200s --unit=nginx.service"
        ),
        "{output}"
    );
}

#[tokio::test]
async fn requests_lists_pending_and_leases() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "ask", "leases": [300] } }));

    let mut waiting = Client::start(&broker, ssh(&["true"])).await;
    pending_id(&mut waiting).await;

    let mut client = Client::start(&broker, Operation::Requests).await;
    let mut output = String::new();
    assert_eq!(client.next(&mut output).await, ServerMessage::Approved { by: ApprovedBy::Policy, stdin: false });

    match client.next(&mut output).await {
        ServerMessage::Finished { exit: 0, result: Some(OpResult::Requests { pending, leases }) } => {
            assert_eq!(pending.len(), 1);
            assert_eq!(pending[0].summary, "ssh river");
            assert!(leases.is_empty());
        }
        other => panic!("unexpected {other:?}"),
    }
}

/// Connects to the remote socket the way `slop-broker remote` does.
async fn remote(path: &Path, role: Role, name: &str) -> Transport<tokio::net::UnixStream> {
    let mut stream = tokio::net::UnixStream::connect(path).await.unwrap();
    write_hello(&mut stream, &Hello { role, name: name.into() }).await.unwrap();
    transport(stream)
}

#[tokio::test]
async fn remote_requesters_and_approvers_use_one_socket() {
    let directory = tempfile::tempdir().unwrap();
    let broker = broker(directory.path(), json!({ "ssh": { "action": "ask" } }));
    let path = directory.path().join("remote.sock");
    let listener = tokio::net::UnixListener::bind(&path).unwrap();
    tokio::spawn(slop_broker::remote::listen(broker.clone(), listener, unsafe { libc::geteuid() }));

    let mut requester = remote(&path, Role::Requester, "agent").await;
    let request = ClientMessage::Request(Request { version: PROTOCOL_VERSION, label: None, operation: ssh(&["true"]) });
    send(&mut requester, &request).await.unwrap();
    let Some(ServerMessage::Pending { id, .. }) = receive(&mut requester).await.unwrap() else { panic!("not pending") };

    // One approver connection carries several requests.
    let mut approver = remote(&path, Role::Approver, "laptop").await;
    send(&mut approver, &ApproveRequest::List).await.unwrap();
    let Some(ApproveResponse::Pending(entries)) = receive(&mut approver).await.unwrap() else { panic!("no list") };
    assert_eq!(entries[0].id, id);

    send(&mut approver, &ApproveRequest::Decide { id: id.clone(), decision: Decision::Once }).await.unwrap();
    assert!(matches!(receive(&mut approver).await.unwrap(), Some(ApproveResponse::Recorded)));
    assert!(matches!(
        receive::<_, ServerMessage>(&mut requester).await.unwrap(),
        Some(ServerMessage::Approved { by: ApprovedBy::Approver, .. })
    ));

    let events: Vec<String> = broker.audit.tail(10).unwrap().iter().map(|r| r.event.to_string()).collect();
    assert!(events.iter().any(|e| e.ends_with("answered once by laptop (ssh)")), "{events:?}");

    // Names must be configured for the role they claim.
    for (role, name) in [(Role::Approver, "agent"), (Role::Requester, "laptop")] {
        let mut stream = remote(&path, role, name).await;
        let _ = send(&mut stream, &ApproveRequest::List).await;
        assert!(receive::<_, ApproveResponse>(&mut stream).await.map_or(true, |r| r.is_none()));
    }
}
