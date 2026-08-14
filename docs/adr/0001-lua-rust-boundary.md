# ADR 0001: thin Neovim frontend, lifecycle-bound Rust sidecar

- Status: Accepted
- Date: 2026-08-14

## Context

The plugin needs tight Neovim integration, animation, spatial planning, persistent world state, and eventually small-model inference. Implementing everything in Lua would couple expensive/non-editor work to the Neovim process. Implementing everything as a Rust remote plugin would make ordinary Neovim API work needlessly cumbersome.

A permanent macOS daemon would also waste resources whenever Neovim is not in use.

## Decision

Use a hybrid architecture:

- Lua owns Neovim API integration and final extmark display.
- Rust runs as a child process of the plugin and owns non-trivial world/behavior computation.
- Rust is started on demand and terminated with the Neovim instance.
- IPC starts as JSONL over stdio.
- A deterministic Lua/Rust fallback remains available when the sidecar or future model is unavailable.

## Consequences

Positive:

- no permanent background process;
- model/runtime memory is isolated from Neovim;
- crash/failure boundary is clearer;
- Rust can evolve independently from the Neovim-facing Lua API;
- IPC is inspectable during development.

Costs:

- two-language repository;
- binary distribution eventually needs releases per platform;
- protocol/versioning becomes a maintained interface.

## Rejected alternatives

### Pure Lua

Suitable for the renderer spike but not preferred for eventual inference and richer planning.

### Pure Rust Neovim remote plugin

Technically viable, but makes native Neovim concepts less ergonomic and increases development friction without clear benefit.

### Permanent daemon / LaunchAgent

Rejected because the companion should consume zero resources when Neovim is not running.
