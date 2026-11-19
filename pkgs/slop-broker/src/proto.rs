//! Messages between `slop` and the broker, and between `slop-approve` and the broker.
//!
//! Each message is CBOR, framed with a 4-byte big-endian length (`LengthDelimitedCodec`). A
//! requester sends one [`ClientMessage::Request`], then (only after an `Approved` that asks for
//! it) stdin. The broker answers with [`ServerMessage`]s and closes after a terminal one.
use std::num::NonZeroU16;

use anyhow::{Context, Result, bail};
use bytes::Bytes;
use futures_util::{SinkExt, StreamExt};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_util::codec::{Framed, LengthDelimitedCodec};

use crate::audit::Record;
use crate::queue::{Decision, PendingInfo};
use crate::types::{Arg, CommitId, DeployTarget, HostName, Lines, NodeName, Since, UnitName, UserName};

/// Bumped on any incompatible change; the broker refuses other versions.
pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_MESSAGE: usize = 1 << 20;
pub const DEFAULT_VSOCK_PORT: u32 = 6262;
/// The host's CID, as seen from a guest.
pub const HOST_CID: u32 = 2;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub enum ClientMessage {
    Request(Request),
    Stdin(#[serde(with = "serde_bytes")] Vec<u8>),
    StdinEnd,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub version: u32,
    /// Free text from the agent (who it is, why); shown to approvers as agent-supplied.
    pub label: Option<String>,
    pub operation: Operation,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub enum Operation {
    /// A command over SSH, joined with spaces and run by the remote shell (as `ssh` does).
    Ssh { destination: Destination, command: Vec<Arg> },
    /// A fixed read-only query, run over SSH with a command the broker builds.
    Query { destination: Destination, query: Query },
    /// This requester's pending requests and leases.
    Requests,
    /// Builds a pushed commit and, once approved, activates it on deploy nodes, all at once.
    Deploy {
        targets: Vec<DeployTarget>,
        commit: CommitId,
        /// Make it the boot default without switching to it.
        boot: bool,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub enum Destination {
    /// A configured target (normally a deploy-rs node), with its configured user and options.
    Node(NodeName),
    Host {
        user: UserName,
        host: HostName,
        port: NonZeroU16,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub enum Query {
    /// `systemctl status`, of one unit or of the whole box.
    Status {
        unit: Option<UnitName>,
    },
    Logs {
        unit: UnitName,
        lines: Lines,
        since: Option<Since>,
    },
    Failed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub enum ServerMessage {
    /// Waiting for an approver.
    Pending {
        id: String,
        summary: String,
    },
    /// Output follows. The client sends its stdin only if `stdin` is set.
    Approved {
        by: ApprovedBy,
        stdin: bool,
    },
    /// Progress from the broker itself.
    Info(String),
    Stdout(#[serde(with = "serde_bytes")] Vec<u8>),
    Stderr(#[serde(with = "serde_bytes")] Vec<u8>),
    /// The operation ran; `exit` is its status and `result` any structured output.
    Finished {
        exit: i32,
        result: Option<OpResult>,
    },
    Denied(String),
    Expired,
    Error(String),
}

impl ServerMessage {
    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Finished { .. } | Self::Denied(_) | Self::Expired | Self::Error(_))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ApprovedBy {
    Policy,
    Lease,
    Approver,
}

/// Structured results of operations that produce data rather than a stream.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub enum OpResult {
    Requests { pending: Vec<PendingSummary>, leases: Vec<LeaseSummary> },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PendingSummary {
    pub id: String,
    pub summary: String,
    pub expires_in: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LeaseSummary {
    pub scope: String,
    pub remaining: u64,
}

/// Approver socket requests.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub enum ApproveRequest {
    List,
    Decide {
        id: String,
        decision: Decision,
    },
    /// The last `count` audit records, at most [`MAX_LOG_RECORDS`].
    Log {
        count: usize,
    },
}

/// Keeps a `Log` response well within [`MAX_MESSAGE`].
pub const MAX_LOG_RECORDS: usize = 200;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case", deny_unknown_fields)]
pub enum ApproveResponse {
    Pending(Vec<PendingInfo>),
    Recorded,
    Log(Vec<Record>),
    Error(String),
}

pub type Transport<S> = Framed<S, LengthDelimitedCodec>;

pub fn codec() -> LengthDelimitedCodec {
    LengthDelimitedCodec::builder().max_frame_length(MAX_MESSAGE).new_codec()
}

pub fn transport<S: AsyncRead + AsyncWrite>(stream: S) -> Transport<S> {
    Framed::new(stream, codec())
}

pub fn encode<T: Serialize>(message: &T) -> Result<Bytes> {
    let mut buffer = Vec::new();
    ciborium::into_writer(message, &mut buffer)?;
    if buffer.len() > MAX_MESSAGE {
        bail!("message too large");
    }
    Ok(buffer.into())
}

pub fn decode<T: DeserializeOwned>(data: &[u8]) -> Result<T> {
    ciborium::from_reader(data).context("invalid message")
}

pub async fn send<S, T>(transport: &mut S, message: &T) -> Result<()>
where
    S: futures_util::Sink<Bytes, Error = std::io::Error> + Unpin,
    T: Serialize,
{
    transport.send(encode(message)?).await?;
    Ok(())
}

/// The next message, or `None` at a clean end of stream.
pub async fn receive<S, T>(transport: &mut S) -> Result<Option<T>>
where
    S: futures_util::Stream<Item = std::io::Result<bytes::BytesMut>> + Unpin,
    T: DeserializeOwned,
{
    match transport.next().await {
        None => Ok(None),
        Some(frame) => Ok(Some(decode(&frame?)?)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn messages_round_trip() {
        let (a, b) = tokio::io::duplex(1024);
        let (mut a, mut b) = (transport(a), transport(b));
        let request = ClientMessage::Request(Request {
            version: PROTOCOL_VERSION,
            label: Some("test".into()),
            operation: Operation::Query {
                destination: Destination::Node("river".parse().unwrap()),
                query: Query::Logs { unit: "nginx.service".parse().unwrap(), lines: Lines::DEFAULT, since: None },
            },
        });

        send(&mut a, &request).await.unwrap();
        send(&mut a, &ClientMessage::Stdin(b"\0\xffbytes".to_vec())).await.unwrap();
        drop(a);

        assert_eq!(receive::<_, ClientMessage>(&mut b).await.unwrap(), Some(request));
        assert_eq!(
            receive::<_, ClientMessage>(&mut b).await.unwrap(),
            Some(ClientMessage::Stdin(b"\0\xffbytes".to_vec()))
        );
        assert_eq!(receive::<_, ClientMessage>(&mut b).await.unwrap(), None);
    }

    #[test]
    fn invalid_values_fail_to_decode() {
        #[derive(Serialize)]
        #[serde(rename_all = "kebab-case")]
        enum Loose {
            Node(String),
        }
        let data = encode(&Loose::Node("-oProxyCommand=x".into())).unwrap();
        assert!(decode::<Destination>(&data).is_err());
        let data = encode(&Loose::Node("river".into())).unwrap();
        assert!(decode::<Destination>(&data).is_ok());
    }

    #[tokio::test]
    async fn oversized_frames_are_rejected() {
        use tokio::io::AsyncWriteExt;
        let (mut a, b) = tokio::io::duplex(64);
        a.write_all(&u32::MAX.to_be_bytes()).await.unwrap();
        assert!(receive::<_, ClientMessage>(&mut transport(b)).await.is_err());
    }
}
