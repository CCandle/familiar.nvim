use crate::protocol::{
    Behavior, BehaviorIntent, BrainConfig, EditorSnapshot, Locomotion, Mood, Target,
};
use crate::provider::{PolicyRequest, ProviderEngine, build_prompt};
use crate::world::World;
use serde_json::Value;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};

pub trait Brain {
    fn decide(&mut self, world: &World) -> BehaviorIntent;
}

#[derive(Default)]
pub struct RuleBrain;

impl Brain for RuleBrain {
    fn decide(&mut self, world: &World) -> BehaviorIntent {
        let Some(snapshot) = world.snapshot.as_ref() else {
            return intent_for(AiBehavior::Hide);
        };

        if snapshot.viewport.width < 48 || snapshot.viewport.height < 12 {
            return intent_for(AiBehavior::Hide);
        }

        if snapshot.activity.idle_ms >= 120_000 {
            return intent_for(AiBehavior::Sleep);
        }

        if snapshot.diagnostics.errors > 0 {
            return intent_for(AiBehavior::Inspect);
        }

        let just_switched_buffer = world
            .last_event
            .as_ref()
            .is_some_and(|event| event.kind == "buffer_enter");

        if snapshot.activity.buffer_switches_10s >= 3
            || (just_switched_buffer && snapshot.activity.buffer_switches_10s >= 2)
        {
            return intent_for(AiBehavior::Curious);
        }

        if snapshot.activity.typing || snapshot.mode.starts_with('i') {
            return intent_for(AiBehavior::Focus);
        }

        intent_for(AiBehavior::Idle)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AiBehavior {
    Idle,
    Focus,
    Inspect,
    Curious,
    Sleep,
    Hide,
}

impl AiBehavior {
    fn name(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Focus => "focus",
            Self::Inspect => "inspect",
            Self::Curious => "curious",
            Self::Sleep => "sleep",
            Self::Hide => "hide",
        }
    }
}

fn probe_behaviors() -> Vec<AiBehavior> {
    vec![
        AiBehavior::Idle,
        AiBehavior::Focus,
        AiBehavior::Inspect,
        AiBehavior::Curious,
        AiBehavior::Sleep,
    ]
}

fn intent_for(choice: AiBehavior) -> BehaviorIntent {
    match choice {
        AiBehavior::Hide => BehaviorIntent {
            behavior: Behavior::Hide,
            target: Target::ScreenEdge,
            locomotion: Locomotion::Vanish,
            mood: Mood::Calm,
            emote: None,
            duration_ms: 5_000,
        },
        AiBehavior::Sleep => BehaviorIntent {
            behavior: Behavior::Sleep,
            target: Target::QuietCorner,
            locomotion: Locomotion::Walk,
            mood: Mood::Sleepy,
            emote: Some("sleep"),
            duration_ms: 30_000,
        },
        AiBehavior::Inspect => BehaviorIntent {
            behavior: Behavior::Inspect,
            target: Target::CursorArea,
            locomotion: Locomotion::Walk,
            mood: Mood::Concerned,
            emote: Some("question"),
            duration_ms: 7_000,
        },
        AiBehavior::Curious => BehaviorIntent {
            behavior: Behavior::Curious,
            target: Target::QuietCorner,
            locomotion: Locomotion::Run,
            mood: Mood::Curious,
            emote: Some("question"),
            duration_ms: 6_000,
        },
        AiBehavior::Focus => BehaviorIntent {
            behavior: Behavior::Focus,
            target: Target::QuietCorner,
            locomotion: Locomotion::None,
            mood: Mood::Focused,
            emote: None,
            duration_ms: 8_000,
        },
        AiBehavior::Idle => BehaviorIntent {
            behavior: Behavior::Idle,
            target: Target::QuietCorner,
            locomotion: Locomotion::Auto,
            mood: Mood::Calm,
            emote: None,
            duration_ms: 10_000,
        },
    }
}

fn behavior_name(behavior: &Behavior) -> &'static str {
    match behavior {
        Behavior::Idle => "idle",
        Behavior::Focus => "focus",
        Behavior::Inspect => "inspect",
        Behavior::Sleep => "sleep",
        Behavior::Hide => "hide",
        Behavior::Curious => "curious",
    }
}

