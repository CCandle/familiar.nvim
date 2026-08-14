# Editor world model

## Purpose

The familiar should understand enough of the editor to behave coherently in coding, Markdown, LaTeX, note-taking, and mixed project sessions. It should not mirror every keystroke or dump an entire repository into a model.

The world model therefore converts raw Neovim activity into bounded, semantic state at several time scales.

## Layers

### Presentation state — fast

Used by deterministic motion/rendering, never a reason by itself to run a model:

- active window and viewport geometry;
- cursor screen/buffer position;
- current animation/transition;
- current familiar position and target;
- safe/occupied screen regions;
- mode and scrolling state.

### Activity state — aggregated

Examples:

- current typing burst duration/rate class;
- idle duration;
- recent buffer-switch count;
- recent save count;
- scroll/jump/search bursts;
- undo/redo activity;
- diagnostic trend;
- build/test/debug result when integrations are available.

Raw keys are not retained. The familiar cares that the user is in a sustained writing burst, not that the user typed a particular sequence of characters.

### Workspace state — slow

A bounded workspace summary may contain:

- root/project name;
- shallow tree (for example depth <= 3 and a node budget);
- open buffers;
- recently visited buffers;
- lightweight Git status summary;
- project type hints inferred from files already visible to Neovim.

Large/vendor/generated directories should be omitted. The tree is context, not a file indexer.

### Current-buffer semantic context

A future richer snapshot may contain a small bounded context slice around the cursor plus structural metadata.

For Markdown:

- heading path;
- paragraph/list/code-block context;
- note/link navigation events when available;
- a small visible/near-cursor text slice.

For LaTeX:

- part/chapter/section/subsection path;
- current environment (equation, figure, table, etc.) when reliably available;
- compilation state;
- a small near-cursor text slice.

For source code:

- current symbol/function when available;
- diagnostics near the cursor;
- a bounded near-cursor text slice;
- test/build/debug state from explicit integrations.

The first implementation currently sends only basic buffer/viewport/diagnostic/activity data. Structural and content context is a planned expansion, not a current capability.

## Semantic event stream

Events are deliberately higher level than key presses. Candidate vocabulary includes:

```text
buffer_enter
buffer_leave
save
focus_started
focus_ended
idle_started
heading_changed
section_changed
environment_entered
search_started
search_finished
diagnostics_increased
diagnostics_decreased
build_started
build_succeeded
build_failed
test_succeeded
test_failed
```

Some events come directly from Neovim; others are derived by the Rust world model from repeated snapshots.

## Text-work behavior

Long-form writing is a first-class mode, not a fallback for when no compiler exists.

A useful default policy is deliberately quiet:

1. entering a new document/section may briefly raise curiosity;
2. sustained typing lowers visible activity and favors a focused idle animation;
3. short pauses allow subtle look/tail/blink behavior;
4. longer idle allows rest/sleep;
5. repeated rapid buffer/note switching may trigger a curious/confused attention behavior;
6. no event should create repeated celebration spam merely because autosave fires.

The familiar should learn when **not** to move.

## Attention targets

The engine should represent attention independently from position:

```text
cursor
current_heading
current_section
nearest_diagnostic
git_hunk
search_match
screen_edge
quiet_corner
none
```

This lets an avatar sit in one place while looking at a target, or deliberately approach a target when space permits.

## Content budget

Before a model call, context must be reduced to a predictable budget. A target envelope for the first tiny-model experiments is roughly hundreds of tokens, not thousands.

Suggested priorities:

1. current activity/intent state;
2. current structural context;
3. recent semantic events;
4. open/recent buffer summary;
5. shallow workspace tree;
6. only then a small current-buffer text slice.

No full repository or full buffer is sent by default.

## Privacy and locality

The intended brain is local. The core architecture does not require a network service. Future remote-model integrations, if ever added, must be explicit opt-in and must define exactly what editor content leaves the machine.
