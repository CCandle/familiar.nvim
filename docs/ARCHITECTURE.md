# Architecture

## Product definition

`familiar.nvim` is a terminal-native animated familiar for Neovim. It should feel present in the editor without becoming another panel, notification source, or chat agent.

The companion has three layers of behavior:

1. **Body** — deterministic animation and rendering.
2. **World** — editor/workspace state, spatial occupancy, memory, and semantic events.
3. **Brain** — a policy that selects declared behavior intents. The baseline policy is deterministic; a tiny local model may later bias/choose intents.

The model is never trusted with rendering, arbitrary commands, or free-form user-visible text.

## Architectural boundary

### Lua frontend

Lua owns everything that is inherently Neovim-specific:

- autocmds and lifecycle;
- buffers, windows, diagnostics and editor mode;
- bounded telemetry extraction;
- extmarks and highlight groups;
- conversion of render plans into Neovim draw operations;
- child-process lifecycle and IPC.

Lua should remain small. It should not host model inference, long-term memory, expensive workspace analysis, or complex behavior search.

### Rust sidecar

`familiar-core` is a child process attached to one Neovim instance. It owns:

- normalized world state;
- behavior intent selection;
- transition/spatial planning as those systems mature;
- avatar/personality policy validation;
- session memory;
- later, a tiny constrained model backend.

The sidecar communicates over newline-delimited JSON on stdin/stdout. JSONL is deliberately chosen for the early protocol because traffic is tiny, debugging is easy, and both sides can be inspected independently. A binary protocol is not justified until measurement says otherwise.

### Lifecycle

The sidecar is not installed as a macOS LaunchAgent and is not a permanent daemon.

```text
Neovim plugin loads
  -> attempt to start familiar-core
  -> handshake
  -> stream bounded semantic snapshots/events
  -> receive behavior intents

Neovim exits / plugin stops
  -> send shutdown
  -> close channel
  -> terminate child if needed
  -> all model/runtime memory is released
```

Failure of the sidecar is non-fatal. The Lua fallback remains functional.

## Rendering model

Rendering is avatar-dependent presentation. The engine does not assume a species or a single visual representation.

The current frontend supports two renderer kinds.

### Glyph actor

The default renderer direction is a small **1–3 terminal-row glyph actor**.

A glyph frame contains rows of styled text segments. Each segment has literal text plus an optional semantic color role. For example, a frame may use `outline`, `face`, `effect`, `success`, and `alert` roles without knowing the final Neovim highlight-group names.

This representation deliberately spends terminal cells on high-information features:

- face/eyes/mouth;
- ears, hair, horns, or headwear when useful;
- hand gestures;
- posture;
- tiny effects or motion residue.

A frame may use fewer rows than the avatar maximum. The renderer pads short frames into a fixed transparent render surface so one-line motion and three-line rest poses keep a stable screen-space anchor.

Glyph row width is validated using terminal display width, not UTF-8 byte length.

### Indexed pixel avatar

The earlier pixel renderer remains supported. Pixel sprites are indexed logical-pixel matrices. Two logical vertical pixels are packed into one terminal cell:

- same color: `█`
- top only: `▀`
- bottom only: `▄`
- different top/bottom colors: `▀` with foreground/background pair

The original fox uses this path. It remains useful as an alternate avatar and a regression target, but it is no longer the default product direction.

### Shared render surface

Both renderer kinds use a borderless, non-focusable, mouse-transparent floating window as an internal **render surface**. This is not a user-facing panel: it has no chrome, never accepts focus, and exists only to place the familiar in screen-cell coordinates. Visible glyphs/pixels receive extmark highlights. The edited buffer, undo history, and file contents are never modified.

A screen-space render surface is preferred over anchoring avatar rows to buffer lines because wrapped Markdown/LaTeX lines can occupy multiple screen rows; a buffer-line-anchored familiar would stretch or fragment under `wrap`.

Unicode beyond common terminal glyphs is considered decorative. Missing exotic glyph support must not destroy the avatar's identity.

## Spatial model

The companion lives in **screen space**, not document coordinates.

A safe-placement pass uses:

- window width/height;
- visible buffer lines;
- display width of those lines;
- avatar dimensions;
- configured margin.

The initial policy prefers empty space to the right of visible text. Future versions may maintain a fuller occupancy map including diagnostics, virtual text, folds, other windows, and reserved UI areas.

If no safe area exists, the companion should compact, peek, or hide. Covering important text is a bug, not a fallback.

## Motion and continuity

Changing coordinates is not itself an animation. Spatial relocation is represented as a transition plan.

Preferred order:

1. short distance: walk/hop;
2. medium distance: run/dash;
3. large or obstructed distance: vanish/appear or leave/enter edge;
4. impossible space: hide.

Buffer switches cannot safely be delayed merely to show a departure animation. The initial implementation therefore preserves continuity by animating **arrival** in the new buffer. Later versions may also use pre-leave cues when they can be shown without blocking editor actions.

Display modes (`full`, `compact`, `peek`, `hidden`) also require transitions rather than hard cuts when time and space permit. For glyph actors these modes may be represented by different row counts or partial faces rather than scaled versions of one sprite.

## World model

The world is multi-timescale.

### Fast presentation state

Updated without model inference:

- cursor/window position;
- current viewport;
- animation frame/timeline;
- interpolation along an existing path.

### Semantic editor state

Aggregated from events:

- current buffer and filetype;
- buffer switches;
- typing/idle periods;
- save/undo/search activity;
- diagnostics;
- build/test results when integrations exist;
- Markdown/LaTeX structural context;
- workspace tree summary and open buffers.

### Brain tick

A future model should run only on meaningful events or a low-frequency policy tick. It does not run per keypress or per animation frame.

## Text work is first-class

The world model must not assume that productive work means compiling code.

For Markdown, useful semantic events include heading changes, long writing bursts, list editing, note/link navigation, and buffer/note switches.

For LaTeX, useful events include section/subsection changes, environment entry, equations, figures, citations, compilation, and forward-search workflow.

A sustained writing session should often make the familiar *quieter*, not more active.

## AI boundary

A future model receives a bounded structured snapshot and returns only a schema-valid intent such as:

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

Every visible token (`question`, `sparkle`, etc.) maps to an asset declared by the avatar/runtime. The model cannot invent strings, Unicode, colors, commands, paths, glyph frames, or sprite data at runtime.

The deterministic `RuleBrain` always exists and is the fail-safe.

## Performance budget

The companion is decoration, so it receives a strict budget:

- animation typically 2-12 FPS, not 60 FPS;
- no work when hidden beyond low-frequency state tracking;
- no AI inference during high-rate typing unless a major event occurs;
- sidecar idle CPU should approach zero;
- no persistent process after Neovim exits;
- eventual tiny-model target: hundreds, not thousands, of megabytes of resident memory.

Performance claims are measurement targets until benchmarked on the primary macOS/iTerm2 environment.
