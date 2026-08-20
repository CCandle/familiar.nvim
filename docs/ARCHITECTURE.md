# Architecture

## Product definition

`familiar.nvim` is a terminal-native animated familiar for Neovim. It should feel present in the editor without becoming another panel, notification source, or chat agent.

The system has four cooperating layers:

1. **Presentation** — deterministic time-domain motion, expression, effects, and rendering.
2. **World** — editor/workspace state, spatial occupancy, semantic events, and memory.
3. **Behavior** — deterministic state machine, mode policy, cooldowns, personality state, and safe action selection.
4. **Brain** — optional low-frequency policy provider. `RuleBrain` is always available; enabled AI providers may choose among already-safe semantic actions.

No model controls animation frames, raw coordinates, arbitrary commands, or free-form visible glyph strings.

## Architectural boundary

### Lua frontend

Lua owns everything inherently Neovim-specific:

- autocmds and lifecycle;
- buffers, windows, diagnostics and editor mode;
- bounded telemetry extraction;
- spatial safety queries;
- presentation scheduling and interpolation;
- floating render surfaces, extmarks and highlight groups;
- child-process lifecycle and IPC.

The Lua layer should remain lightweight even though presentation is local: active high-refresh work is limited to cheap position/effect updates, while semantic policy and expensive analysis stay off the render path.

### Rust sidecar

`familiar-core` is a child process attached to one Neovim instance. It owns or will own:

- normalized world state;
- deterministic RuleBrain policy;
- bounded personality/memory state;
- optional AI BrainProvider implementations;
- semantic intent validation.

The sidecar communicates over newline-delimited JSON on stdin/stdout. Traffic is low-volume and semantic, so a binary protocol is not justified yet.

### Lifecycle

The sidecar is not a macOS LaunchAgent and not a permanent daemon.

```text
Neovim plugin loads
  -> deterministic Lua presentation is immediately available
  -> attempt to start familiar-core
  -> handshake
  -> stream bounded semantic snapshots/events
  -> receive behavior intents

Neovim exits / plugin stops
  -> send shutdown
  -> close channel
  -> terminate child if needed
  -> all sidecar/model memory is released
```

Failure of the sidecar is non-fatal. The Lua fallback remains functional.

## Presentation engine

Presentation is explicitly split from behavior policy.

```text
semantic intent / mode / safe placement
              |
              v
       Presentation Planner
        /       |        \
       v        v         v
  Motion     Expression   Effects
       \        |         /
              v
           Renderer
```

### Time-domain motion

Spatial movement is defined by origin, destination, start time, deadline, locomotion class, and easing.

The actor's logical position is sampled from real elapsed time. Ordinary relocation defaults to 250 ms rather than a fixed number of cells per tick. Distance changes the visual locomotion class (`walk`, `run`, `dash`, or `warp`) instead of making movement arbitrarily long.

In-flight target changes replace stale destinations. The existing burst deadline is preserved when practical, with only a bounded late-retarget extension.

See [`ANIMATION_ENGINE.md`](ANIMATION_ENGINE.md) and ADR 0005.

### Active refresh rate

The default active motion profile targets 60 FPS. A 120 FPS high-refresh profile and 30 FPS economy profile are available.

This is not a permanent renderer heartbeat. When no spatial motion/trail is active, there is no 60/120 Hz actor redraw loop. Blink, glance, stretch, save reactions, and other expressions are discrete scheduled keyframes.

### Expression

Skin animations use explicit millisecond keyframes rather than repeated frames used as a clock. The runtime may interrupt ordinary ambient actions, while short visibility transitions can be protected long enough to remain visually coherent.

### Effects

Trail/effects are separate from the actor body. The default trail is sparse motion residue, not duplicated whole-character smear.

## Rendering model

Rendering is skin-dependent presentation. The engine does not assume a species or one visual representation.

### Glyph actor

The default direction is a small **1–3 terminal-row glyph actor**.

A glyph frame contains rows of styled text segments with semantic color roles such as `outline`, `face`, `effect`, `success`, `alert`, or `muted`.

This representation spends terminal cells on high-information features:

- face/eyes/mouth;
- ears, hair, horns, or headwear when useful;
- hand gestures;
- posture;
- tiny effects and motion residue.

Rows are validated using terminal display width, not UTF-8 byte length. Short frames are padded into a stable transparent render surface.

### Indexed pixel skin

The earlier pixel renderer remains supported. Pixel sprites are indexed logical-pixel matrices packed vertically with Unicode half blocks. The original fox uses this path as a compatibility and regression target, but it is not the default product direction.

### Shared actor surface

Both render kinds use a borderless, non-focusable, mouse-transparent floating window as an internal render surface. Edited buffers, undo history, and file contents are never modified.

