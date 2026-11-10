# familiar.nvim

A tiny terminal-native familiar that lives inside Neovim.

`familiar.nvim` is an experimental editor companion: a small animated character that watches editor context, moves through available screen space, and reacts without chat, popups, or free-form generated text.

The default familiar is **Mote**, a deliberately abstract 1–3 line glyph actor. A second glyph skin, **Spirit**, proves that runtime behavior is skin-independent. The earlier 16×16 pixel fox remains available as an alternate skin.

> **Status:** early development. The repository is a working vertical slice for glyph/pixel rendering, time-domain animation, lifecycle, bounded editor telemetry, deterministic behavior, a lifecycle-bound Rust sidecar, and optional low-frequency AI BrainProviders.

## What it is

The intended experience is closer to a tiny character living in the editor than to a status widget.

The current vertical slice provides:

- a default **1–3 terminal-row glyph familiar** rather than a fixed animal sprite;
- 60 FPS active motion by default, with optional 120 FPS high-refresh and 30 FPS economy profiles;
- fixed-duration relocation, cubic easing, in-flight retargeting, position stickiness, and sparse motion trails;
- separate rendering channels for actor content, actor position, and effects;
- mode-aware behavior for Normal, Insert, Visual/Select, operator-pending, Replace, command-line, and related modes;
- low-frequency micro-expression such as blink, glance, silhouette twitch/shimmer, stretch, save acknowledgment, and diagnostic-resolution celebration;
- conservative safe placement that hides or relocates the familiar when its current region is no longer usable;
- a lifecycle-bound Rust sidecar with a Lua deterministic fallback;
- optional `local_llama`, Ollama, and OpenAI-compatible BrainProviders;
- strict model output validation, deterministic action allow-lists, stale-result rejection, provider failure backoff, and provider metrics;
- explicit demo, skin switching, BrainProvider status/reload/test, and managed-model commands;
- the original half-block pixel renderer and fox skin as a compatibility/experimentation path.

The familiar does **not** need an AI model to feel alive. AI is disabled by default and acts only as an optional **low-frequency behavior director**: it never renders frames, chooses screen coordinates, invokes editor commands, or emits visible dialogue. RuleBrain remains the default product behavior until the user explicitly enables another provider.

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

and expand to three lines when posture benefits from it:

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

## Animation model

The presentation engine is **time-domain**, not step-domain.

An ordinary relocation has a wall-clock duration (250 ms by default). Distance changes whether the familiar looks like it is walking, running, dashing, or phasing, but does not make a 20-row relocation take seconds.

When the editor target changes during motion, the old destination is replaced rather than queued. The current burst keeps its deadline whenever possible, so repeated scrolling converges on the newest safe position instead of replaying stale travel.

The default trail is `auto`: only sufficiently large run/dash motion emits sparse residues such as:

```text
≡  ->  ⠂  ->  ⠄  ->  ·
```

See [`docs/ANIMATION_ENGINE.md`](docs/ANIMATION_ENGINE.md) for details.

## Mode-aware interaction

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
  | bounded editor telemetry / lifecycle
  v
Lua frontend
  |  - mode/activity integration
  |  - presentation planner
  |  - time-domain motion + expression scheduling
  |  - glyph + pixel render paths
  |  - safe placement / stickiness
  |
  | JSONL over stdio
  v
Rust familiar-core (child process)
     - protocol + world state
     - mandatory RuleBrain
     - optional asynchronous BrainProvider worker
       |- embedded llama.cpp / GGUF
       |- Ollama
       `- OpenAI-compatible APIs
     - strict action validation / backoff / metrics
```

