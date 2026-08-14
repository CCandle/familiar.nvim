# familiar.nvim

A tiny pixel-art familiar that lives inside Neovim.

`familiar.nvim` is an experimental Neovim companion: a terminal-native animated avatar that observes editor context, moves through available screen space, and reacts without chat, popups, or free-form generated text.

The first avatar is a small fox. The long-term design makes avatars, animations, emotes, personality data, and behavior policy replaceable.

> **Status:** early development. The current repository is a working vertical slice for the pixel renderer, lifecycle, basic telemetry, deterministic behavior, and Rust sidecar protocol. AI inference is intentionally not implemented yet.

## What it is

The intended experience is closer to a small game character living in the editor than to a status widget.

The current vertical slice already provides:

- terminal-native indexed pixel art rendered with half-block cells;
- short-distance walk/run relocation instead of visible coordinate jumps;
- disappear/appear transitions for large relocations and animated arrival after buffer changes;
- deterministic reactions to typing, idle time, diagnostics, and rapid buffer switching;
- a small fox with idle/blink, attention, walk/run, sleep, appear, and vanish frames;
- conservative safe placement that hides the familiar when the current window is too dense;
- a lifecycle-bound Rust sidecar with a Lua fallback;
- avatar validation for palette, sprite, and animation-graph consistency;
- an explicit animation demo command for real-terminal visual inspection.

Planned behavior includes richer screen-edge entry/exit, compact/peek display modes, Markdown/LaTeX structural awareness, declarative avatar packs, and eventually a tiny constrained local model.

The familiar never speaks. The eventual AI is a **constrained behavior director**, not a text generator or renderer.

## Architecture

```text
Neovim
  |
  | editor telemetry / lifecycle
  v
Lua frontend
  |  - Neovim API integration
  |  - pixel render surface
  |  - safe placement
  |  - animation presentation
  |
  | JSONL over stdio
  v
Rust familiar-core (child process)
     - protocol
     - world state
     - RuleBrain / future Brain implementations
     - spatial / transition planning (growing here over time)
     - memory (planned)
     - tiny local model backend (planned)
```

The Rust process is **not a daemon**. Neovim starts it on demand and terminates it on exit. If the sidecar is missing or fails, the Lua renderer remains usable with a deterministic fallback policy.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and the ADRs under [`docs/adr/`](docs/adr/).

## Rendering

The default renderer uses indexed logical pixels and Unicode half blocks (`▀`, `▄`, `█`). One terminal cell represents two vertical logical pixels. Sprites are therefore stored as tiny text matrices rather than PNG/JPG runtime assets.

The current implementation draws into a borderless, non-focusable, mouse-transparent floating window used purely as an internal render surface. `winblend` and per-pixel highlight blending keep untouched cells transparent while mixed top/bottom pixel cells stay colored. This keeps the sprite coherent in screen coordinates even when Markdown/LaTeX lines wrap.

The renderer currently searches for blank space on the right side of the active normal window. Wrapped rows are treated conservatively as occupied. If no safe region exists, the familiar disappears instead of covering the document.

The fox is still provisional art, but the current sprite is a recognizable 16×16 logical-pixel familiar rather than a placeholder status face. The stable external avatar-package format is intentionally deferred until the first visual round reveals what the engine actually needs.

## Current requirements

The initial development target is intentionally narrow:

- Neovim `>= 0.12`
- `lazy.nvim`
- a true-color terminal; iTerm2 is the primary development terminal
- macOS is the primary development OS
- Rust is optional for the current renderer slice, but required to build `familiar-core`

Broader package-manager and platform support comes later if the plugin proves worth maintaining.

## Install with lazy.nvim

For the current development version:

```lua
{
  "CCandle/familiar.nvim",
  event = "VeryLazy",
  build = "cargo build --release -p familiar-core",
  opts = {},
}
```

If Rust is unavailable, omit `build`. The plugin uses the Lua fallback rather than requiring Ollama or another permanent service.

For local development, point lazy.nvim directly at a checkout:

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

`FamiliarDemo` is intended for development/visual QA. For example:

```vim
:FamiliarDemo idle 5000
:FamiliarDemo inspect 5000
:FamiliarDemo walk 3000
:FamiliarDemo sleep 5000
:FamiliarDemo appear 1500
```

No default keymaps are installed.

## Configuration

```lua
require("familiar").setup({
  enabled = true,
  debug = false,

  core = {
    enabled = true,
    bin = nil, -- nil: auto-detect target/release/familiar-core
  },

  render = {
    frame_ms = 125,
    margin = 1,
    min_width = 48,
    min_height = 12,
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

1. Validate and tune the pixel renderer in the real iTerm2/font/theme combination.
2. Refine movement/relocation continuity and add compact/peek states.
3. Move the fox into a stable declarative avatar-package schema.
4. Make Markdown/LaTeX/editor structure first-class, not coding-only.
5. Benchmark tiny constrained models only after the deterministic runtime is pleasant.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) and [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Design non-goals

- no chat UI;
- no free-form model text;
- no background daemon when Neovim is closed;
- no Ollama dependency;
- no image-protocol dependency for the core experience;
- no model call per animation frame;
- no hiding core behavior behind a model that can fail unpredictably.

## References

The plugin architecture follows current Neovim and lazy.nvim primitives rather than inventing its own host system:

- Neovim API: <https://neovim.io/doc/user/api.html>
- Neovim channels/jobs: <https://neovim.io/doc/user/channel.html>
- lazy.nvim plugin spec: <https://lazy.folke.io/spec>
- lazy.nvim developer guidance: <https://lazy.folke.io/developers>

`blink.cmp` is also a useful precedent for shipping performance-sensitive Rust code inside a Neovim plugin while keeping the user-facing integration in Lua.

## License

MIT. See [`LICENSE`](LICENSE).