### Channel separation

Actor **content**, **position**, and **effects** have independent caches.

A position-only motion tick should usually call only `nvim_win_set_config()`. It should not rebuild frame strings or extmarks. If the logical position still rounds to the same terminal cell, the update is skipped entirely.

Trail particles/residues use a tiny reusable pool of one-cell floats rather than opening and closing windows on every effect sample.

## Spatial model

The familiar lives in **screen space**, not document coordinates.

A safe-placement pass currently uses:

- window width/height;
- visible buffer lines and their display width;
- inline, end-of-line, right-aligned, and fixed-column virtual text;
- skin dimensions;
- configured margin.

The current implementation prefers empty space to the right of visible text and can produce multiple safe candidates. Relocation first performs a route preflight over the quantized screen path; an unsafe route uses the vanish/appear transition instead. The renderer then independently validates the **actual quantized cell immediately before each draw**. That final-frame check reuses cached occupancy and is therefore cheap at 60/120 FPS. Text, diagnostic, scroll, and resize events invalidate the cached occupancy, and unsafe trail cells are suppressed. Future occupancy can include folds, other floats, UI-reserved areas, and selection-aware zones.

### Stickiness

Safe current placement is intentionally sticky.

A newly computed location does not automatically trigger movement. Candidate relocation is gated by semantic benefit and penalties for travel distance, recent movement, already being in motion, and current editor-mode policy.

Safety overrides stickiness. If the current location becomes unsafe, the familiar may relocate, compact, peek, or hide.

This makes "knowing when not to move" a first-class UX behavior rather than an incidental optimization.

## Mode-aware behavior

Editor mode changes behavior budgets as well as visible pose.

- **Normal:** richest ambient behavior and lowest relocation penalty.
- **Insert:** focused, quiet, movement strongly discouraged while safe.
- **Visual/Select:** attentive to the selection, ambient novelty suppressed.
- **Operator-pending:** anticipatory/focused, movement discouraged during the pending command.
- **Replace:** alert/focused, movement discouraged.
- **Command-line/prompt:** compact/frozen when safe.
- **Terminal:** quiet/background policy; current render eligibility still follows normal-window constraints.

This policy is independent of skin assets. A skin decides how `focus` or `visual` looks; the runtime decides when those semantics apply.

## World model

The world is multi-timescale.

### Fast presentation state

Updated without model inference:

- current actor position and motion plan;
- viewport geometry needed for safety;
- expression sequence;
- effect/trail lifetime;
- current editor mode family.

### Semantic editor state

Aggregated from events:

- current buffer and filetype;
- buffer switches;
- typing/idle periods;
- save activity;
- diagnostics and trends;
- build/test results when integrations exist;
- Markdown/LaTeX/code structural context;
- workspace/open-buffer summaries when useful.

### Brain tick

An enabled AI provider runs only on meaningful semantic events or a low-frequency policy tick. It never runs per keypress, motion tick, or animation frame.

## Text work is first-class

The world model must not assume productive work means compiling code.

For Markdown, useful events include heading changes, long writing bursts, list editing, note/link navigation, and buffer/note switches.

For LaTeX, useful events include section/subsection changes, environment entry, equations, figures, citations, compilation, and forward-search workflow.

A sustained writing session should generally make the familiar **quieter**, not more active.

## AI boundary

The current AI architecture is provider-based and opt-in:

```text
RuleBrain (mandatory, default)
optional local llama.cpp/GGUF
optional Ollama
optional OpenAI-compatible endpoint
```

The deterministic layer first computes an eligible action set using safety, nuisance limits, cooldowns, mode policy, and presentation state. An AI provider may choose only among those actions.

A provider receives a compact structured snapshot and returns a validated semantic behavior choice. It cannot invent visible skin strings, arbitrary screen coordinates, commands, or executable behavior.

See [`BRAIN.md`](BRAIN.md).

## Performance budget

The familiar is decoration, so it receives a strict budget:

- active spatial motion defaults to 60 FPS; 120 FPS is optional, 30 FPS is economy;
- high refresh rate does **not** imply high-frequency full content redraw;
- terminal-cell-quantized duplicate position updates are skipped;
- final-frame spatial safety uses cached occupancy rather than rescanning the buffer each motion tick;
- idle expression is event/keyframe driven, not a permanent high-FPS loop;
- hidden state performs only low-frequency semantic tracking;
- no AI inference during high-rate typing unless a major event explicitly warrants it;
- sidecar idle CPU should approach zero;
- no persistent process after Neovim exits;
- optional model memory/cost must be isolated from the core no-AI experience.

Performance claims remain measurement targets until repeatedly benchmarked in real terminal environments.
