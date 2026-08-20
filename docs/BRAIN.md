# Brain providers

## Role

The brain is a low-frequency **behavior director**. It never renders frames, chooses screen coordinates, writes visible dialogue, invokes editor commands, or replaces deterministic safety rules.

`RuleBrain` is mandatory and produces an immediate intent. Optional AI providers run behind the Rust sidecar and may replace that intent only with one currently allowed behavior label:

```text
idle
focus
inspect
curious
sleep
```

`hide` remains deterministic safety behavior. Target, locomotion, mood, emote, duration, placement, animation, and glyphs remain engine-owned.

## Provider architecture

The product default is `RuleBrain` with AI disabled. `local_llama`, Ollama, and hosted OpenAI-compatible providers are explicit opt-ins. Missing or failed AI infrastructure always falls back to deterministic behavior.

```text
BrainProvider
  |- rule               always available, no inference
  |- local_llama        embedded llama.cpp + managed/custom GGUF
  |- ollama             local OpenAI-compatible endpoint
  `- openai_compatible  hosted or self-hosted OpenAI-compatible endpoint
```

All inference happens inside `familiar-core`, not in Neovim's Lua event loop. The core owns one provider worker, so a slow HTTP request or local model decode never blocks editor rendering or input.

The Rust binding for embedded llama.cpp is intentionally pinned to the tested crate version. Provider implementations are recreated on configuration reload instead of accumulating long-lived sessions.

## Deterministic safety envelope

Before a provider sees a request, deterministic policy computes the eligible behavior set. Examples:

- active Insert/Replace typing collapses the set to `focus`;
- diagnostics may allow `inspect`, `focus`, or `curious`;
- long idle allows `sleep` or `idle`;
- command/visual states strongly restrict novelty;
- unsafe or very small presentation space deterministically hides the familiar.

A model cannot expand this set.

Provider output is intentionally narrower than a general structured-agent schema. The current parser accepts only:

```text
curious
"curious"
`curious`
{"behavior":"curious"}
```

when `curious` is currently allowed. Arbitrary prose such as `I think curious is best` is rejected and falls back to RuleBrain. The model cannot emit coordinates, commands, file paths, arbitrary glyphs, shell operations, or user-visible prose.

## Decision cadence and failure policy

Defaults:

```text
ordinary decision interval     20 s
event minimum interval          5 s
successful choice TTL          30 s
provider timeout                8 s
max output tokens               8
temperature                  0.15
```

Additional rules:

- no routine inference while the user is actively typing;
- only one provider request is in flight;
- cached choices are revalidated against the current deterministic allow-list;
- each normal result is bound to a semantic hash of the editor context the model actually saw;
- if the buffer/mode/diagnostics/nearby text changes while inference is running, that stale result is not applied;
- failures immediately fall back to deterministic behavior;
- repeated failures use exponential retry backoff: approximately 2, 4, 8, 16, 32, then 60 seconds maximum;
- a provider failure can leave a still-valid prior choice available, reported as `degraded` rather than crashing the runtime.

## Observability and testing

`:FamiliarBrainStatus` exposes provider state without secrets, including:

```text
provider / state
last_latency_ms
last_choice
consecutive_failures
total_requests
total_successes
embedded local_llama capability
managed-model status
```

`:FamiliarBrainTest` performs one **real inference** through the currently configured provider and reports the selected behavior and latency. It uses the same provider worker/model instance as normal decisions, but its result is diagnostic-only: it does not enter the normal behavior cache and does not trigger an animation.

`:FamiliarBrainReload` reconstructs the provider from the current configuration and re-resolves environment-based credentials. Programmatic equivalents are available:

```lua
require("familiar").brain_status()
require("familiar").brain_reload()
require("familiar").brain_test(function(result)
  print(vim.inspect(result))
end)
```

The provider can also be switched live:

```lua
require("familiar").brain({
  enabled = true,
  provider = "ollama",
  model = "qwen3:0.6b",
})
```

No Neovim restart is required.

## Editor context and privacy

When AI is enabled, familiar.nvim may include a bounded text window around the cursor:

```lua
context = {
  include_buffer_text = true,
  lines_before = 6,
  lines_after = 6,
  max_line_chars = 240,
  max_total_chars = 3200,
  deny_filetypes = { "dotenv" },
  deny_name_patterns = {
    "^%.env",
    "^id_rsa",
    "^id_ed25519",
  },
}
```

The current line is budgeted first, then nearby lines. The entire source file is never sent by this mechanism.

The deny rules execute in Lua **before** the snapshot is sent to `familiar-core`, so obvious secret buffers do not enter the provider pipeline. Users can extend both lists.

When AI is disabled, text context is not collected into brain snapshots. For metadata-only remote decisions:

```lua
brain = {
  enabled = true,
  provider = "openai_compatible",
  context = {
    include_buffer_text = false,
  },
}
```

## Rule-only default

No AI provider is required. This is the default product configuration:

```lua
require("familiar").setup({
  brain = {
    enabled = false,
    provider = "rule",
  },
})
```

It requires no network or model download.

## Embedded local llama.cpp

Build the sidecar with:

```bash
cargo build --release -p familiar-core --features local-llama
```

On macOS the binding uses the Metal backend. Model weights live in Neovim's data directory, not the lazy.nvim checkout.

The managed reference model is:

```text
SmolLM2-135M-Instruct
Q4_K_M GGUF
~105 MB
Apache-2.0
SHA-256: bda484992f9655d22504b14e57985257fa6a86937c61f957cf99c10a3bcae169
```

This is intentionally a **lower-bound policy experiment**, not a claim that 135M parameters understand code like a hosted frontier model.

Install explicitly:

```vim
:FamiliarBrainInstall
:FamiliarBrainStatus
```

The download is written to `.part`, checked for plausible size and GGUF magic, verified against the pinned SHA-256, then atomically renamed to:

```text
stdpath("data")/familiar/models/SmolLM2-135M-Instruct-Q4_K_M.gguf
```

Enable and test:

```lua
require("familiar").setup({
  brain = {
    enabled = true,
    provider = "local_llama",
  },
})
```

```vim
:FamiliarBrainTest
```

A custom GGUF can be used instead:

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

Remove the managed reference model with `:FamiliarBrainRemove`.

## Ollama

Ollama defaults to:

```text
http://127.0.0.1:11434/v1/chat/completions
```

Only a model name is required:

```lua
require("familiar").setup({
  brain = {
    enabled = true,
    provider = "ollama",
    model = "qwen3:0.6b",
  },
})
```

The project does not force one Ollama model; `:FamiliarBrainTest` is intended to make A/B testing easy.

## OpenAI-compatible APIs

Two URL styles are supported.

A standard base URL:

```lua
brain = {
  enabled = true,
  provider = "openai_compatible",
  base_url = "https://example.com/v1",
  model = "my-model",
  api_key_env = "FAMILIAR_API_KEY",
}
```

will call `https://example.com/v1/chat/completions`.

