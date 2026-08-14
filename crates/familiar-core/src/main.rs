use serde::{Deserialize, Serialize};
use std::io::{self, BufRead, BufWriter, Write};

const PROTOCOL_VERSION: u32 = 1;
const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ClientMessage {
    Hello { protocol: u32, client: String },
    Snapshot { seq: u64, snapshot: EditorSnapshot },
    Event { seq: u64, event: EditorEvent },
    Ping { id: u64 },
    Shutdown,
}

#[derive(Debug, Clone, Deserialize)]
struct EditorSnapshot {
    mode: String,
    buffer: BufferSnapshot,
    viewport: ViewportSnapshot,
    diagnostics: DiagnosticSnapshot,
    activity: ActivitySnapshot,
}

#[derive(Debug, Clone, Deserialize)]
struct BufferSnapshot {
    id: i64,
    name: String,
    filetype: String,
    modified: bool,
    line_count: u64,
}

#[derive(Debug, Clone, Deserialize)]
struct ViewportSnapshot {
    width: u64,
    height: u64,
    cursor_row: u64,
    cursor_col: u64,
    topline: u64,
    botline: u64,
    #[serde(default)]
    line_display_widths: Vec<u64>,
}

#[derive(Debug, Clone, Deserialize)]
struct DiagnosticSnapshot {
    errors: u64,
    warnings: u64,
}

#[derive(Debug, Clone, Deserialize)]
struct ActivitySnapshot {
    idle_ms: u64,
    typing: bool,
    buffer_switches_10s: u64,
}

