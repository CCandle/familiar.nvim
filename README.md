# familiar.nvim

A tiny pixel-art familiar that lives inside Neovim.

`familiar.nvim` is an experimental Neovim companion: a terminal-native animated avatar that observes editor context, moves through available screen space, and reacts without chat, popups, or free-form generated text.

The first avatar is a small fox. The long-term design makes avatars, animations, emotes, personality data, and behavior policy replaceable.

> **Status:** early development. The current repository is a vertical slice for the renderer, lifecycle, telemetry, and Rust sidecar protocol. AI inference is intentionally not implemented yet.

## What it is

The intended experience is closer to a small game character living in the editor than to a status widget:

- it moves instead of teleporting when practical;
- it can run in from the screen edge when entering a buffer;
- large relocations can use disappear/appear transitions;
- it may sit quietly during sustained writing;
- it can react to diagnostics, buffer switching, idle time, and document structure;
- it never speaks;
- it may use only declared emotes/symbols from the active avatar package.

The eventual AI is a **constrained behavior director**, not a text generator or renderer.

## Architecture

```text
Neovim
  |
  | editor telemetry / lifecycle
  v
Lua frontend
  |  - Neovim API integration
  |  - extmark pixel renderer
  |  - safe placement
  |  - animation presentation
  |
  | JSONL over stdio
  v
Rust familiar-core (child process)
     - world state
     - behavior planning
     - spatial / transition planning
     - memory
     - later: tiny local model backend
```

The Rust process is **not a daemon**. Neovim starts it on demand and terminates it on exit. If the sidecar is missing or fails, the Lua renderer remains usable with a deterministic fallback policy.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and the ADRs under [`docs/adr/`](docs/adr/).

## Rendering

The default renderer uses indexed logical pixels and Unicode half blocks (`▀`, `▄`, `█`). One terminal cell can represent two vertical logical pixels with independent foreground/background colors. Sprites are therefore stored as text matrices, not PNG/JPG runtime assets.

The current implementation draws into a borderless, non-focusable floating window used purely as an internal render surface. That keeps the sprite in screen coordinates even when Markdown/LaTeX lines wrap. The renderer prefers blank regions and hides when it cannot find a safe location.

The first fox sprite is deliberately small and provisional; the asset format is being designed for later user-authored and AI-generated avatar packs.

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

If Rust is unavailable, omit `build`. The plugin will run the Lua fallback and report that the sidecar is unavailable only when debug logging is enabled.

For local development, lazy.nvim can point directly at a checkout:

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
  },
})
```

The public configuration surface is intentionally small while the architecture is still moving.

## Development priorities

1. Make the pixel renderer genuinely pleasant in iTerm2.
2. Make movement/relocation continuous and non-disruptive.
3. Expand the fox animation graph and avatar package schema.
4. Make Markdown/LaTeX/editor telemetry first-class, not coding-only.
5. Benchmark tiny constrained models only after the deterministic runtime is good.

See [`docs/ROADMAP.md`](docs/ROADMAP.md).

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
