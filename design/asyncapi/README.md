# Oxide CI - AsyncAPI Specification

> Event-driven API specification for a Rust-based CI/CD engine.

## Overview

This AsyncAPI 3.0 specification defines the event-driven architecture for **Oxide CI**, a hypothetical API-first CI/CD system written entirely in Rust.

## Event Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              EVENT TIMELINE                                   │
└──────────────────────────────────────────────────────────────────────────────┘

  GitHub Push                 Scheduler                    Agent Pool
       │                          │                            │
       ▼                          │                            │
  ┌─────────┐                     │                            │
  │ webhook │                     │                            │
  │ .github │                     │                            │
  └────┬────┘                     │                            │
       │                          │                            │
       ▼                          ▼                            │
  ┌──────────────────────────────────┐                         │
  │        run.{id}.queued           │─────────────────────────┤
  └──────────────────────────────────┘                         │
                                                               ▼
                                                    ┌──────────────────┐
                                                    │ agent.{id}       │
                                                    │ .heartbeat       │
                                                    └────────┬─────────┘
                                                             │
       ┌─────────────────────────────────────────────────────┘
       │
       ▼
  ┌──────────────────────────────────┐
  │        run.{id}.started          │
  └──────────────────────────────────┘
       │
       ▼
  ┌──────────────────────────────────┐
  │  run.{id}.stage.{name}.started   │
  └──────────────────────────────────┘
       │
       ▼
  ┌──────────────────────────────────┐
  │  run.{id}.step.{id}.started      │
  └──────────────────────────────────┘
       │
       │  ┌─────────────────────────────────────────────────────────────┐
       ├──│  run.{id}.step.{id}.output  (streaming, many messages)     │
       │  └─────────────────────────────────────────────────────────────┘
       │
       ▼
  ┌──────────────────────────────────┐
  │  run.{id}.step.{id}.completed    │
  └──────────────────────────────────┘
       │
       ▼
  ┌──────────────────────────────────┐
  │  run.{id}.stage.{name}.completed │
  └──────────────────────────────────┘
       │
       ▼
  ┌──────────────────────────────────┐     ┌──────────────────────────────┐
  │     run.{id}.completed           │────▶│  artifact.{id}.uploaded      │
  └──────────────────────────────────┘     └──────────────────────────────┘
```

## Channel Categories

| Category | Channels | Purpose |
|----------|----------|---------|
| **Pipeline** | `pipeline.created`, `pipeline.updated`, `pipeline.deleted` | Pipeline CRUD events |
| **Run** | `run.*.queued`, `run.*.started`, `run.*.completed`, `run.*.cancelled` | Run lifecycle |
| **Stage** | `run.*.stage.*.started`, `run.*.stage.*.completed` | Stage lifecycle |
| **Step** | `run.*.step.*.started`, `run.*.step.*.output`, `run.*.step.*.completed` | Step execution + streaming logs |
| **Agent** | `agent.registered`, `agent.*.heartbeat`, `agent.disconnected` | Agent pool management |
| **Webhook** | `webhook.github` | Inbound webhook events |
| **Artifact** | `artifact.*.uploaded` | Build artifact events |
| **Plugin** | `plugin.loaded`, `plugin.unloaded` | WASM plugin lifecycle |

## Message Protocols

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRANSPORT LAYER                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │
│   │   WebSocket     │  │     NATS        │  │   Server-Sent   │            │
│   │   (wss://)      │  │   (nats://)     │  │   Events (SSE)  │            │
│   ├─────────────────┤  ├─────────────────┤  ├─────────────────┤            │
│   │ • Bidirectional │  │ • Pub/Sub       │  │ • Unidirectional│            │
│   │ • Real-time     │  │ • Queue groups  │  │ • HTTP-based    │            │
│   │ • Client-facing │  │ • Internal bus  │  │ • Log streaming │            │
│   └─────────────────┘  └─────────────────┘  └─────────────────┘            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Usage

### Generate Documentation

```bash
# Install AsyncAPI CLI
npm install -g @asyncapi/cli

# Generate HTML docs
asyncapi generate fromTemplate asyncapi.yaml @asyncapi/html-template -o docs/

# Generate Markdown
asyncapi generate fromTemplate asyncapi.yaml @asyncapi/markdown-template -o docs/
```

### Generate Code

```bash
# Generate Rust types (using custom template)
asyncapi generate models asyncapi.yaml -o src/events/ -l rust

# Generate TypeScript client
asyncapi generate fromTemplate asyncapi.yaml @asyncapi/typescript-nats-template
```

### Validate

```bash
asyncapi validate asyncapi.yaml
```

## Example: Subscribing to Events (Rust)

```rust
use futures::StreamExt;
use tokio_tungstenite::connect_async;

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
enum CiEvent {
    #[serde(rename = "run.started")]
    RunStarted(RunStartedEvent),
    #[serde(rename = "run.completed")]
    RunCompleted(RunCompletedEvent),
    #[serde(rename = "step.output")]
    StepOutput(StepOutputEvent),
}

async fn subscribe_to_run(run_id: Uuid) -> Result<()> {
    let url = format!("wss://api.oxideci.io/ws/runs/{}", run_id);
    let (ws_stream, _) = connect_async(&url).await?;
    let (_, mut read) = ws_stream.split();

    while let Some(msg) = read.next().await {
        let event: CiEvent = serde_json::from_str(&msg?.to_text()?)?;
        match event {
            CiEvent::StepOutput(e) => print!("{}", e.line),
            CiEvent::RunCompleted(e) => {
                println!("Run {} finished: {:?}", run_id, e.status);
                break;
            }
            _ => {}
        }
    }
    Ok(())
}
```

## Example: Agent Heartbeat Loop (Rust)

```rust
use std::time::Duration;
use tokio::time::interval;

async fn heartbeat_loop(agent_id: Uuid, nats: async_nats::Client) -> Result<()> {
    let mut ticker = interval(Duration::from_secs(10));
    
    loop {
        ticker.tick().await;
        
        let metrics = collect_system_metrics().await;
        let heartbeat = AgentHeartbeat {
            agent_id,
            timestamp: Utc::now(),
            status: get_agent_status(),
            current_run_id: get_current_run(),
            system_metrics: metrics,
        };
        
        let subject = format!("agent.{}.heartbeat", agent_id);
        nats.publish(subject, serde_json::to_vec(&heartbeat)?).await?;
    }
}
```

## Schema Reference

See `asyncapi.yaml` for complete schema definitions:

- **Pipeline** - Pipeline configuration with stages and steps
- **Run** - Pipeline execution instance
- **Stage** - Group of steps with dependencies
- **Step** - Individual execution unit (plugin invocation)
- **Agent** - Worker node in the execution pool
- **Plugin** - WASM plugin metadata

## Related

- [AsyncAPI Specification](https://www.asyncapi.com/)
- [AsyncAPI Studio](https://studio.asyncapi.com/) - Visual editor
- [AsyncAPI Generator](https://github.com/asyncapi/generator) - Code generation
