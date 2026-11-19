//! Broker that runs privileged operations for coding agents, under a policy and with human
//! approval. See `docs/slop-broker.md` in nixfiles.
pub mod approve;
pub mod audit;
pub mod builder;
pub mod config;
pub mod exec;
pub mod ha;
pub mod ops;
pub mod policy;
pub mod proto;
pub mod queue;
pub mod remote;
pub mod server;
pub mod types;
