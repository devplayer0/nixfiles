//! Home Assistant Companion notifications for pending requests. The broker connects out to Home
//! Assistant's WebSocket API; nothing listens for approvals over HTTP.
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio_tungstenite::tungstenite::Message;
use url::Url;

use crate::approve;
use crate::config::HomeAssistantConfig;
use crate::ops::truncate;
use crate::queue::{Decision, PendingInfo};
use crate::server::Broker;

pub fn validate(config: &HomeAssistantConfig) -> Result<()> {
    let url = Url::parse(&config.url)?;
    if !matches!(url.scheme(), "ws" | "wss") || url.host_str().is_none() || url.path() != "/api/websocket" {
        bail!("Home Assistant URL must be ws(s)://host/api/websocket");
    }
    if !url.username().is_empty() || url.password().is_some() || url.query().is_some() || url.fragment().is_some() {
        bail!("Home Assistant URL must not contain credentials, a query or a fragment");
    }

    let service = config.notify_service.strip_prefix("mobile_app_").unwrap_or("");
    if service.is_empty() || !service.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_') {
        bail!("notification service must be mobile_app_<device>");
    }

    if config.device_id.is_empty() {
        bail!("Home Assistant device_id is required");
    }
    Ok(())
}

pub async fn run(broker: Arc<Broker>, config: HomeAssistantConfig, token: String) {
    loop {
        // The token is only ever sent, and the URL can't hold credentials, so errors are safe to log.
        if let Err(error) = session(&broker, &config, &token).await {
            eprintln!("<4>Home Assistant connection unavailable ({error:#}); retrying in 5 seconds");
        }
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

/// Notification state for one connection; action IDs are never reused across connections.
struct Notifier<'a> {
    broker: &'a Broker,
    config: &'a HomeAssistantConfig,
    sequence: u64,
    /// Random action ID → (request ID, decision).
    actions: HashMap<String, (String, Decision)>,
    sent: HashSet<String>,
}

async fn session(broker: &Broker, config: &HomeAssistantConfig, token: &str) -> Result<()> {
    let (mut socket, _) =
        tokio::time::timeout(Duration::from_secs(10), tokio_tungstenite::connect_async(&config.url)).await??;

    if read_message(&mut socket).await?["type"] != "auth_required" {
        bail!("expected authentication challenge");
    }
    send(&mut socket, json!({ "type": "auth", "access_token": token })).await?;
    if read_message(&mut socket).await?["type"] != "auth_ok" {
        bail!("authentication failed");
    }

    let mut notifier = Notifier { broker, config, sequence: 0, actions: HashMap::new(), sent: HashSet::new() };
    let subscription = notifier.next_id();
    send(
        &mut socket,
        json!({ "id": subscription, "type": "subscribe_events", "event_type": "mobile_app_notification_action" }),
    )
    .await?;
    let response = read_message(&mut socket).await?;
    if response["id"] != subscription || response["type"] != "result" || response["success"] != true {
        bail!("subscribing to notification actions failed: {}", response["error"]["message"]);
    }

    let mut changes = broker.queue.subscribe();
    let mut tick = tokio::time::interval(Duration::from_secs(5));
    loop {
        notifier.sync(&mut socket).await?;
        tokio::select! {
            message = read_message(&mut socket) => {
                let message = message?;
                if message["type"] == "result" && message["success"] == false {
                    bail!("service call failed");
                }
                notifier.handle_event(&message);
            }
            _ = changes.changed() => {}
            _ = tick.tick() => {}
        }
    }
}

type Socket = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn read_message(socket: &mut Socket) -> Result<Value> {
    loop {
        match socket.next().await.context("connection closed")?? {
            Message::Text(text) => return Ok(serde_json::from_str(&text)?),
            Message::Close(_) => bail!("connection closed"),
            _ => continue,
        }
    }
}

async fn send(socket: &mut Socket, message: Value) -> Result<()> {
    socket.send(Message::text(message.to_string())).await?;
    Ok(())
}

impl Notifier<'_> {
    fn next_id(&mut self) -> u64 {
        self.sequence += 1;
        self.sequence
    }

    async fn notify(&mut self, socket: &mut Socket, data: Value) -> Result<()> {
        let id = self.next_id();
        let message = json!({
            "id": id, "type": "call_service", "domain": "notify", "service": self.config.notify_service, "service_data": data,
        });
        send(socket, message).await
    }

    async fn sync(&mut self, socket: &mut Socket) -> Result<()> {
        let pending: HashMap<String, PendingInfo> =
            self.broker.queue.list().into_iter().map(|e| (e.id.clone(), e)).collect();
        self.actions.retain(|_, (id, _)| pending.contains_key(id));

        let gone: Vec<String> = self.sent.iter().filter(|id| !pending.contains_key(*id)).cloned().collect();
        for id in gone {
            self.notify(socket, json!({ "message": "clear_notification", "data": { "tag": format!("slop-{id}") } }))
                .await?;
            self.sent.remove(&id);
        }

        for (id, entry) in pending {
            if !self.sent.contains(&id) {
                let data = self.notification(&entry);
                self.notify(socket, data).await?;
                self.sent.insert(id);
            }
        }
        Ok(())
    }

    fn notification(&mut self, entry: &PendingInfo) -> Value {
        // Android shows at most three actions: once, the shortest lease and deny.
        let mut decisions = vec![Decision::Once];
        if let Some(&lease) = entry.offers.iter().find(|d| matches!(d, Decision::Lease(_))) {
            decisions.push(lease);
        }
        decisions.push(Decision::Deny);

        let buttons: Vec<Value> = decisions
            .into_iter()
            .map(|decision| {
                // Independent of request IDs, which requesters can see.
                let action = format!("SLOP_{}", hex::encode(rand::random::<[u8; 32]>()));
                self.actions.insert(action.clone(), (entry.id.clone(), decision));
                json!({ "action": action, "title": decision.title(), "authenticationRequired": true })
            })
            .collect();

        let mut message = format!("{}\n{}", entry.summary, truncate(&entry.detail, 400));
        if let Some(label) = &entry.label {
            message += &format!("\nAgent says: {}", truncate(label, 120));
        }
        message += &format!("\nFrom {}", entry.requester);

        let title = if entry.sensitive { "Agent approval (sensitive)" } else { "Agent approval" };
        // Sticky, so tapping it doesn't remove it, and persistent, which stops swiping it away on
        // Android before 14; the broker clears it by tag once it's answered or expired.
        let data = json!({
            "tag": format!("slop-{}", entry.id),
            "actions": buttons,
            "persistent": true,
            "sticky": "true",
        });
        json!({ "title": title, "message": message, "data": data })
    }

    fn handle_event(&mut self, message: &Value) {
        let event = &message["event"];
        if message["type"] != "event" || event["event_type"] != "mobile_app_notification_action" {
            return;
        }

        // Other automations' actions aren't ours to mention.
        let data = &event["data"];
        let Some(action) = data["action"].as_str().filter(|a| a.starts_with("SLOP_")) else { return };
        let device = data["device_id"].as_str();
        if device != Some(self.config.device_id.as_str()) {
            eprintln!("<4>ignored a notification answer from device {device:?}; only the configured device may answer");
            return;
        }

        let Some((id, decision)) = self.actions.get(action).cloned() else {
            eprintln!("<4>ignored a notification answer for a request that's no longer pending");
            return;
        };
        // Fails harmlessly if it expired, was answered in a terminal, or arrived twice.
        let _ = approve::approve(self.broker, &id, decision, "home-assistant");
        self.actions.retain(|_, (other, _)| *other != id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(url: &str, service: &str) -> HomeAssistantConfig {
        HomeAssistantConfig {
            url: url.into(),
            notify_service: service.into(),
            device_id: "d".into(),
            token: "t".into(),
        }
    }

    #[test]
    fn validates_config() {
        assert!(validate(&config("wss://hass.nul.ie/api/websocket", "mobile_app_pixel")).is_ok());
        assert!(validate(&config("https://hass.nul.ie/api/websocket", "mobile_app_pixel")).is_err());
        assert!(validate(&config("wss://u:p@hass.nul.ie/api/websocket", "mobile_app_pixel")).is_err());
        assert!(validate(&config("wss://hass.nul.ie/api/websocket?x", "mobile_app_pixel")).is_err());
        assert!(validate(&config("wss://hass.nul.ie/api/websocket", "persistent_notification")).is_err());
    }
}
