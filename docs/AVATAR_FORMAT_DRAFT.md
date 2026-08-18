# Avatar package format — design draft

> This document defines direction, not a frozen compatibility contract. The built-in avatars are still Lua tables while the external data-only schema is being designed.

## Goal

An avatar is presentation data, not a hard-coded engine type.

The engine should select semantic actions such as `idle`, `inspect`, `walk`, `sleep`, `appear`, or `peek`. The avatar decides how those actions look. A future user should be able to generate or edit an avatar package as ordinary text assets, inspect it in Git, and load it without runtime image assets or arbitrary executable code.

The current implementation supports two renderer kinds:

- **glyph** — preferred/default direction; one to three terminal rows of styled text segments;
- **pixel** — retained half-block indexed-pixel renderer used by the original fox.

The public schema should support both without letting engine behavior depend on species-specific branches.

## Design principles

1. **At most three terminal rows for glyph actors.** Small size is a product constraint, not an optimization target.
2. **Expression over detail.** Faces, gestures, posture, headwear, ears/horns/hair, and effects carry identity.
3. **Semantic color roles.** Frames reference roles such as `outline`, `face`, `effect`, or `alert`; they do not hard-code Neovim highlight group names.
4. **Unicode is optional decoration.** A core identity should not require a fragile exotic glyph.
5. **Actions are semantic.** The brain chooses `inspect`; it never chooses a visible string such as `(•̀_•́)σ`.
6. **Packages are data.** Built-in Lua helpers are temporary authoring convenience, not the final external extension surface.

## Current built-in glyph shape

The built-in `mote` avatar is conceptually equivalent to:

```lua
{
  id = "mote",
  kind = "glyph",
  width = 12,
  height = 3,

  palette = {
    outline = "#F49B48",
    face = "#F4E1BC",
    effect = "#68CDE0",
    success = "#7ACD84",
    alert = "#EB7070",
  },

  frames = {
    idle_1 = {
      rows = {
        {
          { text = "   " },
          { text = "/\\_/\\", role = "outline" },
        },
        {
          { text = "  " },
          { text = "(", role = "outline" },
          { text = " •ω• ", role = "face" },
          { text = ")", role = "outline" },
        },
      },
    },
  },
}
```

A glyph frame may contain one, two, or three rows. Each row is a sequence of text segments. Segments without a role are transparent/default text; segments with a role receive the avatar palette color for that role.

The renderer pads short frames into the avatar's maximum height. This keeps the spatial anchor stable while allowing a one-line run state and a three-line sleep state to share the same avatar.

## Proposed external layout

A future data-only package may look like:

```text
my-avatar/
├── avatar.toml
├── palette.toml
├── animations.toml
├── behavior.toml
├── emotes.toml
└── frames/
    ├── idle.toml
    ├── inspect.toml
    ├── walk.toml
    └── ...
```

The exact file split is not frozen. The important contract is the semantic model, not the extension names.

## Manifest

Tentative direction:

```toml
schema = 1
id = "mote-like"
name = "My Familiar"
renderer = "glyph"

[body]
width = 12
height = 3

[personality]
curiosity = 0.80
energy = 0.60
shyness = 0.15
restlessness = 0.35
attention_to_errors = 0.75
attention_to_writing = 0.55
```

For a pixel avatar:

```toml
renderer = "pixel"

[body]
width = 16
height = 16
```

Personality values are hints in `[0, 1]`. They bias deterministic and model policies; they do not directly execute behavior.

## Glyph frame data

The stable serialization is still open, but it needs to preserve segment boundaries and roles. A TOML-like sketch:

```toml
[[row]]
segments = [
  { text = "   " },
  { text = "/\\_/\\", role = "outline" },
]

[[row]]
segments = [
  { text = "  " },
  { text = "(", role = "outline" },
  { text = " •ω• ", role = "face" },
  { text = ")", role = "outline" },
]
```

Requirements:

- rendered display width of every row must be `<= body.width`;
- glyph frame height must be in `1..3`;
- role references must exist in the palette;
- a segment cannot contain embedded newlines;
- package validation must use terminal display width, not UTF-8 byte length;
- animation frames may intentionally occupy fewer rows than the avatar maximum.

## Pixel frame data

The retained pixel format remains an indexed logical-pixel matrix:

```text
................
...11......11...
...121....121...
..12221..12221..
...
```

`.` means transparent. Other characters refer to palette entries.

Pixel requirements:

- all rows have identical logical width;
- the current half-block renderer requires even logical height;
- unknown palette indices are validation errors.

Pixel support is retained, but it is no longer the default visual direction.

## Palette

Glyph palettes use semantic role names:

```toml
[colors]
outline = "#F49B48"
face = "#F4E1BC"
effect = "#68CDE0"
success = "#7ACD84"
alert = "#EB7070"
```

Pixel palettes may continue to use compact indexed keys.

The engine may later adapt colors against the active colorscheme, but an avatar must remain valid with its declared palette alone.

## Animation graph

Animation is separated from individual frames:

```toml
[animation.idle]
frames = ["idle_01", "idle_01", "blink"]
loop = true

[animation.walk]
frames = ["walk_01", "walk_02"]
loop = true

[animation.appear]
frames = ["spark_01", "compact_01", "idle_01"]
loop = false
next = "idle"
```

The stable format should eventually support per-animation/frame timing rather than forcing every avatar to share one global frame interval.

The engine owns interruption rules. A new intent does not automatically cut the current frame sequence.

## Required semantic actions

The engine should work with semantic action IDs, not species-specific names:

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

An avatar may add showcase actions such as `wave`, `cheer`, or `magic`. Missing optional actions should fall back through declared aliases rather than engine branches such as `if avatar == "fox"`.

## Emotes and overlays

Emotes are semantic IDs:

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

A glyph avatar may express an emote by changing the face, appending a symbol, changing headwear, or adding a tiny effect row. A pixel avatar may use a sprite overlay.

A model never writes the visible glyph/string itself.

## Behavior data

The first public behavior customization should remain declarative:

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

This is intentionally weaker than a scripting language. Lua/WASM behavior extensions remain deferred.

## Validation

Before schema v1, package validation should check:

- manifest/schema version;
- renderer kind;
- logical dimensions;
- glyph row display widths and row count;
- glyph role references;
- pixel palette references and frame dimensions;
- referenced animation frames;
- transition graph targets;
- required action/fallback availability;
- emote references;
- personality ranges.

Invalid avatar data must fail closed without taking Neovim down.

## AI-generated avatars

The format is deliberately text-first so an AI/code agent can generate and revise an avatar in normal source-control workflow. Generation happens outside runtime.

The runtime model, if enabled, still cannot synthesize avatar strings, sprites, or executable logic while the editor is running.