The Rust process is **not a daemon**. Neovim starts it on demand and terminates it on exit. If the sidecar is missing or fails, the Lua renderer remains usable with deterministic behavior.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/ANIMATION_ENGINE.md`](docs/ANIMATION_ENGINE.md), [`docs/AVATAR_FORMAT_DRAFT.md`](docs/AVATAR_FORMAT_DRAFT.md), [`docs/BRAIN.md`](docs/BRAIN.md), and the ADRs under [`docs/adr/`](docs/adr/).

## Rendering and skins

### Glyph skins

`mote` and `spirit` store each frame as 1–3 rows of styled text segments. A segment carries text plus a semantic color role such as `outline`, `face`, or `effect`.

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

The older `fox` skin uses indexed logical pixels packed with Unicode half blocks (`▀`, `▄`, `█`):

```lua
require("familiar").setup({
  skin = "fox",
})
```

`avatar = "fox"` remains a compatibility alias for the earlier configuration name.

## Requirements

The initial development target is intentionally narrow:

- Neovim `>= 0.12`
- `lazy.nvim`
- a true-color terminal; iTerm2 is the primary development terminal
- macOS is the primary development OS
- Rust is optional for the Lua fallback, but required for `familiar-core` and all AI providers

## Install with lazy.nvim

Deterministic core + remote/Ollama providers:

```lua
{
  "CCandle/familiar.nvim",
  event = "VeryLazy",
  build = "cargo build --release -p familiar-core",
  opts = {},
}
```

For the fully embedded local GGUF provider, build with llama.cpp support:

```lua
{
  "CCandle/familiar.nvim",
  event = "VeryLazy",
  build = "cargo build --release -p familiar-core --features local-llama",
  opts = {},
}
```

If Rust is unavailable, omit `build`; the plugin falls back to deterministic Lua behavior, but AI providers are unavailable.

For local development:

```lua
{
  dir = "~/Coding/familiar.nvim",
  event = "VeryLazy",
  build = "cargo build --release -p familiar-core --features local-llama",
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
- `:FamiliarBrainStatus`
- `:FamiliarBrainReload`
- `:FamiliarBrainTest`
- `:FamiliarBrainInstall`
- `:FamiliarBrainRemove`
- `:checkhealth familiar`

`FamiliarBrainTest` runs one real inference through the configured provider and reports the selected behavior and latency. The probe does **not** alter the familiar's behavior cache or trigger an animation.

No default keymaps are installed.

## Basic configuration

```lua
require("familiar").setup({
  enabled = true,
  skin = "mote",
  animation = {
    profile = "balanced", -- balanced | high_refresh | economy
  },
})
```

| Profile | Active motion FPS | Ordinary relocation | Easing |
| --- | ---: | ---: | --- |
| `balanced` | 60 | 250 ms | cubic |
| `high_refresh` | 120 | 250 ms | cubic |
| `economy` | 30 | 280 ms | cubic |

## Optional AI providers

RuleBrain is the default. Local and network-backed AI providers are explicit opt-ins. The deterministic engine always retains final control over safety, placement, mode handling, animation, and the allowed action set.

### Embedded local model

Build with `--features local-llama`, then explicitly download the managed reference model:

```vim
:FamiliarBrainInstall
```

The current reference is **SmolLM2-135M-Instruct Q4_K_M**, about 105 MB, Apache-2.0. The download is SHA-256 verified before installation and stored under `stdpath("data")/familiar/models/` unless `brain.local_model.model_path` is explicitly overridden.

```lua
require("familiar").setup({
  brain = {
    enabled = true,
    provider = "local_llama",
  },
})
```

Then verify the real inference path:

```vim
:FamiliarBrainTest
:FamiliarBrainStatus
```

### Ollama

```lua
require("familiar").setup({
  brain = {
    enabled = true,
    provider = "ollama",
    model = "qwen3:0.6b",
  },
})
```

Ollama defaults to `http://127.0.0.1:11434/v1/chat/completions`.

### OpenAI-compatible / DeepSeek

```lua
require("familiar").setup({
  brain = {
    enabled = true,
    provider = "openai_compatible",
    base_url = "https://api.deepseek.com",
    model = "deepseek-v4-flash",
    api_key_env = "DEEPSEEK_API_KEY",
    extra_body = {
      thinking = { type = "disabled" },
    },
  },
})
```

You may provide a complete `endpoint` instead of `base_url`, add string `headers` for gateways/non-Bearer authentication, and pass vendor-specific fields through `extra_body`.

Provider calls are low-frequency and asynchronous. Successful decisions are bound to the semantic editor context the model actually saw; stale results are rejected. Failures fall back immediately to RuleBrain and use exponential retry backoff.

Nearby source context is bounded by default. Obvious sensitive names/filetypes such as `.env*`, `id_rsa*`, `id_ed25519*`, and `dotenv` are excluded client-side. Set `brain.context.include_buffer_text = false` to use metadata-only remote decisions.

Live switching is supported without restarting Neovim:

```lua
require("familiar").brain({
  enabled = true,
  provider = "ollama",
  model = "qwen3:0.6b",
})
```

`:FamiliarBrainReload` re-resolves environment-based credentials and reconstructs the provider worker.

See [`docs/BRAIN.md`](docs/BRAIN.md) for the full contract, privacy limits, provider knobs, and local model details.

## Development priorities

1. Real-terminal tuning of motion, trail, stickiness, and mode-aware interaction.
2. Refine Mote/Spirit micro-expression grammar and expand visually distinct skins.
3. Improve spatial behaviors such as real edge-peek, selection awareness, and richer safe-placement candidates.
4. Make Markdown/LaTeX/editor structure first-class, not coding-only.
5. Build PetBench scenarios to compare RuleBrain, the 135M local lower bound, Ollama models, and hosted APIs on behavior quality rather than chatbot benchmarks.

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