fn allowed_behaviors(world: &World) -> Vec<AiBehavior> {
    let Some(snapshot) = world.snapshot.as_ref() else {
        return vec![AiBehavior::Hide];
    };

    if snapshot.viewport.width < 48 || snapshot.viewport.height < 12 {
        return vec![AiBehavior::Hide];
    }
    if snapshot.activity.typing || snapshot.mode.starts_with('i') || snapshot.mode.starts_with('R') {
        return vec![AiBehavior::Focus];
    }
    if snapshot.diagnostics.errors > 0 {
        return vec![AiBehavior::Inspect, AiBehavior::Focus, AiBehavior::Curious];
    }
    if snapshot.activity.idle_ms >= 120_000 {
        return vec![AiBehavior::Sleep, AiBehavior::Idle];
    }

    let first = snapshot.mode.chars().next().unwrap_or('n');
    if matches!(first, 'c' | 't' | 'v' | 'V') {
        return vec![AiBehavior::Idle, AiBehavior::Focus];
    }

    let mut allowed = vec![AiBehavior::Idle, AiBehavior::Curious, AiBehavior::Focus];
    if snapshot.diagnostics.warnings > 0 {
        allowed.push(AiBehavior::Inspect);
    }
    allowed
}

fn semantic_key(world: &World) -> u64 {
    let mut hasher = DefaultHasher::new();
    let Some(snapshot) = world.snapshot.as_ref() else {
        return hasher.finish();
    };

    snapshot.mode.hash(&mut hasher);
    snapshot.buffer.id.hash(&mut hasher);
    snapshot.buffer.filetype.hash(&mut hasher);
    snapshot.buffer.modified.hash(&mut hasher);
    snapshot.diagnostics.errors.hash(&mut hasher);
    snapshot.diagnostics.warnings.hash(&mut hasher);
    snapshot.activity.typing.hash(&mut hasher);
    snapshot.context.current_line.hash(&mut hasher);
    snapshot.context.before.hash(&mut hasher);
    snapshot.context.after.hash(&mut hasher);
    hasher.finish()
}

fn match_choice(candidate: &str, allowed: &[AiBehavior]) -> Option<AiBehavior> {
    allowed
        .iter()
        .copied()
        .find(|choice| choice.name().eq_ignore_ascii_case(candidate.trim()))
}

fn parse_choice(raw: &str, allowed: &[AiBehavior]) -> Result<AiBehavior, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err("model returned an empty behavior".into());
    }

    if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
        if let Some(candidate) = value.as_str() {
            if let Some(choice) = match_choice(candidate, allowed) {
                return Ok(choice);
            }
        }
        if let Some(candidate) = value.get("behavior").and_then(Value::as_str) {
            if let Some(choice) = match_choice(candidate, allowed) {
                return Ok(choice);
            }
            return Err(format!("model returned forbidden behavior: {candidate:?}"));
        }
    }

    let candidate = trimmed.trim_matches(|ch: char| {
        matches!(
            ch,
            '`' | '\'' | '"' | '.' | ':' | ';' | ',' | ' ' | '\t' | '\r' | '\n'
        )
    });
    if !candidate
        .chars()
        .all(|ch| ch.is_ascii_alphabetic() || ch == '_')
    {
        return Err(format!("model returned non-label output: {raw:?}"));
    }

    match_choice(candidate, allowed)
        .ok_or_else(|| format!("model returned no allowed behavior: {raw:?}"))
}

fn major_event(world: &World) -> bool {
    world.last_event.as_ref().is_some_and(|event| {
        matches!(
            event.kind.as_str(),
            "buffer_enter" | "bufwritepost" | "diagnosticchanged"
        )
    })
}

struct AiJob {
    prompt: String,
    allowed: Vec<AiBehavior>,
    semantic_key: u64,
    probe_id: Option<u64>,
}

