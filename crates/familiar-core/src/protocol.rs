use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

pub const PROTOCOL_VERSION: u32 = 2;
pub const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

fn default_provider() -> String {
    "rule".into()
}
fn default_interval_ms() -> u64 {
    20_000
}
fn default_event_min_interval_ms() -> u64 {
    5_000
}
fn default_choice_ttl_ms() -> u64 {
    30_000
}
fn default_timeout_ms() -> u64 {
    8_000
}
fn default_max_tokens() -> u32 {
    8
}
fn default_temperature() -> f32 {
    0.15
}
fn default_n_ctx() -> u32 {
    2_048
}
fn default_n_threads() -> i32 {
    4
}
fn default_n_gpu_layers() -> u32 {
    99
}

#[derive(Clone, Deserialize)]
pub struct BrainConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default = "default_provider")]
    pub provider: String,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub endpoint: Option<String>,
    #[serde(default)]
    pub base_url: Option<String>,
    #[serde(default)]
    pub api_key: Option<String>,
    #[serde(default)]
    pub headers: Map<String, Value>,
    #[serde(default)]
    pub extra_body: Map<String, Value>,
    #[serde(default = "default_interval_ms")]
    pub interval_ms: u64,
    #[serde(default = "default_event_min_interval_ms")]
    pub event_min_interval_ms: u64,
    #[serde(default = "default_choice_ttl_ms")]
    pub choice_ttl_ms: u64,
    #[serde(default = "default_timeout_ms")]
    pub timeout_ms: u64,
    #[serde(default = "default_max_tokens")]
    pub max_tokens: u32,
    #[serde(default = "default_temperature")]
    pub temperature: f32,
    #[serde(default, rename = "local")]
    #[cfg_attr(not(feature = "local-llama"), allow(dead_code))]
    pub local_config: LocalBrainConfig,
}

impl Default for BrainConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            provider: default_provider(),
            model: None,
            endpoint: None,
            base_url: None,
            api_key: None,
            headers: Map::new(),
            extra_body: Map::new(),
            interval_ms: default_interval_ms(),
            event_min_interval_ms: default_event_min_interval_ms(),
            choice_ttl_ms: default_choice_ttl_ms(),
            timeout_ms: default_timeout_ms(),
            max_tokens: default_max_tokens(),
            temperature: default_temperature(),
            local_config: LocalBrainConfig::default(),
        }
    }
}

#[derive(Clone, Deserialize)]
#[cfg_attr(not(feature = "local-llama"), allow(dead_code))]
pub struct LocalBrainConfig {
    #[serde(default)]
    pub model_path: Option<String>,
    #[serde(default = "default_n_ctx")]
    pub n_ctx: u32,
    #[serde(default = "default_n_threads")]
    pub n_threads: i32,
    #[serde(default = "default_n_gpu_layers")]
    pub n_gpu_layers: u32,
}

impl Default for LocalBrainConfig {
    fn default() -> Self {
        Self {
            model_path: None,
            n_ctx: default_n_ctx(),
            n_threads: default_n_threads(),
            n_gpu_layers: default_n_gpu_layers(),
        }
    }
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    Hello {
        protocol: u32,
        client: String,
    },
    Configure {
        brain: BrainConfig,
    },
    Snapshot {
        seq: u64,
        snapshot: EditorSnapshot,
    },
    Event {
        seq: u64,
        event: EditorEvent,
    },
    BrainProbe {
        id: u64,
        snapshot: EditorSnapshot,
    },
    Ping {
        id: u64,
    },
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
    #[serde(default)]
    pub context: TextContextSnapshot,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[allow(dead_code)]
pub struct TextContextSnapshot {
    #[serde(default)]
    pub current_line: String,
    #[serde(default)]
    pub before: Vec<String>,
    #[serde(default)]
    pub after: Vec<String>,
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
        local_llama: bool,
    },
    Intent {
        seq: u64,
        intent: BehaviorIntent,
    },
    BrainStatus {
        enabled: bool,
        provider: String,
        state: &'static str,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        last_latency_ms: Option<u64>,
        #[serde(skip_serializing_if = "Option::is_none")]
        last_choice: Option<&'static str>,
        consecutive_failures: u32,
        total_requests: u64,
        total_successes: u64,
    },
    BrainProbeResult {
        id: u64,
        ok: bool,
        #[serde(skip_serializing_if = "Option::is_none")]
        choice: Option<&'static str>,
        #[serde(skip_serializing_if = "Option::is_none")]
        latency_ms: Option<u64>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<String>,
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
