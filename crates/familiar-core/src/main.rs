mod brain;
mod model_store;
mod protocol;
mod provider;
mod world;

use brain::{Brain, BrainController, BrainStatus};
use protocol::{CORE_VERSION, ClientMessage, PROTOCOL_VERSION, ServerMessage};
use std::io::{self, BufRead, BufWriter, Write};
use world::World;

fn write_message(
    out: &mut BufWriter<io::StdoutLock<'_>>,
    message: &ServerMessage,
) -> io::Result<()> {
    serde_json::to_writer(&mut *out, message)?;
    out.write_all(b"\n")?;
    out.flush()
}

fn protocol_error(out: &mut BufWriter<io::StdoutLock<'_>>, message: impl Into<String>) {
    let _ = write_message(
        out,
        &ServerMessage::Error {
            message: message.into(),
        },
    );
}

fn brain_status_key(status: &BrainStatus) -> String {
    format!(
        "{}|{}|{}|{}|{:?}|{:?}|{}|{}|{}",
        status.enabled,
        status.provider,
        status.state,
        status.error.as_deref().unwrap_or(""),
        status.last_latency_ms,
        status.last_choice,
        status.consecutive_failures,
        status.total_requests,
        status.total_successes,
    )
}

fn emit_brain_status(
    out: &mut BufWriter<io::StdoutLock<'_>>,
    brain: &mut BrainController,
    previous: &mut Option<String>,
) -> io::Result<()> {
    let status = brain.status();
    let key = brain_status_key(&status);
    if previous.as_ref() == Some(&key) {
        return Ok(());
    }
    *previous = Some(key);
    write_message(
        out,
        &ServerMessage::BrainStatus {
            enabled: status.enabled,
            provider: status.provider,
            state: status.state,
            error: status.error,
            last_latency_ms: status.last_latency_ms,
            last_choice: status.last_choice,
            consecutive_failures: status.consecutive_failures,
            total_requests: status.total_requests,
            total_successes: status.total_successes,
        },
    )
}

fn run_protocol() -> io::Result<()> {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    let mut world = World::default();
    let mut brain = BrainController::default();
    let mut handshaken = false;
    let mut last_brain_status = None;

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(line) => line,
            Err(error) => {
                protocol_error(&mut out, format!("stdin error: {error}"));
                break;
            }
        };

        if line.trim().is_empty() {
            continue;
        }

        let message = match serde_json::from_str::<ClientMessage>(&line) {
            Ok(message) => message,
            Err(error) => {
                protocol_error(&mut out, format!("invalid json: {error}"));
                continue;
            }
        };

        match message {
            ClientMessage::Hello { protocol, client } => {
                if protocol != PROTOCOL_VERSION {
                    protocol_error(
                        &mut out,
                        format!("protocol mismatch: client={protocol}, core={PROTOCOL_VERSION}"),
                    );
                    continue;
                }

                eprintln!("familiar-core: connected client {client}");
                handshaken = true;
                write_message(
                    &mut out,
                    &ServerMessage::Ready {
                        protocol: PROTOCOL_VERSION,
                        core: "familiar-core",
                        version: CORE_VERSION,
                        local_llama: cfg!(feature = "local-llama"),
                    },
                )?;
            }
            ClientMessage::Configure { brain: config } => {
                if !handshaken {
                    protocol_error(&mut out, "hello required before configure");
                    continue;
                }
                brain.configure(config);
                last_brain_status = None;
                emit_brain_status(&mut out, &mut brain, &mut last_brain_status)?;
            }
            ClientMessage::Snapshot { seq, snapshot } => {
                if !handshaken {
                    protocol_error(&mut out, "hello required before snapshot");
                    continue;
                }

                world.apply_snapshot(snapshot);
                let intent = brain.decide(&world);
                write_message(&mut out, &ServerMessage::Intent { seq, intent })?;
                emit_brain_status(&mut out, &mut brain, &mut last_brain_status)?;
            }
            ClientMessage::Event { seq, event } => {
                if !handshaken {
                    protocol_error(&mut out, "hello required before event");
                    continue;
                }

                world.apply_event(event);
                let intent = brain.decide(&world);
                write_message(&mut out, &ServerMessage::Intent { seq, intent })?;
                emit_brain_status(&mut out, &mut brain, &mut last_brain_status)?;
            }
            ClientMessage::Ping { id } => {
                write_message(&mut out, &ServerMessage::Pong { id })?;
            }
            ClientMessage::Shutdown => break,
        }
    }

    Ok(())
}

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match model_store::run_cli(&args) {
        Ok(true) => return Ok(()),
        Ok(false) => {}
        Err(error) => {
            eprintln!("familiar-core: {error}");
            std::process::exit(2);
        }
    }
    run_protocol()
}