Or provide the complete endpoint:

```lua
endpoint = "https://example.com/v1/chat/completions"
```

String and segmented text response content are both accepted.

### DeepSeek example

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

The familiar policy is only a small behavior choice, so disabling heavyweight reasoning is normally preferable when a provider enables it by default.

## Authentication and gateway compatibility

Bearer authentication can be supplied directly or, preferably, through an environment variable:

```lua
api_key_env = "FAMILIAR_API_KEY"
```

For gateways or providers using other headers:

```lua
headers = {
  ["x-client-name"] = "familiar.nvim",
}

header_env = {
  ["x-api-key"] = "MY_PROVIDER_API_KEY",
}
```

`header_env` resolves the environment variable only when the provider configuration is sent to the sidecar. `:FamiliarBrainReload` therefore picks up a rotated key without restarting Neovim.

`extra_body` carries vendor-specific JSON request fields. `model`, `messages`, and `stream` are reserved by familiar.nvim and cannot be overwritten through `extra_body`.

## Why SmolLM2-135M-Instruct

For the built-in sub-150M reference, the practical field is narrow. `SmolLM2-135M-Instruct` is small, Apache-2.0, instruction-tuned, readily available as GGUF, and supported by llama.cpp. That makes it a clean lower-bound experiment.

Many smaller alternatives are base language models rather than instruction models or have less convenient licensing/distribution. A future familiar-specific classifier/policy model may beat a generic 135M LLM on latency, memory, and consistency; the provider abstraction deliberately leaves that path open.

## PetBench direction

The same behavior scenarios should eventually compare:

```text
RuleBrain
SmolLM2-135M embedded
Ollama local models
DeepSeek / other hosted APIs
future specialized policy models
```

Useful metrics include contextual appropriateness, nuisance rate, action continuity, malformed-output rate, latency, resident memory, network/API cost, and how often an AI choice actually improves on RuleBrain.
