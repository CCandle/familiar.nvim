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

Sent after `hello` and whenever the BrainProvider is reloaded or switched.

```json
{
  "type":"configure",
  "brain":{
    "enabled":true,
    "provider":"openai_compatible",
    "model":"example-model",
    "base_url":"https://example.com/v1",
    "api_key":"resolved-secret",
    "headers":{"x-gateway":"example"},
    "extra_body":{},
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

The Lua layer resolves environment-based credentials before this message is sent. Credentials are never returned in status messages or protocol errors.

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

The Lua frontend bounds viewport widths and optional nearby text. With AI disabled, brain text context is empty. Sensitive-buffer filtering happens before this message is constructed for provider use.

### event

```json
{"type":"event","seq":13,"event":{"kind":"buffer_enter","buffer":8}}
```

Events update deterministic state immediately and may make a later low-frequency AI decision eligible; they do not synchronously invoke a provider.

### brain_probe

```json
{
  "type":"brain_probe",
  "id":3,
  "snapshot":{
    "mode":"n",
    "buffer":{"id":4,"name":"main.rs","filetype":"rust","modified":false,"line_count":120},
    "viewport":{"width":120,"height":40,"cursor_row":20,"cursor_col":4,"topline":1,"botline":40,"line_display_widths":[]},
    "diagnostics":{"errors":0,"warnings":0},
    "activity":{"idle_ms":400,"typing":false,"buffer_switches_10s":0},
    "context":{"current_line":"fn main() {}","before":[],"after":[]}
  }
}
```

A probe uses the same loaded provider/model instance as normal policy inference, but its result is diagnostic-only. It does not update the normal behavior cache and does not trigger an animation.

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
  "local_llama":true
}
```

`local_llama` reports whether this binary was compiled with embedded llama.cpp support.

### brain_status

Emitted when provider state or metrics change:

```json
{
  "type":"brain_status",
  "enabled":true,
  "provider":"openai_compatible",
  "state":"ready",
  "last_latency_ms":214,
  "last_choice":"curious",
  "consecutive_failures":0,
  "total_requests":4,
  "total_successes":4
}
```

Core states include `disabled`, `idle`, `querying`, `ready`, `degraded`, `error`, and `unavailable`. The Lua status layer also uses `reconfiguring` and `disconnected`.

Provider errors are diagnostic state only; deterministic behavior continues.

### brain_probe_result

```json
{
  "type":"brain_probe_result",
  "id":3,
  "ok":true,
  "choice":"focus",
  "latency_ms":87
}
```

or:

```json
{
  "type":"brain_probe_result",
  "id":3,
  "ok":false,
  "error":"provider request failed: ..."
}
```

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

The AI provider never authors this full structure directly. It may choose one behavior label from the deterministic allow-list; the core maps that label into a validated `BehaviorIntent`.

Normal AI results are also tied to a semantic key derived from the editor context they observed. A result that arrives after that context has materially changed is ignored rather than applied stale.

### error / pong

```json
{"type":"error","message":"protocol mismatch"}
{"type":"pong","id":7}
```

## Compatibility rules

- Unknown or malformed messages should be reported and ignored when safe.
- New optional fields may be added without a protocol bump.
- Semantics-breaking changes require a bump.
- A mismatched core must not continue normal planning.
- Provider failures never invalidate the JSONL transport or block editor animation.
- A timed-out provider request remains logically in flight until its late worker reply is drained; callers must not queue overlapping work onto the single provider worker.