struct AiReply {
    result: Result<AiBehavior, String>,
    latency_ms: u64,
    semantic_key: u64,
    probe_id: Option<u64>,
}

pub struct BrainProbeOutcome {
    pub ok: bool,
    pub choice: Option<&'static str>,
    pub latency_ms: Option<u64>,
    pub error: Option<String>,
}

struct AiDirector {
    config: BrainConfig,
    sender: Sender<AiJob>,
    receiver: Receiver<AiReply>,
    in_flight: bool,
    last_query: Option<Instant>,
    last_event_generation: u64,
    cached: Option<(AiBehavior, Instant, u64)>,
    last_error: Option<String>,
    backoff_until: Option<Instant>,
    last_latency_ms: Option<u64>,
    last_choice: Option<&'static str>,
    consecutive_failures: u32,
    total_requests: u64,
    total_successes: u64,
}

impl AiDirector {
    fn new(config: BrainConfig) -> Result<Self, String> {
        let worker_config = config.clone();
        let (job_tx, job_rx) = mpsc::channel::<AiJob>();
        let (reply_tx, reply_rx) = mpsc::channel::<AiReply>();

        thread::Builder::new()
            .name("familiar-brain".into())
            .spawn(move || {
                let mut provider = ProviderEngine::from_config(&worker_config);
                for job in job_rx {
                    let started = Instant::now();
                    let result = match &mut provider {
                        Ok(provider) => provider
                            .query(&job.prompt)
                            .and_then(|raw| parse_choice(&raw, &job.allowed)),
                        Err(error) => Err(error.clone()),
                    };
                    let latency_ms = started.elapsed().as_millis().min(u64::MAX as u128) as u64;
                    if reply_tx
                        .send(AiReply {
                            result,
                            latency_ms,
                            semantic_key: job.semantic_key,
                            probe_id: job.probe_id,
                        })
                        .is_err()
                    {
                        break;
                    }
                }
            })
            .map_err(|error| format!("failed to start brain worker: {error}"))?;

        Ok(Self {
            config,
            sender: job_tx,
            receiver: reply_rx,
            in_flight: false,
            last_query: None,
            last_event_generation: 0,
            cached: None,
            last_error: None,
            backoff_until: None,
            last_latency_ms: None,
            last_choice: None,
            consecutive_failures: 0,
            total_requests: 0,
            total_successes: 0,
        })
    }

    fn failure_backoff(&self) -> Duration {
        let exponent = self.consecutive_failures.saturating_sub(1).min(5);
        Duration::from_millis((2_000_u64.saturating_mul(1_u64 << exponent)).min(60_000))
    }

    fn record_failure(&mut self, error: String) {
        self.consecutive_failures = self.consecutive_failures.saturating_add(1);
        self.backoff_until = Some(Instant::now() + self.failure_backoff());
        eprintln!("familiar-core: AI provider: {error}");
        self.last_error = Some(error);
    }

    fn record_success(&mut self, choice: AiBehavior, latency_ms: u64) {
        self.last_latency_ms = Some(latency_ms);
        self.last_choice = Some(choice.name());
        self.last_error = None;
        self.backoff_until = None;
        self.consecutive_failures = 0;
        self.total_successes = self.total_successes.saturating_add(1);
    }

    fn poll(&mut self) {
        loop {
            match self.receiver.try_recv() {
                Ok(reply) => {
                    self.in_flight = false;
                    self.last_latency_ms = Some(reply.latency_ms);

                    // A probe reply visible here is necessarily late/orphaned:
                    // ordinary probes consume their own reply synchronously. Clear the
                    // worker busy state, but preserve the earlier timeout/failure signal.
                    if reply.probe_id.is_some() {
                        continue;
                    }

                    match reply.result {
                        Ok(choice) => {
                            self.record_success(choice, reply.latency_ms);
                            self.cached = Some((
                                choice,
                                Instant::now() + Duration::from_millis(self.config.choice_ttl_ms),
                                reply.semantic_key,
                            ));
                        }
                        Err(error) => self.record_failure(error),
                    }
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    self.in_flight = false;
                    self.record_failure("brain worker disconnected".into());
                    break;
                }
            }
        }

        if self
            .cached
            .as_ref()
            .is_some_and(|(_, expires, _)| Instant::now() >= *expires)
        {
            self.cached = None;
        }
    }

