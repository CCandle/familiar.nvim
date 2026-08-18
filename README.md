# familiar.nvim

A tiny terminal-native familiar that lives inside Neovim.

`familiar.nvim` is an experimental editor companion: a small animated character that watches editor context, moves through available screen space, and reacts without chat, popups, or free-form generated text.

The default familiar is now **Mote**, a deliberately abstract 1–3 line glyph actor. It is not bound to a species. Its identity comes from a compact face grammar, optional ears/headwear, hand gestures, posture, and a small effect vocabulary. The earlier 16×16 pixel fox remains available as an alternate avatar while the renderer architecture evolves.

> **Status:** early development. The repository is a working vertical slice for glyph/pixel rendering, lifecycle, basic telemetry, deterministic behavior, and the Rust sidecar protocol. AI inference is intentionally not implemented yet.

## What it is

The intended experience is closer to a tiny character living in the editor than to a status widget.

The current vertical slice provides:

- a default **1–3 terminal-row glyph familiar** rather than a fixed animal sprite;
- expressive state changes through facial glyph substitution, gestures, posture, and tiny Unicode effects;
- short-distance walk/run relocation instead of visible coordinate jumps;
- disappear/appear transitions for large relocations and animated arrival after buffer changes;
- deterministic reactions to typing, idle time, diagnostics, and rapid buffer switching;
- conservative safe placement that hides the familiar when the current window is too dense;
- a lifecycle-bound Rust sidecar with a Lua fallback;
- avatar validation for glyph roles, row bounds, pixel palettes, frames, and animation graphs;
- an explicit animation demo command for real-terminal visual inspection;
- the original half-block pixel renderer and fox avatar as a compatibility/experimentation path.

The familiar never speaks. The eventual AI is a **constrained behavior director**, not a text generator or renderer.

## Visual language

The default avatar is intentionally tiny:

```text
   /\_/\
  ( •ω• )
```

It can collapse to one line for motion or compact states:

```text
  (•ω•)ﾉ
  ≡(•̀ω•́)
```

and expand to three lines only when posture benefits from it:

```text
   /\_/\
  ( -ω- )___
  ──────────
```

The design rule is:

> recognizable in at most three terminal rows; expression comes from glyph substitution and pose, never from raster detail.

Mote uses a restrained palette of outline, face, effect, success, and alert roles. Braille-like dots and symbols are reserved for motion residue or small effects rather than used to rasterize the body.

The default design is cat-ish only when the ears help the silhouette. It is not canonically a cat, fox, or furry character. Avatar packs are expected to replace or omit ears, add hair/headwear, change facial grammar, and define different gestures while keeping the same semantic action vocabulary.

## Architecture

```text
Neovim
  |
  | editor telemetry / lifecycle
  v
Lua frontend
  |  - Neovim API integration
  |  - glyph + pixel render paths
  |  - safe placement
  |  - animation presentation
  |
  | JSONL over stdio
  v
Rust familiar-core (child process)
     - protocol
     - world state
     - RuleBrain / future Brain implementations
     - spatial / transition planning
     - memory (planned)
     - tiny local model backend (planned)
```

The Rust process is **not a daemon**. Neovim starts it on demand and terminates it on exit. If the sidecar is missing or fails, the Lua renderer remains usable with a deterministic fallback policy.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/AVATAR_FORMAT_DRAFT.md`](docs/AVATAR_FORMAT_DRAFT.md), and the ADRs under [`docs/adr/`](docs/adr/).

## Rendering

Two render kinds currently exist.

### Glyph avatars

The default `mote` avatar stores each frame as 1–3 rows of styled text segments. A segment carries text plus a semantic color role such as `outline`, `face`, or `effect`.

Rows may have different visible content but are validated against a small maximum terminal footprint. The renderer pads frames into a stable transparent surface, so one-line run/appear states and three-line rest states share a consistent anchor without requiring a raster sprite.

This path intentionally prefers common terminal glyphs. Special Unicode is decorative, not structural: a missing fancy wedge must never destroy the character.

### Pixel avatars

The older `fox` avatar uses indexed logical pixels packed with Unicode half blocks (`▀`, `▄`, `█`). It remains supported for comparison and future avatar experimentation:

```lua
require("familiar").setup({
  avatar = "fox",
})
```

The current renderer draws into a borderless, non-focusable floating window used purely as an internal render surface. The surface is transparent and uses highlight groups only for visible character/pixel cells.

Safe placement currently searches blank space on the right side of the active normal window. Wrapped rows are treated conservatively as occupied. If no safe region exists, the familiar disappears instead of covering the document.

## Current requirements

The initial development target is intentionally narrow:

- Neovim `>= 0.12`
- `lazy.nvim`
- a true-color terminal; iTerm2 is the primary development terminal
- macOS is the primary development OS
- Rust is optional for the Lua fallback, but required to build `familiar-core`

Broader package-manager and platform support comes later if the plugin proves worth maintaining.

## Install with lazy.nvim

```lua
{
  "CCandle/familiar.nvim",
  event = "VeryLazy",
  build = "cargo build --release -p familiar-core",
  opts = {},
}
```

If Rust is unavailable, omit `build`. The plugin uses the Lua fallback rather than requiring Ollama or another permanent service.

For local development:

```lua
{
  dir = "~/Coding/familiar.nvim",
  event = "VeryLazy",
  build = "cargo build --release -p familiar-core",
  opts = {
    debug = true,
  },
}
```

## Commands

- `:FamiliarStart`
- `:FamiliarStop`
- `:FamiliarToggle`
- `:FamiliarStatus`
- `:FamiliarDemo <animation> [duration_ms]`
- `:checkhealth familiar`

`FamiliarDemo` is intended for visual QA. The default Mote avatar includes both behavioral and showcase animations:

```vim
:FamiliarDemo idle 5000
:FamiliarDemo inspect 5000
:FamiliarDemo walk 3000
:FamiliarDemo sleep 5000
:FamiliarDemo wave 4000
:FamiliarDemo cheer 4000
:FamiliarDemo magic 4000
:FamiliarDemo peek 4000
```

No default keymaps are installed.

## Configuration

```lua
require("familiar").setup({
  enabled = true,
  debug = false,
  avatar = "mote", -- "mote" (default glyph actor) or "fox" (legacy pixel avatar)

  core = {
    enabled = true,
    bin = nil,
  },

  render = {
    frame_ms = 125,
    margin = 1,
    min_width = 36,
    min_height = 8,
    move_step = 2,
    warp_distance = 32,
  },

  telemetry = {
    snapshot_ms = 1200,
    max_visible_lines = 120,
  },
})
```

The public configuration surface is intentionally small while the architecture is still moving.

## Development priorities

1. Refine the 1–3 row glyph character grammar in real terminals and make the default Mote feel alive rather than decorative.
2. Improve movement/relocation continuity and turn `peek`/edge interaction into real spatial behaviors rather than demo-only animations.
3. Stabilize a declarative avatar-package schema that can represent glyph actors first and pixel sprites second.
4. Make Markdown/LaTeX/editor structure first-class, not coding-only.
5. Benchmark tiny constrained models only after the deterministic runtime is pleasant.

## Design non-goals

- no chat UI;
- no free-form model text;
- no background daemon when Neovim is closed;
- no Ollama dependency;
- no image-protocol dependency for the core experience;
- no model call per animation frame;
- no requirement that an avatar represent a particular animal;
- no hiding core behavior behind a model that can fail unpredictably.

## License

MIT. See [`LICENSE`](LICENSE).
