# ADR 0004: Make a 1–3 row glyph actor the default visual language

- Status: Accepted
- Date: 2026-08-18
- Supersedes: ADR 0002 as the default renderer choice; the pixel renderer remains supported

## Context

The first working vertical slice used a 16×16 indexed-pixel fox rendered with Unicode half blocks. That implementation proved several useful engine properties: transparent floating rendering, safe placement, animation sequencing, relocation, and a replaceable avatar module.

Real-terminal visual testing exposed a different product problem.

At the small footprint appropriate for a Neovim companion, the pixel avatar looked coarse. Increasing the sprite size improved detail but consumed too much editor space. A second experiment treated Unicode box/legacy-computing characters as contour strokes. It avoided raster blocks but required too many columns and rows for very little character expression; the result read more like a geometric icon than a living familiar.

The strongest tests were highly abstract character forms: a compact face, a few silhouette anchors such as ears/headwear, optional hands, posture, and small effect glyphs. Human perception extracts emotion and identity from these symbols with far fewer terminal cells than either a sprite or a complete contour drawing.

## Decision

The default familiar will use a **glyph actor** with these constraints:

1. A frame occupies at most **three terminal rows**.
2. Frames are composed from styled text segments rather than logical pixels.
3. Identity is carried by a small grammar:
   - face/eyes/mouth;
   - optional ears, hair, horns, or headwear;
   - hands/gesture;
   - posture;
   - tiny motion/emote effects.
4. One-line, two-line, and three-line frames may coexist in one avatar. Short frames are padded onto a stable transparent render surface.
5. The engine continues to select semantic actions (`idle`, `inspect`, `walk`, `sleep`, etc.). It never generates visible kaomoji strings itself.
6. Unicode beyond common terminal glyphs is decorative, not structurally required.
7. The existing half-block pixel renderer and fox avatar remain available as an alternate rendering path.

The initial built-in glyph actor is named `mote`. The name intentionally does not define a species.

## Why not pure kaomoji only?

Pure one-line kaomoji are extremely expressive but can collapse into a status icon. The chosen format keeps the same information density while allowing one or two extra rows for silhouette and posture when they materially improve the character.

For example, the same identity may appear as:

```text
(•ω•)ﾉ
```

or:

```text
   /\_/\
  ( •ω• )
```

or:

```text
   /\_/\
  ( -ω- )___
  ──────────
```

The avatar is therefore not a fixed cat drawing. The ears are one optional silhouette primitive among many possible avatar designs.

## Why not Symbols for Legacy Computing as the core?

Testing showed that legacy-computing wedges and subcell glyphs vary significantly in stroke weight and font fallback. They are useful as optional local marks but are too fragile to define the default character silhouette.

Braille-like dots remain useful for particles, warp residue, sleep marks, or other effects because failure there does not destroy identity.

## Consequences

### Positive

- Much higher emotional bandwidth per terminal cell.
- The familiar can remain tiny enough not to compete with code.
- State changes are cheap: replacing a few glyphs can communicate blink, focus, surprise, annoyance, sleep, or celebration.
- Avatar creation becomes text-first and diff-friendly.
- The visual language is naturally terminal-native rather than an image simulated inside a terminal.
- Existing runtime semantics and movement logic remain reusable.

### Negative

- Visual quality depends on terminal/font rendering of some Unicode characters.
- Display width must be validated with terminal-cell semantics rather than UTF-8 byte length.
- Exact aesthetics cannot be proven by headless CI.
- Glyph art requires manual visual design discipline; more available Unicode does not automatically mean better art.

### Compatibility

The pixel renderer is not deleted. Existing `fox` data remains loadable, and the renderer dispatches by avatar kind. This keeps the proven half-block path available while making the glyph actor the product default.

## Follow-up

- Tune Mote in real iTerm2/Neovim sessions.
- Make `peek` and edge interaction first-class spatial behaviors.
- Add declarative external glyph-avatar packages.
- Add a setup/preview flow that can show the selected familiar and detect obvious display-width/font problems without pretending that Neovim can detect every missing font glyph.
