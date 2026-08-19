# Lua ↔ Rust protocol

## Transport

familiar.nvim uses JSON Lines over the lifecycle-bound `familiar-core` child process.

- one UTF-8 JSON object per line;
- protocol negotiation via `hello`;
- stdout is protocol-only; diagnostic logging goes to stderr;
- malformed provider/model output never becomes protocol text;
- malformed client messages must not crash Neovim.

Protocol version: **2**.

## Client → core

### hello

```json
{"type":"hello","protocol":2,"client":"familiar.nvim"}
```

### configure

Sent after `hello`. AI is off by default.

```json
{
  "type":"configure",
  "brain":{
    "enabled":false,
    "provider":"rule",
    "interval_ms":20000,
    "event_min_interval_ms":5000,
    "choice_ttl_ms":30000,
    "timeout_ms":8000,
    "max_tokens":8,
    "temperature":0.15,
    "local":{
      "model_path":"/path/to/model.gguf",
      "n_ctx":2048,
      "n_threads":4,
      "n_gpu_layers":99
    }
  }
}
```

`provider` is currently `rule`, `local_llama`, `ollama`, or `openai_compatible`.

`openai_compatible` may additionally carry `model`, `endpoint`, `api_key`, and `extra_body`. API credentials are never sent back by the core.

### snapshot

```json
{
  "type":"snapshot",
  "seq":12,
  "snapshot":{
    "mode":"n",
    "buffer":{"id":4,"name":"main.rs","filetype":"rust","modified":true,"line_count":310},
    "viewport":{"width":128,"height":43,"cursor_row":82,"cursor_col":16,"topline":60,"botline":102,"line_display_widths":[33,74,0]},
    "diagnostics":{"errors":0,"warnings":1},
    "activity":{"idle_ms":90,"typing":false,"buffer_switches_10s":0},
    "context":{
      "current_line":"let value = compute();",
      "before":["fn work() {"],
      "after":["}"]
    }
  }
}
```

The Lua frontend bounds viewport widths and optional nearby text. With AI disabled, brain text context is empty. Remote-provider context limits are documented in `BRAIN.md`.

### event

```json
{"type":"event","seq":13,"event":{"kind":"buffer_enter","buffer":8}}
```

Events update deterministic state immediately and may make a later low-frequency AI decision eligible; they do not synchronously invoke a provider.

### ping / shutdown

```json
{"type":"ping","id":7}
{"type":"shutdown"}
```

## Core → client

### ready

```json
{
  "type":"ready",
  "protocol":2,
  "core":"familiar-core",
  "version":"0.1.0",
  "local_llama":false
}
```

`local_llama` reports whether this binary was compiled with the embedded llama.cpp feature.

### brain_status

Emitted when provider state changes:

```json
{
  "type":"brain_status",
  "enabled":true,
  "provider":"openai_compatible",
  "state":"querying"
}
```

States include `disabled`, `idle`, `querying`, `ready`, `error`, `unavailable`, and `disconnected` on the Lua side. Provider errors are diagnostic state only; deterministic behavior continues.

### intent

```json
{
  "type":"intent",
  "seq":12,
  "intent":{
    "behavior":"inspect",
    "target":"cursor_area",
    "locomotion":"walk",
    "mood":"concerned",
    "emote":"question",
    "duration_ms":7000
  }
}
```

The AI provider never authors this full structure directly. It may choose one behavior label from the deterministic allow-list; the core maps that label back into a validated `BehaviorIntent`.

### error / pong

```json
{"type":"error","message":"protocol mismatch"}
{"type":"pong","id":7}
```

## Compatibility rules

- Unknown/malformed messages should be reported and ignored when safe.
- New optional fields may be added without a protocol bump.
- Semantics-breaking changes require a bump.
- A mismatched core must not continue normal planning.
- Provider failures never invalidate the JSONL transport or block editor animation.