    fn maybe_schedule(&mut self, world: &World, previous: &str) {
        if self.in_flight {
            return;
        }
        let Some(snapshot) = world.snapshot.as_ref() else {
            return;
        };
        if snapshot.activity.typing {
            return;
        }

        let now = Instant::now();
        if self.backoff_until.is_some_and(|until| now < until) {
            return;
        }

        let allowed = allowed_behaviors(world);
        if allowed.len() <= 1 {
            return;
        }

        let since_last = self.last_query.map(|last| now.duration_since(last));
        let periodic_due = since_last
            .map(|elapsed| elapsed >= Duration::from_millis(self.config.interval_ms))
            .unwrap_or(true);
        let new_event = world.event_generation != self.last_event_generation;
        let event_due = new_event
            && major_event(world)
            && since_last
                .map(|elapsed| {
                    elapsed >= Duration::from_millis(self.config.event_min_interval_ms)
                })
                .unwrap_or(true);

        if !periodic_due && !event_due {
            return;
        }

        let names: Vec<&'static str> = allowed.iter().map(|choice| choice.name()).collect();
        let prompt = build_prompt(PolicyRequest {
            snapshot,
            allowed: &names,
            previous,
        });
        let semantic_key = semantic_key(world);
        if self
            .sender
            .send(AiJob {
                prompt,
                allowed,
                semantic_key,
                probe_id: None,
            })
            .is_ok()
        {
            self.in_flight = true;
            self.last_query = Some(now);
            self.last_event_generation = world.event_generation;
            self.total_requests = self.total_requests.saturating_add(1);
        } else {
            self.last_error = Some("brain worker queue is unavailable".into());
        }
    }

    fn probe(&mut self, id: u64, snapshot: &EditorSnapshot, previous: &str) -> BrainProbeOutcome {
        self.poll();
        if self.in_flight {
            return BrainProbeOutcome {
                ok: false,
                choice: None,
                latency_ms: None,
                error: Some("provider is busy with a normal decision; retry shortly".into()),
            };
        }

        let allowed = probe_behaviors();
        let names: Vec<&'static str> = allowed.iter().map(|choice| choice.name()).collect();
        let prompt = build_prompt(PolicyRequest {
            snapshot,
            allowed: &names,
            previous,
        });

        if self
            .sender
            .send(AiJob {
                prompt,
                allowed,
                semantic_key: 0,
                probe_id: Some(id),
            })
            .is_err()
        {
            return BrainProbeOutcome {
                ok: false,
                choice: None,
                latency_ms: None,
                error: Some("brain worker queue is unavailable".into()),
            };
        }

        self.in_flight = true;
        self.total_requests = self.total_requests.saturating_add(1);
        let wait = Duration::from_millis(self.config.timeout_ms.saturating_add(1_500));
        match self.receiver.recv_timeout(wait) {
            Ok(reply) => {
                self.in_flight = false;
                self.last_latency_ms = Some(reply.latency_ms);
                if reply.probe_id != Some(id) {
                    let error = "brain worker returned an unexpected probe response".to_string();
                    self.record_failure(error.clone());
                    return BrainProbeOutcome {
                        ok: false,
                        choice: None,
                        latency_ms: Some(reply.latency_ms),
                        error: Some(error),
                    };
                }

                match reply.result {
                    Ok(choice) => {
                        self.record_success(choice, reply.latency_ms);
                        BrainProbeOutcome {
                            ok: true,
                            choice: Some(choice.name()),
                            latency_ms: Some(reply.latency_ms),
                            error: None,
                        }
                    }
                    Err(error) => {
                        self.record_failure(error.clone());
                        BrainProbeOutcome {
                            ok: false,
                            choice: None,
                            latency_ms: Some(reply.latency_ms),
                            error: Some(error),
                        }
                    }
                }
            }
            Err(RecvTimeoutError::Timeout) => {
                // Keep `in_flight` true: the provider worker may still be executing.
                // A future poll drains the late probe reply and only then clears busy.
                let error = format!("brain probe timed out after {} ms", wait.as_millis());
                self.record_failure(error.clone());
                BrainProbeOutcome {
                    ok: false,
                    choice: None,
                    latency_ms: None,
                    error: Some(error),
                }
            }
            Err(RecvTimeoutError::Disconnected) => {
                self.in_flight = false;
                let error = "brain worker disconnected during probe".to_string();
                self.record_failure(error.clone());
                BrainProbeOutcome {
                    ok: false,
                    choice: None,
                    latency_ms: None,
                    error: Some(error),
                }
            }
        }
    }

