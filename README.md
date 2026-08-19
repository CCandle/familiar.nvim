# familiar.nvim

A tiny terminal-native familiar that lives inside Neovim.

`familiar.nvim` is an experimental editor companion: a small animated character that watches editor context, moves through available screen space, and reacts without chat, popups, or free-form generated text.

The default familiar is **Mote**, a deliberately abstract 1–3 line glyph actor. It is not bound to a species. Its identity comes from a compact face grammar, optional ears/headwear, gestures, posture, timing, and a small effect vocabulary. A second glyph skin, **Spirit**, deliberately removes the ear silhouette to prove that runtime behavior is skin-independent. The earlier 16×16 pixel fox remains available as an alternate skin.

> **Status:** early development. The repository is a working vertical slice for glyph/pixel rendering, time-domain animation, lifecycle, basic telemetry, deterministic behavior, and the Rust sidecar protocol. Optional AI providers are designed but not implemented yet.

## What it is

The intended experience is closer to a tiny character living in the editor than to a status widget.

The current vertical slice provides:

- a default **1–3 terminal-row glyph familiar** rather than a fixed animal sprite;
- 60 FPS active motion by default, with optional 120 FPS high-refresh and 30 FPS economy profiles;
- fixed-duration relocation rather than movement time that grows with terminal-cell distance;
- cubic easing, in-flight retargeting, position stickiness, and automatic sparse motion trails;
- separate rendering channels for actor content, actor position, and effects;
- mode-aware behavior for Normal, Insert, Visual/Select, operator-pending, Replace, command-line, and related modes;
- low-frequency micro-expression such as blink, glance, silhouette twitch/shimmer, stretch, save acknowledgment, and diagnostic-resolution celebration;
- conservative safe placement that hides or relocates the familiar when its current region is no longer usable;
- a lifecycle-bound Rust sidecar with a Lua fallback;
- skin validation for glyph roles, row bounds, timed animation steps, pixel palettes, and animation graphs;
- explicit demo and live skin-switching commands for real-terminal visual inspection;
- the original half-block pixel renderer and fox skin as a compatibility/experimentation path.

The familiar does not need an AI model to feel alive. The eventual AI layer is an optional **low-frequency behavior director**, not a renderer, animation controller, or required dependency.

## Visual language

The default Mote skin is intentionally tiny:

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

Spirit uses the same runtime semantics without animal anatomy:

```text
     ✦
   ~(•ᴗ•)~
```

The design rule is:

> recognizable in at most three terminal rows; expression comes from glyph substitution, timing, gesture, and context rather than raster detail.

Mote and Spirit use semantic palette roles such as outline, face, effect, success, alert, and muted. Braille-like dots and symbols are reserved for motion residue or small effects rather than used to rasterize the body.

Future skins may add hair/headwear, use robot/blob grammars, or define entirely different silhouettes while keeping the same semantic behavior vocabulary.

## Animation model

The presentation engine is **time-domain**, not step-domain.

An ordinary relocation has a wall-clock duration (250 ms by default). Distance changes whether the familiar looks like it is walking, running, dashing, or phasing, but does not make a 20-row relocation take seconds.

When the editor target changes during motion, the old destination is replaced rather than queued. The current motion burst keeps its deadline whenever possible, so repeated scrolling converges on the newest safe position instead of replaying stale travel.

The actor's glyph content is not rebuilt simply because its position changed. High-frequency movement normally updates only a reusable floating-window position; unchanged quantized terminal cells are skipped entirely.

The default trail is `auto`: only sufficiently large run/dash motion emits sparse residues such as:

```text
≡  ->  ⠂  ->  ⠄  ->  ·
```

The whole actor is never smeared into multiple copies.

See [`docs/ANIMATION_ENGINE.md`](docs/ANIMATION_ENGINE.md) for the full design.

## Mode-aware interaction

Mode changes affect the familiar's **behavior budget**, not merely its facial expression.

| Mode | Default intent |
| --- | --- |
| Normal | observant and relaxed; low-frequency ambient fidgets allowed |
| Insert | quietly focused; suppress unnecessary movement and ambient novelty |
| Visual/Select | attentive to the selection; avoid distracting relocation |
| Operator-pending | anticipatory/focused; stay put when safe |
| Replace | alert/focused; stay unobtrusive |
| Command-line/prompt | compact; freeze if the current position is safe |
| Terminal | quiet/background policy; currently subject to normal-window rendering limits |

Safety always wins. A frozen/sticky familiar can still move or hide when its current screen region becomes unsafe.

## Architecture

```text
Neovim
  |
  | editor telemetry / lifecycle
  v
Lua frontend
  |  - semantic mode/activity integration
  |  - presentation planner
  |  - time-domain motion + expression scheduling
  |  - glyph + pixel render paths
  |  - safe placement / stickiness
  |
  | JSONL over stdio
  v
Rust familiar-core (child process)
     - protocol
     - world state
     - RuleBrain
     - future optional BrainProvider implementations
     - memory/personality state (planned)
```