#[derive(Debug, Clone, Deserialize)]
struct EditorEvent {
    kind: String,
    #[serde(default)]
    buffer: Option<i64>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ServerMessage {
    Ready {
        protocol: u32,
        core: &'static str,
        version: &'static str,
    },
    Intent {
        seq: u64,
        intent: BehaviorIntent,
    },
    Pong {
        id: u64,
    },
    Error {
        message: String,
    },
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum Behavior {
    Idle,
    Focus,
    Inspect,
    Sleep,
    Hide,
    Curious,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum Target {
    QuietCorner,
    CursorArea,
    ScreenEdge,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum Locomotion {
    Auto,
    Walk,
    Run,
    Vanish,
    None,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum Mood {
    Calm,
    Focused,
    Curious,
    Concerned,
    Sleepy,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
struct BehaviorIntent {
    behavior: Behavior,
    target: Target,
    locomotion: Locomotion,
    mood: Mood,
    #[serde(skip_serializing_if = "Option::is_none")]
    emote: Option<&'static str>,
    duration_ms: u64,
}

#[derive(Default)]
struct World {
    snapshot: Option<EditorSnapshot>,
    last_event: Option<EditorEvent>,
}

impl World {
    fn apply_snapshot(&mut self, snapshot: EditorSnapshot) {
        self.snapshot = Some(snapshot);
    }

    fn apply_event(&mut self, event: EditorEvent) {
        self.last_event = Some(event);
    }
}

fn plan(world: &World) -> BehaviorIntent {
    let Some(snapshot) = world.snapshot.as_ref() else {
        return BehaviorIntent {
            behavior: Behavior::Hide,
            target: Target::ScreenEdge,
            locomotion: Locomotion::None,
            mood: Mood::Calm,
            emote: None,
            duration_ms: 3_000,
        };
    };

    if snapshot.viewport.width < 48 || snapshot.viewport.height < 12 {
        return BehaviorIntent {
            behavior: Behavior::Hide,
            target: Target::ScreenEdge,
            locomotion: Locomotion::Vanish,
            mood: Mood::Calm,
            emote: None,
            duration_ms: 5_000,
        };
    }

    if snapshot.activity.idle_ms >= 120_000 {
        return BehaviorIntent {
            behavior: Behavior::Sleep,
            target: Target::QuietCorner,
            locomotion: Locomotion::Walk,
            mood: Mood::Sleepy,
            emote: Some("sleep"),
            duration_ms: 30_000,
        };
    }

    if snapshot.diagnostics.errors > 0 {
        return BehaviorIntent {
            behavior: Behavior::Inspect,
            target: Target::CursorArea,
            locomotion: Locomotion::Walk,
            mood: Mood::Concerned,
            emote: Some("question"),
            duration_ms: 7_000,
        };
    }

    let just_switched_buffer = world
        .last_event
        .as_ref()
        .is_some_and(|event| event.kind == "buffer_enter");

    if snapshot.activity.buffer_switches_10s >= 3
        || (just_switched_buffer && snapshot.activity.buffer_switches_10s >= 2)
    {
        return BehaviorIntent {
            behavior: Behavior::Curious,
            target: Target::QuietCorner,
            locomotion: Locomotion::Run,
            mood: Mood::Curious,
            emote: Some("question"),
            duration_ms: 6_000,
        };
    }

    if snapshot.activity.typing || snapshot.mode.starts_with('i') {
        return BehaviorIntent {
            behavior: Behavior::Focus,
            target: Target::QuietCorner,
            locomotion: Locomotion::None,
            mood: Mood::Focused,
            emote: None,
            duration_ms: 8_000,
        };
    }

    BehaviorIntent {
        behavior: Behavior::Idle,
        target: Target::QuietCorner,
        locomotion: Locomotion::Auto,
        mood: Mood::Calm,
        emote: None,
        duration_ms: 10_000,
    }
}

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

                let _context = (
                    snapshot.buffer.id,
                    snapshot.buffer.name.len(),
                    snapshot.buffer.filetype.len(),
                    snapshot.buffer.modified,
                    snapshot.buffer.line_count,
                    snapshot.viewport.cursor_row,
                    snapshot.viewport.cursor_col,
                    snapshot.viewport.topline,
                    snapshot.viewport.botline,
                    snapshot.viewport.line_display_widths.len(),
                    snapshot.diagnostics.warnings,
                );

                world.apply_snapshot(snapshot);
                let intent = plan(&world);
                write_message(&mut out, &ServerMessage::Intent { seq, intent })?;
            }
            ClientMessage::Event { seq, event } => {
                if !handshaken {
                    protocol_error(&mut out, "hello required before event");
                    continue;
                }
                let _event_context = (event.kind.as_str(), event.buffer);
                world.apply_event(event);
                let intent = plan(&world);
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

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot() -> EditorSnapshot {
        EditorSnapshot {
            mode: "n".into(),
            buffer: BufferSnapshot {
                id: 1,
                name: "notes.md".into(),
                filetype: "markdown".into(),
                modified: false,
                line_count: 120,
            },
            viewport: ViewportSnapshot {
                width: 120,
                height: 40,
                cursor_row: 10,
                cursor_col: 3,
                topline: 1,
                botline: 40,
                line_display_widths: vec![20, 30],
            },
            diagnostics: DiagnosticSnapshot {
                errors: 0,
                warnings: 0,
            },
            activity: ActivitySnapshot {
                idle_ms: 0,
                typing: false,
                buffer_switches_10s: 0,
            },
        }
    }

    #[test]
    fn hides_in_small_windows() {
        let mut s = snapshot();
        s.viewport.width = 30;
        let world = World {
            snapshot: Some(s),
            last_event: None,
        };
        assert_eq!(plan(&world).behavior, Behavior::Hide);
    }

    #[test]
    fn sustained_idle_prefers_sleep() {
        let mut s = snapshot();
        s.activity.idle_ms = 130_000;
        let world = World {
            snapshot: Some(s),
            last_event: None,
        };
        assert_eq!(plan(&world).behavior, Behavior::Sleep);
    }

    #[test]
    fn typing_prefers_focus() {
        let mut s = snapshot();
        s.activity.typing = true;
        let world = World {
            snapshot: Some(s),
            last_event: None,
        };
        assert_eq!(plan(&world).behavior, Behavior::Focus);
    }
}
