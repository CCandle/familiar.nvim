# Avatar package format — design draft

> This document defines the direction, not a frozen compatibility contract. The first fox is still embedded in Lua while the renderer is validated in a real terminal.

## Goal

An avatar is not a hard-coded engine type. It is a data package that can change appearance, animation timing, available actions, emotes, and bounded personality tendencies without changing the familiar engine.

A future user should be able to ask an AI/code agent to create an avatar package, inspect the generated text assets in Git, and load it without producing PNG/JPG runtime assets or arbitrary executable code.

## Proposed layout

```text
my-avatar/
├── avatar.toml
├── palette.toml
├── animations.toml
├── behavior.toml
├── emotes.toml
└── sprites/
    ├── idle_01.pix
    ├── idle_02.pix
    ├── walk_01.pix
    ├── walk_02.pix
    └── ...
```

## Manifest

Tentative shape:

```toml
schema = 1
id = "fox"
name = "Fox Familiar"

[body.full]
width = 16
height = 16

[body.compact]
width = 8
height = 8

[personality]
curiosity = 0.80
energy = 0.60
shyness = 0.15
restlessness = 0.35
attention_to_errors = 0.75
attention_to_writing = 0.55
```

Personality values are hints in `[0, 1]`. They bias deterministic and model policies; they do not directly execute behavior.

## Sprite data

A `.pix` file is an indexed logical-pixel matrix. Example:

```text
................
...11......11...
...121....121...
..12221..12221..
...
```

`.` means transparent. Other characters refer to palette entries. The exact stable palette-key alphabet will be chosen before avatar schema v1 is frozen.

Requirements:

- all rows in a frame have identical logical width;
- height must be compatible with the selected renderer (the half-block renderer currently wants an even height);
- unknown palette indices are validation errors;
- assets are data only and cannot execute code.

## Palette

Tentative example:

```toml
[colors]
"1" = "#393552"
"2" = "#c47d5b"
"3" = "#e8ad82"
"4" = "#191724"
"5" = "#eb6f92"
"6" = "#f6c177"
```

The engine may later support palette adaptation against the current colorscheme, but an avatar must remain valid with its declared palette alone.

## Animation graph

Animation is separated from individual frames.

```toml
[animation.idle]
frames = ["idle_01", "idle_01", "idle_02"]
loop = true

[animation.walk]
frames = ["walk_01", "walk_02"]
loop = true

[transition.full_to_peek]
animation = "leave_edge"
next_body = "peek"
```

The stable format should eventually support per-animation/frame timing rather than forcing every avatar to share one global frame interval.

The engine owns interruption rules. A new intent does not automatically cut the current frame sequence: transitions may finish, blend into a compatible state, or be interrupted only at declared safe points.

## Required semantic actions

The engine should work with semantic action IDs, not fox-specific names. A full avatar will eventually provide reasonable visual implementations for a core vocabulary such as:

```text
idle
focus
look
inspect
walk
run
hop
sleep
wake
appear
vanish
enter_edge
leave_edge
peek
```

An avatar may add optional actions. Missing optional actions fall back through declared aliases rather than engine branches such as `if avatar == fox`.

## Emotes

Emotes are also declared assets. The brain selects an ID only:

```text
none
question
exclaim
ellipsis
sparkle
sweat
sleep
heart
music
check
cross
book
fire
```

An avatar decides how an emote looks: a Unicode symbol, tiny pixel overlay, or small animation. A model never writes the visible glyph/string itself.

## Behavior data

The first public behavior customization should be declarative rather than arbitrary Lua/Rust execution.

Possible shape:

```toml
[behavior.inspect_error]
weight = 0.8
requires = ["diagnostic_error"]
preferred_action = "inspect"
preferred_emote = "question"

[behavior.sleep]
weight = 0.6
idle_after_seconds = 120
preferred_action = "sleep"
```

This is intentionally weaker than a scripting language. Lua/WASM behavior extensions are deferred until there is a real use case and a compatibility/security model.

## Validation

Before schema v1, Rust should gain a package validator that checks:

- manifest/schema version;
- dimensions and frame consistency;
- palette references;
- referenced animation frames;
- transition graph targets;
- required action/fallback availability;
- emote references;
- personality ranges.

Invalid avatar data must fail closed without taking Neovim down.

## AI-generated avatars

The format is deliberately text-first so an AI/code agent can generate and revise an avatar in normal source-control workflow. Generation happens outside the runtime. The runtime model, if enabled, still cannot synthesize sprite data or executable logic while the editor is running.
