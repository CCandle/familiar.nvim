# Development

## Local checkout with lazy.nvim

During development, point lazy.nvim directly at the checkout instead of repeatedly installing from GitHub:

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

Then `:Lazy reload familiar.nvim` is useful for package metadata, but animation/runtime changes should be tested with a full Neovim restart because timers, jobs, autocmds, and Lua module state can survive ad-hoc sourcing.

## Rust core

```sh
cargo fmt --all
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo build --release -p familiar-core
```

The binary is expected at:

```text
target/release/familiar-core
```

Set `FAMILIAR_CORE_BIN` to override discovery during experiments.

## Neovim smoke test

```sh
nvim --headless -u tests/minimal_init.lua -l tests/smoke.lua
nvim --headless -u tests/minimal_init.lua -l tests/placement.lua
```

The smoke test checks module loading, avatar validation, half-block frame conversion, and disabled setup. The placement test verifies ordinary and virtual-text occupancy, safe motion paths, trail suppression, and text-change invalidation. Final visual rendering still requires an interactive Neovim session.

## Visual test checklist

Use the real terminal/font/theme combination. For the initial macOS target:

1. open a normal code buffer with `nowrap`;
2. open Markdown/TeX with wrapping enabled;
3. verify the render surface is visually transparent outside the sprite;
4. resize the window repeatedly;
5. split windows and move between them;
6. switch buffers quickly;
7. type continuously and verify animation does not introduce input lag;
8. scroll through long wrapped paragraphs;
9. confirm the companion hides rather than covering dense text;
10. exit Neovim and confirm `familiar-core` is gone.

## Architecture rule

Do not add AI inference until the deterministic companion is already pleasant. A model is allowed to improve behavior selection; it is not allowed to compensate for a weak renderer, weak spatial logic, or incomplete animation transitions.