The Rust process is **not a daemon**. Neovim starts it on demand and terminates it on exit. If the sidecar is missing or fails, the Lua renderer remains usable with deterministic behavior.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/ANIMATION_ENGINE.md`](docs/ANIMATION_ENGINE.md), [`docs/AVATAR_FORMAT_DRAFT.md`](docs/AVATAR_FORMAT_DRAFT.md), [`docs/BRAIN.md`](docs/BRAIN.md), and the ADRs under [`docs/adr/`](docs/adr/).

## Rendering and skins

Two render kinds currently exist.

### Glyph skins

`mote` and `spirit` store each frame as 1–3 rows of styled text segments. A segment carries text plus a semantic color role such as `outline`, `face`, or `effect`.

Rows may have different visible content but are validated against a small maximum terminal footprint. The renderer pads frames into a stable transparent surface, so one-line run/appear states and three-line rest states share a consistent anchor without requiring a raster sprite.

Animations can use explicit millisecond keyframes:

```lua
blink = {
  steps = {
    { frame = "blink", duration_ms = 70 },
    { frame = "idle", duration_ms = 90 },
  },
}
```

Special Unicode is decorative, not structural: a missing fancy glyph should never destroy the whole character.

### Pixel skins

The older `fox` skin uses indexed logical pixels packed with Unicode half blocks (`▀`, `▄`, `█`). It remains supported for comparison and future experimentation:

```lua
require("familiar").setup({
  skin = "fox",
})
```

`avatar = "fox"` remains a compatibility alias for the earlier configuration name.

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
- `:FamiliarSkin [name]`
- `:FamiliarDemo <animation> [duration_ms]`
- `:checkhealth familiar`

Examples:

```vim
:FamiliarSkin mote
:FamiliarSkin spirit
:FamiliarDemo inspect 5000
:FamiliarDemo sleep 5000
:FamiliarDemo wave 4000
:FamiliarDemo cheer 4000
:FamiliarDemo magic 4000
:FamiliarDemo peek 4000
```

No default keymaps are installed.

## Configuration

Most users should start with an animation profile:

```lua
require("familiar").setup({
  enabled = true,
  debug = false,
  skin = "mote",

  animation = {
    profile = "balanced", -- balanced | high_refresh | economy
  },
})
```

Built-in profiles:

| Profile | Active motion FPS | Ordinary relocation | Easing |
| --- | ---: | ---: | --- |
| `balanced` | 60 | 250 ms | cubic |
| `high_refresh` | 120 | 250 ms | cubic |
| `economy` | 30 | 280 ms | cubic |

Advanced overrides are available without requiring a custom profile:

```lua
require("familiar").setup({
  skin = "mote",

  animation = {
    profile = "balanced",
    fps = 60,
    duration_ms = 250,
    easing = "cubic", -- linear | quad | cubic | quart (out aliases also accepted)

    motion = {
      run_distance = 10,
      dash_distance = 26,
      dash_duration_ms = 190,
      retarget_min_remaining_ms = 70,
      retarget_max_extend_ms = 80,
    },

    trail = {
      mode = "auto", -- none | auto | always
      min_distance = 7,
      sample_ms = 38,
      lifetime_ms = 180,
      max_samples = 4,
    },

    stickiness = {
      enabled = true,
      utility_threshold = 0.18,
      distance_cost = 0.45,
      distance_scale = 24,
      recent_move_window_ms = 700,
      recent_move_cost = 0.35,
      moving_cost = 0.15,
    },
  },

  render = {
    margin = 1,
    min_width = 36,
    min_height = 8,
    warp_distance = 40,
    recompute_throttle_ms = 80,
  },

  telemetry = {
    snapshot_ms = 1200,
    max_visible_lines = 120,
  },
})
```

The detailed values are advanced tuning knobs. The intended normal UX is to choose a profile, skin, and trail preference rather than hand-tune physics.

## Optional AI direction

AI is deliberately not a current runtime dependency and will remain off by default.

The planned abstraction is provider-based rather than tied to one model:

```text
rule
local_llama        (embedded llama.cpp + opt-in GGUF download)
ollama
openai_compatible  (can point at hosted or local APIs)
custom
```

Local model weights would be downloaded only after explicit opt-in and stored under Neovim's data directory rather than inside the plugin checkout. Remote providers would be low-frequency semantic advisors; animation, safety, mode handling, cooldowns, and placement remain deterministic.

See [`docs/BRAIN.md`](docs/BRAIN.md).

## Development priorities

1. Real-terminal tuning of motion, trail, stickiness, and mode-aware interaction on the new presentation engine.
2. Refine Mote/Spirit micro-expression grammar and continue proving the skin contract with visually distinct actors.
3. Improve spatial behaviors such as real edge-peek, per-selection awareness, and richer safe-placement candidates.
4. Make Markdown/LaTeX/editor structure first-class, not coding-only.
5. Build PetBench before choosing any optional local AI model/backend.

## Design non-goals

- no required chat UI;
- no free-form model text as the core interaction language;
- no background daemon when Neovim is closed;
- no required Ollama dependency;
- no image-protocol dependency for the core experience;
- no model call per animation frame or keypress;
- no requirement that a skin represent a particular animal;
- no hiding core behavior behind a model that can fail unpredictably.

## License

MIT. See [`LICENSE`](LICENSE).
