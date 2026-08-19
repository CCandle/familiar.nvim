# ADR 0005: Time-domain presentation engine

## Status

Accepted for the glyph-familiar development branch.

## Context

The first runtime advanced movement by a fixed number of terminal cells on a fixed global frame timer. With a 125 ms frame interval and one-row vertical step, travel time grew directly with screen distance. Long relocation after scrolling could therefore take seconds, and simply increasing the frame rate would also multiply expensive buffer/extmark redraw work.

Real-terminal MotionLab testing showed a materially better experience with 60 FPS active motion, a roughly 250 ms total relocation budget, cubic ease-out, automatic sparse trail, and position stickiness. 120 FPS was useful as an explicit high-refresh option; 30 FPS was acceptable as an economy fallback.

Mature Neovim animation implementations also converge on several useful principles: actual elapsed time should drive animation, total duration should be a first-class quantity, stale motion should be retargeted instead of queued, and high-frequency drawing should be limited to the cheapest state that actually changed.

## Decision

`familiar.nvim` uses a time-domain presentation engine.

1. Spatial motion is represented by start time, deadline, origin, destination, locomotion class, and easing.
2. Ordinary relocation uses a fixed total duration rather than a fixed delay per terminal cell.
3. Distance selects walk/run/dash/warp presentation but does not make ordinary movement arbitrarily long.
4. In-flight target changes replace the destination and preserve the current motion burst deadline, with only a bounded late-retarget extension.
5. The actor's content, position, and trail/effects are independently rendered and cached.
6. The high-frequency timer exists only while spatial motion or its residual trail is active.
7. Expression animation uses explicit millisecond keyframes and low-frequency scheduled events rather than repeated frames on the motion clock.
8. Safe current placement is sticky. Movement is gated by semantic utility and penalties for distance, recent movement, current motion, and editor-mode policy.
9. Mode-aware interaction changes movement and ambient budgets as well as pose semantics.

## Consequences

### Positive

- Page and long-screen relocation completes in a predictable amount of real time.
- Missed callbacks do not force the familiar to replay stale visual frames.
- Repeated scroll events converge on the latest target instead of producing a movement queue.
- 60/120 FPS operation does not imply 60/120 full actor-buffer rewrites per second.
- The character can remain quiet during sustained editing while retaining richer ambient behavior in normal mode.
- Skins can author meaningful action timing without knowing the runtime's motion FPS.

### Costs

- The presentation runtime is more stateful than a fixed sprite loop.
- Terminal-cell quantization means logical 60/120 FPS motion may not produce a distinct visible position every tick; the renderer must explicitly suppress redundant updates.
- Behavior, motion, expression, transition, and trail interruption rules need tests because they can overlap.
- Default timings remain perceptual UX parameters and must continue to be validated in real terminals.

## Rejected alternatives

### Increase the old frame rate only

Rejected because it retains distance-dependent duration and multiplies expensive redraw work.

### Spring physics for all locomotion

Rejected as the default because a companion benefits from predictable arrival time. Spring-like effects may later exist as optional presentation styles, but they should not control core relocation semantics.

### Full-character smear trail

Rejected because duplicating or stretching the actor harms readability. Sparse terminal-native residues communicate speed with much lower visual noise.

### Always choose the mathematically best placement

Rejected because small placement-score improvements can create constant nuisance motion. Safe-position stickiness is a product behavior, not merely an optimization.
