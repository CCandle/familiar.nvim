# Tiny brain design

## Role

The model is a low-frequency **behavior director**. It does not animate frames, draw pixels, write dialogue, invoke editor commands, or replace the deterministic runtime.

The deterministic `RuleBrain` remains mandatory. AI is an optional policy layer that makes the familiar less mechanically predictable.

## Lifecycle

No Ollama or permanent daemon is required.

The intended production shape is:

```text
Neovim starts familiar-core
  -> Rust initializes deterministic systems immediately
  -> tiny model is loaded lazily when/if enabled
  -> behavior decisions run on semantic triggers / slow ticks

Neovim exits
  -> familiar-core exits
  -> model memory is released
```

If loading or inference fails, the session continues on `RuleBrain`.

## Rust abstraction

The inference backend should sit behind a small interface rather than leaking a particular runtime through the engine:

```rust
trait Brain {
    fn decide(&mut self, world: &WorldSnapshot, choices: &ActionSet) -> Decision;
}
```

Possible implementations:

- `RuleBrain` — always present;
- a llama.cpp/GGUF-backed implementation;
- a pure-Rust/Metal-capable implementation if it proves mature enough;
- test/fake brains for deterministic scenarios.

Backend selection is deferred until measurement.

## Input

The brain receives a compact normalized snapshot, not raw Neovim events. Conceptually:

```json
{
  "session": {
    "minutes": 43,
    "idle_ms": 3200
  },
  "activity": {
    "typing": "sustained",
    "buffer_switch_rate": "low",
    "diagnostic_trend": -2
  },
  "document": {
    "filetype": "tex",
    "section": "Control Architecture",
    "environment": "equation"
  },
  "pet": {
    "energy": 0.42,
    "curiosity": 0.71,
    "stress": 0.18
  },
  "recent_events": ["section_changed", "save"],
  "available_actions": ["idle", "focus", "inspect", "walk", "sleep"]
}
```

Actual schema will be smaller and versioned before inference lands.

## Output

The output is strictly constrained to declared IDs and numbers:

```json
{
  "behavior": "inspect",
  "target": "current_section",
  "locomotion": "walk",
  "mood": "curious",
  "emote": "question",
  "duration_ms": 12000
}
```

The model cannot emit:

- free-form visible text;
- arbitrary Unicode/emoji;
- colors or sprite data;
- file paths not already represented as IDs;
- shell/editor commands;
- executable behavior code.

The runtime validates every decision. Invalid output falls back to deterministic policy.

## Decision frequency

A model call is never tied to animation FPS.

Initial target policy:

- major semantic event: eligible for an immediate decision;
- otherwise: at most one slow decision every tens of seconds;
- sustained high-rate typing suppresses routine inference;
- hidden/background conditions suppress inference;
- repeated equivalent state should reuse the existing plan rather than ask again.

## Internal state

The companion may maintain continuous bounded traits such as:

```text
energy
curiosity
stress
confidence
focus
social
```

Editor events nudge these values; they also decay over time. The model sees state rather than receiving a hard-coded mapping such as `build_failed => sad`.

A very small persistent session/profile file may later capture long-lived tendencies, but no vector database or RAG system is required.

## Performance targets

These are acceptance targets, not yet measured claims:

- model class roughly 100M–400M parameters if behavior quality permits;
- quantized local weights;
- short context (hundreds of tokens);
- tiny structured output;
- sidecar idle CPU near zero;
- no inference on every keypress/frame;
- resident-memory target in the low hundreds of MB rather than multi-GB.

The smallest model that passes behavior tests wins.

## PetBench

Model choice should be based on familiar behavior rather than generic chatbot benchmarks. A small scenario suite should include cases such as:

- sustained writing: prefer calm/focus and avoid interruption;
- repeated buffer switching: curiosity/confusion is reasonable;
- new diagnostics: inspect may be useful;
- diagnostics resolved while typing continues: avoid noisy celebration;
- long idle: rest/sleep;
- new Markdown/LaTeX section: occasional exploration is reasonable;
- dense viewport: accept hide/peek instead of covering text;
- same state repeated: preserve behavioral continuity.

Metrics should include schema validity, contextual appropriateness, action diversity, continuity, nuisance rate, latency, RSS, and energy impact.

Only after this benchmark exists should the project choose between candidate tiny models/backends.
