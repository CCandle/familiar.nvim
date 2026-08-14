mod brain;
mod protocol;
mod world;

use brain::{Brain, RuleBrain};
use protocol::{ClientMessage, CORE_VERSION, PROTOCOL_VERSION, ServerMessage};
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

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    let mut world = World::default();
    let mut brain = RuleBrain;
    let mut handshaken = false;

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
                    },
                )?;
            }
            ClientMessage::Snapshot { seq, snapshot } => {
                if !handshaken {
                    protocol_error(&mut out, "hello required before snapshot");
                    continue;
                }

                world.apply_snapshot(snapshot);
                let intent = brain.decide(&world);
                write_message(&mut out, &ServerMessage::Intent { seq, intent })?;
            }
            ClientMessage::Event { seq, event } => {
                if !handshaken {
                    protocol_error(&mut out, "hello required before event");
                    continue;
                }

                world.apply_event(event);
                let intent = brain.decide(&world);
                write_message(&mut out, &ServerMessage::Intent { seq, intent })?;
            }
            ClientMessage::Ping { id } => {
                write_message(&mut out, &ServerMessage::Pong { id })?;
            }
            ClientMessage::Shutdown => break,
        }
    }

    Ok(())
}
