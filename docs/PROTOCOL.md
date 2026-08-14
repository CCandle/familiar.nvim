# Lua ↔ Rust protocol

## Transport

The initial protocol is JSON Lines over the child process stdin/stdout.

- one JSON object per line;
- UTF-8;
- protocol version is negotiated with `hello`;
- stdout is protocol-only;
- diagnostic logging belongs on stderr;
- malformed messages must not crash Neovim.

Protocol version: **1**.

## Client to core

### hello

```json
{"type":"hello","protocol":1,"client":"familiar.nvim"}
```

### snapshot

```json
{
  "type":"snapshot",
  "seq":12,
  "snapshot":{
    "mode":"i",
    "buffer":{"id":4,"name":"notes.md","filetype":"markdown","modified":true,"line_count":310},
    "viewport":{"width":128,"height":43,"cursor_row":82,"cursor_col":16,"topline":60,"botline":102,"line_display_widths":[33,74,0]},
    "diagnostics":{"errors":0,"warnings":1},
    "activity":{"idle_ms":90,"typing":true,"buffer_switches_10s":0}
  }
}
```

The viewport line-width list is bounded by the Lua frontend; it is not intended to mirror entire buffers.

### event

```json
{"type":"event","seq":13,"event":{"kind":"buffer_enter","buffer":8}}
```

The event vocabulary is intentionally open during early development, but payloads remain structured and bounded.

### ping / shutdown

```json
{"type":"ping","id":7}
{"type":"shutdown"}
```

## Core to client

### ready

```json
{"type":"ready","protocol":1,"core":"familiar-core","version":"0.1.0"}
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
    "mood":"curious",
    "emote":"question",
    "duration_ms":6000
  }
}
```

Current intents are produced by a deterministic rule policy. The same contract is intended to constrain future model output.

### error / pong

```json
{"type":"error","message":"protocol mismatch"}
{"type":"pong","id":7}
```

## Compatibility rules

- Unknown message types should be reported and ignored when safe.
- New optional fields may be added without a protocol bump.
- Semantics-breaking changes require a protocol bump.
- A core with a mismatched protocol must not continue normal planning.