    fn choice(&self, world: &World) -> Option<AiBehavior> {
        let (choice, expires, source_key) = self.cached?;
        if Instant::now() >= expires || semantic_key(world) != source_key {
            return None;
        }
        allowed_behaviors(world).contains(&choice).then_some(choice)
    }

    fn state(&self) -> &'static str {
        if self.last_error.is_some() && self.cached.is_some() {
            "degraded"
        } else if self.last_error.is_some() {
            "error"
        } else if self.in_flight {
            "querying"
        } else if self.cached.is_some() {
            "ready"
        } else {
            "idle"
        }
    }
}

pub struct BrainStatus {
    pub enabled: bool,
    pub provider: String,
    pub state: &'static str,
    pub error: Option<String>,
    pub last_latency_ms: Option<u64>,
    pub last_choice: Option<&'static str>,
    pub consecutive_failures: u32,
    pub total_requests: u64,
    pub total_successes: u64,
}

pub struct BrainController {
    rule: RuleBrain,
    ai: Option<AiDirector>,
    provider: String,
    enabled: bool,
    last_behavior: String,
    setup_error: Option<String>,
}

impl Default for BrainController {
    fn default() -> Self {
        Self {
            rule: RuleBrain,
            ai: None,
            provider: "rule".into(),
            enabled: false,
            last_behavior: "idle".into(),
            setup_error: None,
        }
    }
}

impl BrainController {
    pub fn configure(&mut self, config: BrainConfig) {
        self.provider = config.provider.clone();
        self.enabled = config.enabled && config.provider != "rule";
        self.setup_error = None;
        self.ai = None;

        if self.enabled {
            match AiDirector::new(config) {
                Ok(ai) => self.ai = Some(ai),
                Err(error) => {
                    eprintln!("familiar-core: AI setup: {error}");
                    self.setup_error = Some(error);
                }
            }
        }
    }

    pub fn probe(&mut self, id: u64, snapshot: &EditorSnapshot) -> BrainProbeOutcome {
        if !self.enabled {
            return BrainProbeOutcome {
                ok: false,
                choice: None,
                latency_ms: None,
                error: Some("AI brain is disabled".into()),
            };
        }
        let Some(ai) = &mut self.ai else {
            return BrainProbeOutcome {
                ok: false,
                choice: None,
                latency_ms: None,
                error: Some(
                    self.setup_error
                        .clone()
                        .unwrap_or_else(|| "AI provider is unavailable".into()),
                ),
            };
        };
        ai.probe(id, snapshot, &self.last_behavior)
    }

    pub fn status(&mut self) -> BrainStatus {
        if let Some(ai) = &mut self.ai {
            ai.poll();
            return BrainStatus {
                enabled: self.enabled,
                provider: self.provider.clone(),
                state: ai.state(),
                error: ai.last_error.clone(),
                last_latency_ms: ai.last_latency_ms,
                last_choice: ai.last_choice,
                consecutive_failures: ai.consecutive_failures,
                total_requests: ai.total_requests,
                total_successes: ai.total_successes,
            };
        }
        BrainStatus {
            enabled: self.enabled,
            provider: self.provider.clone(),
            state: if self.setup_error.is_some() {
                "error"
            } else if self.enabled {
                "unavailable"
            } else {
                "disabled"
            },
            error: self.setup_error.clone(),
            last_latency_ms: None,
            last_choice: None,
            consecutive_failures: u32::from(self.setup_error.is_some()),
            total_requests: 0,
            total_successes: 0,
        }
    }
}

