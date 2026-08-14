# ADR 0002: terminal-native indexed pixel renderer

- Status: Accepted for the primary renderer
- Date: 2026-08-14

## Context

The desired visual is animated pixel art, not emoji-only decoration and not a floating image panel. iTerm2 supports image protocols, but tying the core experience to PNG/GIF/image escape sequences complicates scrolling, cleanup, positioning, and portability.

## Decision

Represent avatar art as indexed logical pixels and render it in a tiny borderless, non-focusable Neovim floating window used only as a screen-space render surface. Unicode half-block characters carry the logical pixels, and extmark highlights inside the scratch buffer carry the palette colors.

Two logical vertical pixels map to one terminal cell. Palette pairs become Neovim highlight groups. Fully transparent cells produce no extmark output.

The render surface is deliberately non-interactive (`focusable=false`, mouse passthrough) and has no border or user-facing chrome. It solves an important problem with wrapped Markdown/LaTeX: the sprite is positioned in screen cells rather than being tied to buffer-line geometry.

The primary renderer therefore requires true color but does not require runtime image files or terminal image protocols.

## Consequences

Positive:

- pixel assets are tiny and diffable;
- animation frames can be generated/edited as text data;
- rendering participates in normal Neovim lifecycle;
- no PNG/JPG decoder or image daemon is required;
- avatar packs can remain simple and AI-authorable later.

Limitations:

- terminal cell geometry controls final aspect ratio;
- a partially transparent half-cell cannot reveal the exact underlying glyph; safe placement is therefore important;
- complex scenes are out of scope;
- final quality must be judged in the actual terminal/font/theme combination.

## Rejected alternative

The iTerm2 inline image protocol remains an optional future experiment, not the primary renderer.
