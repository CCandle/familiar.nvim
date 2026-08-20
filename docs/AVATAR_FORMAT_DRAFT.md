# Skin package format — design draft

> This document defines direction, not a frozen compatibility contract. The built-in skins are still Lua tables while the external data-only schema is being designed. Earlier documentation called these packages "avatars"; `avatar` remains a compatibility term in code/config while the user-facing concept moves to **skin**.

## Goal

A skin is presentation data, not a hard-coded engine type.

The runtime selects semantic states such as `idle`, `focus`, `visual`, `inspect`, `sleep`, or locomotion classes such as `walk` and `dash`. The skin decides how those semantics look and how its own micro-actions are timed.

The current implementation supports two renderer kinds:

- **glyph** — preferred/default direction; one to three terminal rows of styled text segments;
- **pixel** — retained half-block indexed-pixel renderer used by the original fox.

The public schema should support both without letting runtime behavior depend on species-specific branches.

## Design principles

1. **At most three terminal rows for glyph actors.** Small size is a product constraint.
2. **Expression over detail.** Faces, gestures, posture, headwear, ears/horns/hair, and tiny effects carry identity.
3. **Timing is part of the skin.** A blink and a stretch do not share one global sprite interval.
4. **Motion timing is not part of the skin.** The engine owns wall-clock relocation; the skin only supplies walk/run/dash poses.
5. **Semantic color roles.** Frames reference roles such as `outline`, `face`, `effect`, or `alert` rather than Neovim highlight group names.
6. **Unicode is optional decoration.** Core identity should not depend on one fragile exotic glyph.
7. **Actions are semantic.** A brain chooses `inspect`; it never chooses the visible string `(•̀_•́)σ`.
8. **Packages should become data-only.** Built-in Lua helpers are authoring convenience, not the intended untrusted external extension surface.

## Current built-in glyph shape

Mote v2 is conceptually equivalent to:

```lua
{
  id = "mote",
  kind = "glyph",
  version = 2,
  width = 14,
  height = 3,

  palette = {
    outline = "#F49B48",
    face = "#F4E1BC",
    effect = "#68CDE0",
    success = "#7ACD84",
    alert = "#EB7070",
    muted = "#9C968D",
  },

  frames = {
    idle = {
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

  poses = {
    idle = "idle",
    focus = "focus",
    visual = "visual",
    operator = "operator",
  },

  motion = {
    walk = { "walk_1", "walk_2" },
    run = { "run_1", "run_2" },
    dash = { "dash_1", "dash_2" },
  },

  animations = {
    blink = {
      steps = {
        { frame = "blink", duration_ms = 70 },
        { frame = "idle", duration_ms = 90 },
      },
    },
  },
}
```

A glyph frame may contain one, two, or three rows. Each row is a sequence of text segments. Segments without a role use default/transparent presentation; segments with a role receive the skin palette color for that role.

The renderer pads short frames into the skin's maximum height. This keeps the spatial anchor stable while allowing a compact one-line motion pose and a three-line rest pose to share one render surface.

## Poses, motion poses, and animations

These are deliberately separate concepts.

### Semantic poses

`poses` maps long-lived runtime semantics to a stable frame:

```lua
poses = {
  idle = "idle",
  focus = "focus",
  visual = "visual",
  command = "command",
}
```

Mode-aware behavior can therefore change skins without adding species-specific branches to the runtime.

### Motion poses

`motion` maps locomotion class to a short cycling list of frames:

```lua
motion = {
  walk = { "walk_1", "walk_2" },
  run = { "run_1", "run_2" },
  dash = { "dash_1", "dash_2" },
}
```

The presentation engine determines the actor's continuous logical position and total movement duration. The skin controls only what the character looks like while that motion is underway.

### Timed animations

Discrete expressions use explicit millisecond keyframes:

```lua
animations = {
  ear_twitch = {
    steps = {
      { frame = "ear_twitch", duration_ms = 110 },
      { frame = "idle", duration_ms = 110 },
      { frame = "ear_twitch", duration_ms = 90 },
      { frame = "idle", duration_ms = 120 },
    },
  },
}
```

`duration_ms` may eventually allow either a single duration or a bounded `{min,max}` range for intentionally irregular idle actions.

The old built-in `frames = {...}` animation form remains accepted for compatibility and is interpreted with a fallback frame duration.

## Proposed external layout

A future data-only package may look like:

```text
my-skin/
├── skin.toml
├── palette.toml
├── poses.toml
├── motion.toml
├── animations.toml
└── frames/
    ├── idle.toml
    ├── focus.toml
    ├── inspect.toml
    └── ...
```

The exact file split is not frozen. The important contract is the semantic model, not the extension names.

## Manifest direction

```toml
schema = 1
id = "mote-like"
name = "My Familiar"
renderer = "glyph"

[body]
width = 14
height = 3

[personality]
curiosity = 0.80
energy = 0.60
shyness = 0.15
restlessness = 0.35
```

Personality values are hints in `[0,1]`. They may bias deterministic or AI policy later; they do not directly execute presentation logic.

## Glyph-frame serialization

A TOML-like sketch:

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
- short animation frames may occupy fewer rows than the skin maximum.

## Pixel-frame compatibility

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

Pixel support remains useful for experimentation, but it is no longer the default visual direction.

## Semantic vocabulary and fallback

The runtime should converge on a compact stable vocabulary, for example:

```text
idle
focus
visual
operator
replace
command
inspect
curious
sleep
walk
run
dash
appear
vanish
peek
```

A skin may add showcase/micro-actions such as:

```text
blink
glance
ear_twitch
stretch
wave
cheer
magic
save
success
```

Missing optional actions should eventually fall back through declared aliases instead of engine branches such as `if skin == "mote"`.

## Interruptibility

The final external contract should allow a small interruption policy for discrete actions:

```text
immediate
safe_point
finish
```

The engine remains authoritative. Mode changes, safety relocation, and visibility transitions may override ordinary ambient actions. A short protected transition such as disappear/appear should not be torn apart by a blink event.

## Validation

Before schema v1, validation should cover:

- manifest/schema version;
- renderer kind and dimensions;
- glyph row display widths/count and role references;
- pixel palette references and dimensions;
- pose frame references;
- motion frame references;
- timed-animation frame references and valid positive durations;
- fallback/alias targets;
- personality ranges.

Invalid external skin data must fail closed without taking Neovim down.

## AI-generated skins

The format remains text-first so an AI/code agent can generate and revise a skin in normal source-control workflow. Generation happens outside runtime.

An enabled behavior model still cannot synthesize visible glyph strings, palette data, or executable skin logic while the editor is running.
