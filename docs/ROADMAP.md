# Roadmap

This roadmap is ordered to avoid building an AI system before the underlying companion is enjoyable.

## M0 — repository and contracts

- [x] public repository and MIT license
- [x] architecture document
- [x] Lua/Rust boundary ADR
- [x] terminal-native renderer ADRs
- [x] avatar-package ADR
- [x] versioned JSONL protocol
- [x] lazy.nvim-oriented plugin skeleton

## M1 — terminal character vertical slice

Goal: prove a familiar can be expressive while staying tiny enough to coexist with code.

- [x] indexed half-block pixel renderer
- [x] provisional pixel fox
- [x] real-terminal visual evaluation of the pixel direction
- [x] real-terminal evaluation of Unicode contour/subcell directions
- [x] adopt a 1–3 row glyph actor as the default visual language
- [x] built-in abstract `mote` avatar
- [x] semantic color roles for glyph frames
- [x] retain the pixel fox as an alternate avatar
- [x] safe right-side placement
- [x] low-FPS animation timer
- [x] non-blocking commands/lifecycle
- [ ] tune Mote face/gesture grammar from real Neovim screenshots
- [ ] add more posture-aware transitions without increasing the three-row limit
- [ ] add a setup/preview flow for avatar and terminal compatibility

## M2 — continuity and editor world

Goal: make the familiar feel like an inhabitant rather than a widget.

- [x] bounded editor snapshot structure
- [x] buffer-switch activity tracking
- [x] sidecar lifecycle scaffold
- [x] deterministic Rust policy scaffold
- [x] short relocation uses walk/run instead of coordinate jumps
- [x] long relocation uses vanish/appear
- [ ] occupancy map beyond simple right-side whitespace
- [ ] path planning and movement interruption rules
- [ ] make `peek`/edge states real spatial behavior
- [ ] richer diagnostic attention targets
- [ ] Markdown heading/paragraph context
- [ ] VimTeX/LaTeX section/environment context
- [ ] workspace tree/open-buffer summary
- [ ] build/test integration hooks

## M3 — avatar package v1

- [ ] move built-in glyph frames out of executable Lua into a stable text asset format
- [ ] manifest schema with renderer kind
- [ ] semantic glyph palette schema
- [ ] retained indexed-pixel palette schema
- [ ] animation graph schema
- [ ] emote/overlay schema
- [ ] personality parameters
- [ ] validation tool in Rust
- [ ] example second glyph avatar with a different silhouette grammar
- [ ] example pixel avatar to prove dual-renderer compatibility

## M4 — tiny brain benchmark

Only start after M1/M2 are pleasant without AI.

- [ ] PetBench scenario corpus
- [ ] constrained intent schema
- [ ] benchmark ~100M-400M local models on Apple Silicon
- [ ] measure RSS, latency, energy impact, and behavior quality
- [ ] select inference backend behind a Rust trait
- [ ] keep deterministic RuleBrain as mandatory fallback

## M5 — distribution

- [ ] macOS arm64 prebuilt `familiar-core`
- [ ] release download/verification path
- [ ] remove Rust toolchain requirement for normal users
- [ ] version avatar packages and protocol
- [ ] only then evaluate non-lazy.nvim installation docs and broader OS support
