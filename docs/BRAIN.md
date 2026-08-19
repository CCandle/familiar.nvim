# Brain providers

## Role

The brain is a low-frequency **behavior director**. It never renders frames, chooses screen coordinates, writes visible dialogue, invokes editor commands, or replaces deterministic safety rules.

`RuleBrain` is always present and produces an immediate intent. Optional AI providers run asynchronously and may replace that intent only with one currently allowed behavior label. If a provider is slow, malformed, unavailable, or returns a forbidden action, familiar.nvim simply continues with `RuleBrain`.

The current AI output vocabulary is deliberately tiny:

```text
idle
focus
inspect
curious
sleep
```

`hide` remains deterministic safety behavior. Target, locomotion, mood, emote, duration, placement, animation, and glyphs remain engine-owned.

## Provider contract

AI is disabled by default.

```text
BrainProvider
  |- rule               always available, no inference
  |- local_llama        embedded llama.cpp + managed/custom GGUF
  |- ollama             local OpenAI-compatible Ollama endpoint
  `- openai_compatible  hosted or self-hosted OpenAI-compatible endpoint
```

All inference happens inside `familiar-core`, not in Neovim's Lua event loop. The core owns a single background brain worker. Animation and editor interaction never wait for inference.

## Decision cadence

Default AI policy:

- ordinary AI decision eligibility: at most once every **20 seconds**;
- meaningful events (`buffer_enter`, save, diagnostic change): may trigger after a **5 second** minimum interval;
- no routine inference while the user is actively typing;
- only one request may be in flight;
- successful AI choices have a **30 second TTL**;
- a cached choice is revalidated against the current deterministic allowed-action set before use;
- provider timeout defaults to **8 seconds** and does not block Neovim.

The model is therefore not the character's animation loop or personality engine. Most liveliness comes from mode policy, state transitions, cooldowns, motion utility/stickiness, micro-actions, and the Presentation Engine.

## Editor context and privacy

When AI is enabled, familiar.nvim may include a bounded text window around the cursor:

```text
6 lines before
current line
6 lines after
```

Defaults:

```lua
context = {
  include_buffer_text = true,
  lines_before = 6,
  lines_after = 6,
  max_line_chars = 240,
  max_total_chars = 3200,
}
```

The current line is budgeted first, then the nearest surrounding lines. The entire source file is never sent by this mechanism.

When AI is disabled, text context is not collected into brain snapshots. For a remote provider, users who do not want source text to leave the machine can use:

```lua
brain = {
  enabled = true,
  provider = "openai_compatible",
  -- ...
  context = {
    include_buffer_text = false,
  },
}
```

That leaves mode, filetype, modified state, diagnostics, idle state, and other bounded metadata available to the policy.

## Rule-only default

No AI provider is required:

```lua
require("familiar").setup({
  brain = {
    enabled = false,
    provider = "rule",
  },
})
```

This is the default and requires no network or model download.

## Embedded local llama.cpp

The fully local path links llama.cpp into `familiar-core` behind the Cargo feature `local-llama`.

Build it with:

```bash
cargo build --release -p familiar-core --features local-llama
```

On macOS the binding uses the Metal backend. The model lives in the familiar data directory, not the lazy.nvim checkout.

The managed reference model is:

```text
SmolLM2-135M-Instruct
Q4_K_M GGUF
~105 MB
Apache-2.0
SHA-256: bda484992f9655d22504b14e57985257fa6a86937c61f957cf99c10a3bcae169
```

It is intentionally a **minimal policy experiment**, not a claim that a 135M model understands code like a hosted frontier model.

Install explicitly from Neovim:

```vim
:FamiliarBrainInstall
:FamiliarBrainStatus
```

The download is written to `.part`, checked for plausible size, GGUF magic, and the pinned SHA-256, then atomically renamed into:

```text
stdpath("data")/familiar/models/SmolLM2-135M-Instruct-Q4_K_M.gguf
```

Remove it with:

```vim
:FamiliarBrainRemove
```

Enable it:

```lua
require("familiar").setup({
  brain = {
    enabled = true,
    provider = "local_llama",
  },
})
```

A custom GGUF can be used without the managed model:

```lua
brain = {
  enabled = true,
  provider = "local_llama",
  local_model = {
    model_path = "~/models/my-model.gguf",
    n_ctx = 2048,
    n_threads = 4,
    n_gpu_layers = 99,
  },
}
```

## Ollama

Ollama exposes an OpenAI-compatible chat endpoint locally. familiar.nvim defaults the Ollama endpoint to:

```text
http://127.0.0.1:11434/v1/chat/completions
```

Only the model name is required:

```lua
require("familiar").setup({
  brain = {
    enabled = true,
    provider = "ollama",
    model = "qwen3:0.6b",
  },
})
```

Any Ollama model that can follow the one-word behavior contract can be tested. The project does not force one Ollama model.

## DeepSeek / OpenAI-compatible APIs

Use the full chat-completions endpoint, model name, and preferably an environment variable for the API key.

For current DeepSeek V4 Flash:

```lua
require("familiar").setup({
  brain = {
    enabled = true,
    provider = "openai_compatible",
    endpoint = "https://api.deepseek.com/chat/completions",
    model = "deepseek-v4-flash",
    api_key_env = "DEEPSEEK_API_KEY",

    -- DeepSeek V4 currently enables thinking by default. The familiar policy
    -- needs a tiny final label, so disable thinking rather than spending
    -- reasoning tokens on a five-way behavior choice.
    extra_body = {
      thinking = { type = "disabled" },
    },
  },
})
```

`extra_body` is passed to OpenAI-compatible request bodies for vendor-specific options. The engine reserves `model`, `messages`, and `stream`; those cannot be replaced through `extra_body`.

A generic provider looks the same:

```lua
brain = {
  enabled = true,
  provider = "openai_compatible",
  endpoint = "https://example.com/v1/chat/completions",
  model = "my-model",
  api_key_env = "FAMILIAR_API_KEY",
}
```

Direct `api_key = "..."` is supported, but `api_key_env` is preferred so credentials do not live in the Neovim configuration file.

## Provider request/output

The prompt contains only:

- the currently allowed behavior labels;
- mode and filetype;
- modified/diagnostic/activity metadata;
- previous behavior;
- the bounded nearby text context when enabled.

The provider is asked to return exactly one behavior word. Parsing remains defensive: only a token that exactly matches an allowed behavior is accepted. A JSON-ish response containing an allowed label is tolerated, but free-form text does not expand the action space.

Remote/OpenAI-compatible requests use these defaults:

```text
temperature = 0.15
max_tokens = 8
timeout = 8000ms
stream = false
```

The AI cannot emit coordinates, commands, arbitrary glyphs, skin definitions, shell operations, or user-visible prose.

## Safety envelope

The deterministic layer reduces the available action set before inference. Examples:

- active Insert/Replace typing collapses the set to `focus`;
- errors allow `inspect`, `focus`, or `curious`;
- long idle allows `sleep` or `idle`;
- command/visual states strongly restrict novelty;
- unsafe/small presentation space deterministically hides the familiar.

A model cannot override these restrictions.

## Why SmolLM2-135M-Instruct

For the built-in local reference, the current practical sub-150M field is narrow.

`SmolLM2-135M-Instruct` is small enough to be a reasonable optional download, has an Apache-2.0 license, has readily available GGUF quantization, works with llama.cpp, and is actually instruction-tuned. It therefore makes a clean **lower-bound benchmark**.

Other sub-150M candidates tend to be base language models that would need a familiar-specific fine-tune, or have less convenient distribution/licensing. A future tiny classifier or project-specific policy model may eventually replace the generic 135M LLM if PetBench shows it can preserve useful contextual behavior with lower memory and latency.

## PetBench direction

The provider abstraction exists so the same scenarios can compare:

```text
RuleBrain
SmolLM2-135M embedded
Ollama local models
DeepSeek / other hosted APIs
future specialized policy models
```

Useful metrics include contextual appropriateness, nuisance rate, action continuity, malformed-output rate, latency, resident memory, network/API cost, and how often the AI choice actually differs beneficially from RuleBrain.
