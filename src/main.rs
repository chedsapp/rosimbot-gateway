use std::{env, sync::Arc};

use futures_util::StreamExt;
use serde::Deserialize;
use twilight_gateway::{CloseFrame, ConfigBuilder, Intents, Message, Shard, ShardId};
use twilight_model::gateway::{
    payload::outgoing::update_presence::UpdatePresencePayload,
    presence::{ActivityType, MinimalActivity, Status},
};

const FORWARDED: &[&str] = &[];
const FATAL_CLOSE_CODES: &[u16] = &[4004, 4010, 4011, 4012, 4013, 4014];

#[derive(Deserialize)]
struct Envelope<'a> {
    op: u8,
    #[serde(borrow)]
    t: Option<&'a str>,
}

struct Forwarder {
    http: reqwest::Client,
    url: String,
    secret: String,
}

impl Forwarder {
    async fn send(&self, event: &str, body: String) {
        let res = self
            .http
            .post(&self.url)
            .header("content-type", "application/json")
            .header("x-gateway-secret", &self.secret)
            .body(body)
            .send()
            .await;

        match res {
            Ok(r) if r.status().is_success() => tracing::debug!(event, "forwarded"),
            Ok(r) => tracing::warn!(event, status = %r.status(), "worker rejected event"),
            Err(e) => tracing::warn!(event, error = %e, "failed to reach worker"),
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt::init();

    let token = env::var("DISCORD_TOKEN")?;
    let forwarder = Arc::new(Forwarder {
        http: reqwest::Client::new(),
        url: env::var("WORKER_URL")?,
        secret: env::var("GATEWAY_SECRET")?,
    });

    let intents = Intents::empty();

    let presence = UpdatePresencePayload::new(
        vec![
            MinimalActivity {
                kind: ActivityType::Watching,
                name: "the simulation".into(),
                url: None,
            }
            .into(),
        ],
        false,
        None,
        Status::Online,
    )?;

    let config = ConfigBuilder::new(token, intents)
        .presence(presence)
        .build();
    let mut shard = Shard::with_config(ShardId::ONE, config);
    tracing::info!("connecting to gateway");

    loop {
        let item = tokio::select! {
            item = shard.next() => item,
            _ = tokio::signal::ctrl_c() => {

                tracing::info!("shutting down");
                shard.close(CloseFrame::NORMAL);

                while let Some(Ok(msg)) = shard.next().await {
                    if matches!(msg, Message::Close(_)) { break; }
                }
                break;
            }
        };

        let Some(item) = item else { break };
        let msg = match item {
            Ok(msg) => msg,
            Err(e) => {
                tracing::warn!(error = %e, "error receiving message");
                continue;
            }
        };

        match msg {
            Message::Text(json) => {
                let Ok(env) = serde_json::from_str::<Envelope>(&json) else {
                    continue;
                };
                if env.op != 0 {
                    continue;
                }
                let Some(event) = env.t else { continue };
                if event == "READY" {
                    tracing::info!("ready, bot is online");
                }
                if !FORWARDED.contains(&event) {
                    continue;
                }

                let event = event.to_owned();
                let fwd = Arc::clone(&forwarder);
                tokio::spawn(async move { fwd.send(&event, json).await });
            }
            Message::Close(frame) => {
                let code = frame.as_ref().map(|f| f.code);
                tracing::warn!(?code, "gateway closed connection");
                if code.is_some_and(|c| FATAL_CLOSE_CODES.contains(&c)) {
                    anyhow::bail!("fatal gateway close code {code:?}; check token/intents");
                }
            }
        }
    }

    Ok(())
}
