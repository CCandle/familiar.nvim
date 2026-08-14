use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u32 = 1;
pub const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    Hello { protocol: u32, client: String },
    Snapshot { seq: u64, snapshot: EditorSnapshot },
    Event { seq: u64, event: EditorEvent },
    Ping { id: u64 },
    Shutdown,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct EditorSnapshot {
    pub mode: String,
    pub buffer: BufferSnapshot,
    pub viewport: ViewportSnapshot,
    pub diagnostics: DiagnosticSnapshot,
    pub activity: ActivitySnapshot,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct BufferSnapshot {
    pub id: i64,
    pub name: String,
    pub filetype: String,
    pub modified: bool,
    pub line_count: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct ViewportSnapshot {
    pub width: u64,
    pub height: u64,
    pub cursor_row: u64,
    pub cursor_col: u64,
    pub topline: u64,
    pub botline: u64,
    #[serde(default)]
    pub line_display_widths: Vec<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct DiagnosticSnapshot {
    pub errors: u64,
    pub warnings: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ActivitySnapshot {
    pub idle_ms: u64,
    pub typing: bool,
    pub buffer_switches_10s: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct EditorEvent {
    pub kind: String,
    #[serde(default)]
    pub buffer: Option<i64>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage {
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
pub enum Behavior {
    Idle,
    Focus,
    Inspect,
    Sleep,
    Hide,
    Curious,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Target {
    QuietCorner,
    CursorArea,
    ScreenEdge,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Locomotion {
    Auto,
    Walk,
    Run,
    Vanish,
    None,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Mood {
    Calm,
    Focused,
    Curious,
    Concerned,
    Sleepy,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct BehaviorIntent {
    pub behavior: Behavior,
    pub target: Target,
    pub locomotion: Locomotion,
    pub mood: Mood,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub emote: Option<&'static str>,
    pub duration_ms: u64,
}
