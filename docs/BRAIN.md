# Brain design

## Role

The brain is a low-frequency **behavior director**. It does not animate frames, draw glyphs, choose coordinates, invoke editor commands, or replace the deterministic runtime.

The deterministic `RuleBrain` remains mandatory. Optional AI providers add contextual judgment and variety when several already-safe actions are reasonable.

Most of the familiar's liveliness comes from the world model, state machine, personality state, cooldowns, motion utility, action continuity, and presentation engine. The language model is not the personality itself.

## Provider model

AI is off by default. The long-term user-facing abstraction is a provider rather than one required local model:

```text
BrainProvider
  |- rule               always available
  |- local_llama        embedded llama.cpp + downloaded GGUF
  |- ollama             optional local HTTP service
  |- openai_compatible  remote/local OpenAI-compatible endpoint
  `- custom             user-supplied adapter
```

Examples of services behind `openai_compatible` can include hosted or self-hosted models. The familiar core must not special-case one vendor's behavior policy.

A future configuration shape may look like:

```lua
brain = {
  enabled = false,
  provider = "rule",
}
```

or:

```lua
brain = {
  enabled = true,
  provider = "ollama",
  model = "...",
}
```

or:

```lua
brain = {
  enabled = true,
  provider = "openai_compatible",
  endpoint = "...",
  model = "...",
  api_key = function()
    return os.getenv("FAMILIAR_API_KEY")
  end,
}
```

The exact public schema is deferred until at least two providers share a working contract.

## Local llama.cpp backend

The intended fully local backend is linked into `familiar-core` rather than requiring Ollama or a permanent daemon:

```text
Neovim starts familiar-core
  -> deterministic systems are immediately available
  -> local model is lazily initialized only if enabled
  -> llama.cpp runs inside the sidecar process

Neovim exits
  -> familiar-core exits
  -> model memory is released
```

The plugin itself does not bundle model weights in its Git checkout.

When a user opts into the local backend, a pinned model can be downloaded into a persistent data directory such as:

```text
stdpath("data")/familiar/models/<model-id>/<revision>/model.gguf
```

Temporary partial downloads belong under `stdpath("cache")/familiar/`.

A model manifest should pin at least:

```text
model id
repository/provider
revision
filename
expected bytes
SHA-256
license
prompt/template family
```

Download flow should be explicit and atomic:

```text
user enables local AI
  -> show model name / size / license
  -> user confirms download
  -> download to .part
  -> verify checksum
  -> atomic rename
  -> model becomes available
```

If the model is absent, damaged, unsupported, or fails inference, the session continues on `RuleBrain`.

## Model size

No parameter count is a product requirement.

A 100M-class instruct model is currently an acceptable upper-bound experiment for a tiny local policy, but the task should be benchmarked downward as aggressively as possible. The brain only needs to interpret a compact editor snapshot and choose among a small action set; it is not a general chat assistant.

A smaller specialized classifier/policy model may ultimately beat a general LLM on latency, memory, and predictability. The provider abstraction deliberately keeps that option open.

The smallest backend that passes familiar-specific behavior tests wins.

## Input

Providers receive a compact normalized semantic snapshot, not a dump of raw Neovim events or an entire source file.

Conceptually:

```json
{
  "session": {
    "minutes": 43,
    "idle_ms": 3200
  },
  "activity": {
    "mode": "normal",
    "typing": "quiet",
    "buffer_switch_rate": "low",
    "diagnostic_trend": -2
  },
  "document": {
    "filetype": "tex",
    "local_context": "equation",
    "semantic_hint": "Control Architecture"
  },
  "familiar": {
    "energy": 0.42,
    "curiosity": 0.71,
    "stress": 0.18,
    "recent_actions": ["idle", "glance"]
  },
  "available_actions": ["idle", "focus", "inspect", "peek", "wander"]
}
```

Source context must be aggressively bounded and only collected when it can materially change a low-frequency decision. The provider should not see every keypress or every animation frame.

## Output

Output is strictly constrained to declared semantic IDs and small scalar values, for example:

```json
{
  "behavior": "inspect",
  "target": "current_context",
  "mood": "curious",
  "emote": "question"
}
```

The model cannot emit:

- visible free-form dialogue by default;
- arbitrary Unicode or skin data;
- raw screen coordinates;
- colors or animation frames;
- shell or editor commands;
- executable code;
- arbitrary file paths.

For llama.cpp, grammar/JSON-schema constrained decoding should be used when the chosen model/backend supports it. Remote providers are still validated against the same runtime schema.

## RuleBrain and safety envelope

AI never receives an unconstrained action space.

The deterministic layer decides which actions are currently eligible based on safety, nuisance limits, cooldowns, editor mode, visibility, and presentation state. A provider chooses only inside that set.

Example:

```text
allowed: idle, glance, peek, inspect
blocked: celebrate, sleep, relocate-over-selection
```

The provider may choose `peek`; it cannot override the blocked set.

This architecture makes weak or quirky tiny models useful without letting their mistakes become editor interference.

## Decision frequency

A model call is never tied to animation FPS.

Initial policy:

- meaningful semantic transitions may make a decision eligible;
- otherwise decisions occur at most on a slow tens-of-seconds cadence;
- sustained typing suppresses routine inference;
- Insert/Visual/command-line activity strongly suppresses novelty decisions;
- hidden/background familiar state suppresses inference;
- repeated equivalent world states reuse the current plan;
- cooldowns prevent remote API use from becoming noisy or expensive.

For many sessions, most behavior should come from deterministic state-machine logic with only occasional AI calls.

## Internal state

The companion can maintain bounded continuous traits such as:

```text
energy
curiosity
stress
confidence
focus
social
```

Editor events nudge these values and they decay over time. This provides continuity even when the AI backend is disabled or unavailable.

A small persistent profile may eventually store long-lived tendencies. No vector database or RAG service is required for the core experience.

## Provider security and privacy

Remote providers are explicitly opt-in.

API credentials must not be committed into the familiar repository or written into logs. Configuration should support environment variables or callbacks so secrets can remain in the user's existing secret-management workflow.

Before sending editor context to a remote provider, the eventual implementation must document exactly what fields can leave the machine and provide conservative defaults. Local RuleBrain and local llama.cpp operation remain available without network context disclosure.

## PetBench

Provider choice should be based on familiar behavior rather than generic chatbot benchmarks.

Scenarios should include:

- sustained Insert-mode writing: stay focused and non-disruptive;
- Visual selection: observe without relocating frivolously;
- repeated scrolling: avoid stale action plans;
- new diagnostics: inspecting may be useful;
- diagnostics resolved while typing continues: avoid noisy celebration;
- long idle: rest/sleep;
- new Markdown/LaTeX/code structure: occasional curiosity is reasonable;
- dense viewport: accept hide/peek instead of covering text;
- repeated equivalent state: preserve behavioral continuity;
- rapid mode changes: avoid animation thrashing;
- backend timeout or malformed output: deterministic fallback is immediate.

Metrics should include schema validity, contextual appropriateness, action diversity, continuity, nuisance rate, inference latency, resident memory, network cost, and energy impact.

Only after this benchmark exists should the project choose a default optional local model.