impl Brain for BrainController {
    fn decide(&mut self, world: &World) -> BehaviorIntent {
        let rule_intent = self.rule.decide(world);
        if rule_intent.behavior == Behavior::Hide {
            self.last_behavior = "hide".into();
            return rule_intent;
        }

        let Some(ai) = &mut self.ai else {
            self.last_behavior = behavior_name(&rule_intent.behavior).into();
            return rule_intent;
        };

        ai.poll();
        ai.maybe_schedule(world, &self.last_behavior);
        if let Some(choice) = ai.choice(world) {
            let intent = intent_for(choice);
            self.last_behavior = choice.name().into();
            return intent;
        }

        self.last_behavior = behavior_name(&rule_intent.behavior).into();
        rule_intent
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{
        ActivitySnapshot, BufferSnapshot, DiagnosticSnapshot, EditorSnapshot, TextContextSnapshot,
        ViewportSnapshot,
    };

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
            context: TextContextSnapshot::default(),
        }
    }

    fn world(snapshot: EditorSnapshot) -> World {
        World {
            snapshot: Some(snapshot),
            last_event: None,
            event_generation: 0,
        }
    }

    #[test]
    fn hides_in_small_windows() {
        let mut snapshot = snapshot();
        snapshot.viewport.width = 30;
        assert_eq!(RuleBrain.decide(&world(snapshot)).behavior, Behavior::Hide);
    }

    #[test]
    fn sustained_idle_prefers_sleep() {
        let mut snapshot = snapshot();
        snapshot.activity.idle_ms = 130_000;
        assert_eq!(RuleBrain.decide(&world(snapshot)).behavior, Behavior::Sleep);
    }

    #[test]
    fn diagnostics_take_attention_before_focus() {
        let mut snapshot = snapshot();
        snapshot.activity.typing = true;
        snapshot.diagnostics.errors = 1;
        assert_eq!(RuleBrain.decide(&world(snapshot)).behavior, Behavior::Inspect);
    }

    #[test]
    fn typing_prefers_focus_without_more_important_event() {
        let mut snapshot = snapshot();
        snapshot.activity.typing = true;
        assert_eq!(RuleBrain.decide(&world(snapshot)).behavior, Behavior::Focus);
    }

    #[test]
    fn parser_accepts_labels_and_strict_json_only() {
        let allowed = [AiBehavior::Idle, AiBehavior::Curious];
        assert_eq!(parse_choice("curious", &allowed).unwrap(), AiBehavior::Curious);
        assert_eq!(parse_choice("`idle`", &allowed).unwrap(), AiBehavior::Idle);
        assert_eq!(
            parse_choice("{\"behavior\":\"idle\"}", &allowed).unwrap(),
            AiBehavior::Idle
        );
        assert!(parse_choice("inspect", &allowed).is_err());
        assert!(parse_choice("I think curious is best", &allowed).is_err());
        assert!(parse_choice("not curious; idle", &allowed).is_err());
    }

    #[test]
    fn typing_collapses_ai_action_space() {
        let mut snapshot = snapshot();
        snapshot.activity.typing = true;
        assert_eq!(allowed_behaviors(&world(snapshot)), vec![AiBehavior::Focus]);
    }

    #[test]
    fn semantic_key_changes_with_local_context() {
        let first = world(snapshot());
        let mut second_snapshot = snapshot();
        second_snapshot.context.current_line = "different line".into();
        let second = world(second_snapshot);
        assert_ne!(semantic_key(&first), semantic_key(&second));
    }

    #[test]
    fn probe_action_space_never_contains_hide() {
        assert!(!probe_behaviors().contains(&AiBehavior::Hide));
    }
}
