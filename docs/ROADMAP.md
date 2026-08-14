# Roadmap

This roadmap is ordered to avoid building an AI system before the underlying companion is enjoyable.

## M0 — repository and contracts

- [x] public repository and MIT license
- [x] architecture document
- [x] Lua/Rust boundary ADR
- [x] renderer ADR
- [x] avatar-package ADR
- [x] versioned JSONL protocol
- [x] lazy.nvim-oriented plugin skeleton

## M1 — pixel fox vertical slice

Goal: prove that terminal-native pixel animation is visually worthwhile.

- [x] indexed sprite representation
- [x] half-block renderer
- [x] transparent-run rendering
- [x] provisional fox frames
- [x] safe right-side placement
- [x] low-FPS animation timer
- [x] non-blocking commands/lifecycle
- [ ] verify appearance in iTerm2 with the primary font/theme
- [ ] tune sprite proportions/colors from real screenshots
- [ ] add compact and peek bodies
- [ ] expand idle/walk/run/appear/vanish transition frames

## M2 — continuity and editor world

Goal: make the familiar feel like an inhabitant rather than a widget.

- [x] bounded editor snapshot structure
- [x] buffer-switch activity tracking
- [x] sidecar lifecycle scaffold
- [x] deterministic Rust policy scaffold
- [ ] occupancy map beyond simple right-side whitespace
- [ ] path planning and movement interruption rules
- [ ] animated full/compact/peek transitions
- [ ] richer diagnostic attention targets
- [ ] Markdown heading/paragraph context
- [ ] VimTeX/LaTeX section/environment context
- [ ] workspace tree/open-buffer summary
- [ ] build/test integration hooks

## M3 — avatar package v1

- [ ] move default fox out of Lua code into a stable text asset format
- [ ] manifest schema
- [ ] palette schema
- [ ] animation graph schema
- [ ] emote library schema
- [ ] personality parameters
- [ ] validation tool in Rust
- [ ] example second avatar to prove the abstraction is real

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
