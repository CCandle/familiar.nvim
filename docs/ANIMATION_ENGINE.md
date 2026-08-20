# Presentation and animation engine

This document defines the time-domain presentation model used by `familiar.nvim`.

The goal is not merely to make a floating glyph move. The goal is to make a tiny terminal character feel responsive while remaining quiet enough to live beside real editing work.

## Design inputs

The first defaults were chosen after a small real-terminal MotionLab rather than from frame-count intuition. The useful baseline was:

- 60 FPS for active spatial motion;
- 250 ms for an ordinary relocation;
- cubic ease-out;
- automatic sparse motion trail;
- position stickiness enabled;
- 120 FPS as an explicit high-refresh option;
- 30 FPS as an economy/fallback profile.

The architecture also borrows proven ideas from terminal/Neovim animation projects without copying their visual effects:

- `smear-cursor.nvim`: actual elapsed-time integration, in-flight retargeting, lag-aware scheduling, reusable floating windows;
- `snacks.nvim`: total-duration animation, high refresh-rate support, replacement of stale animations, accelerated repeated motion;
- `mini.animate`: separation of path/steps from timing and asynchronous non-blocking presentation;
- `neoscroll.nvim`: total duration as a first-class property rather than one fixed delay per line;
- terminal-pet/Tamagotchi projects: a mostly calm idle state punctuated by rare fidgets is more alive than a constantly changing sprite.

## Core invariant: time owns animation

Animation state is a function of wall-clock progress. Draw calls are best effort.

A relocation is represented by a plan similar to:

```text
from
 target
 started_ms
 deadline_ms
 kind
 easing
```

At an active animation tick:

```text
progress = (now - started) / (deadline - started)
position = lerp(from, target, easing(progress))
```

The engine never means "move two cells per frame". A delayed callback must advance to the position implied by real elapsed time rather than making the animation itself last longer.

This gives two important properties:

1. animation duration is stable when Neovim occasionally misses a visual update;
2. travel time does not grow linearly with terminal-cell distance.

## Active refresh rate

`animation.fps` is a ceiling for active spatial animation, not a permanent heartbeat.

The default profile is 60 FPS. A 120 FPS profile exists for high-refresh displays, and a 30 FPS economy profile exists for constrained environments.

When nothing is moving, there is no 60/120 Hz actor redraw loop. Idle expression is scheduled as discrete events such as blink or glance.

Even while active, terminal quantization provides another natural optimization: if two logical samples round to the same terminal cell, the renderer does not issue another position update.

## Fixed-duration locomotion

Ordinary relocation defaults to 250 ms regardless of distance. Distance changes the *presentation class*, not the amount of time spent taking one-cell steps.

Current classes are:

- `walk`: short relocation;
- `run`: medium relocation;
- `dash`: long but still visually traversable relocation;
- `warp`: very large relocation, represented by disappear/appear rather than an implausibly fast walk.

The default thresholds are deliberately configurable and remain subject to real-terminal tuning.

## Retargeting

A character must follow the latest editor state, not execute a queue of stale coordinates.

When the target changes during motion:

- the previous destination is replaced immediately;
- the actor starts the new segment from its current interpolated position;
- the existing burst deadline is preserved;
- only a very late retarget may extend the deadline, and only by a bounded amount.

This is especially important for repeated scrolling and page movement. Three quick page-down actions should look like one continuous chase toward the latest safe location, not three queued trips.

## Stickiness and motion utility

A mathematically better placement is not automatically a better user experience.

Before relocating, the runtime asks two questions:

1. Is the current position still safe?
2. Is the new position useful enough to justify visible movement?

If the current position remains safe, candidate motion is evaluated using a utility function with penalties for:

- travel distance;
- having moved very recently;
- already being in motion;
- the current editor mode's motion bias.

The semantic reason for movement contributes positive utility. Safety overrides the gate: an unsafe current position may always relocate or hide.

This is intentionally hysteretic. The familiar should not oscillate because a newly computed candidate is only marginally better than the current place.

## Renderer channels

The renderer treats actor content, actor position, and transient effects as separate channels.

### Actor content

Changes only when the visible pose/frame changes. It may require buffer text and highlight updates.

### Actor position

Changes only the reusable actor float configuration. It must not rebuild frame text or extmarks.

### Effects and trail

Use a tiny reusable pool of one-cell floats. They never duplicate the whole actor.

This separation is what makes 60/120 FPS practical: high-frequency motion should usually be a cheap window-position update, not a complete glyph rerender.

## Sparse trail language

The trail is not a stretched copy of the character and not a general-purpose cursor smear.

The default `auto` mode emits sparse motion residues only for sufficiently large run/dash motion. A sample decays through a small glyph vocabulary such as:

```text
≡  ->  ⠂  ->  ⠄  ->  ·  ->  gone
```

The full actor exists only once. Short moves and ordinary idle adjustments normally have no trail.

The effect is intended to communicate speed while keeping the character readable.

## Expression timing

Skin animation is based on explicit wall-clock keyframes, not repeated frames used as a timer.

Example:

```lua
blink = {
  steps = {
    { frame = "blink", duration_ms = 70 },
    { frame = "idle", duration_ms = 90 },
  },
}
```

This makes blink, ear twitch, glance, stretch, celebration, appearance, and other actions independently tunable without tying them to motion FPS.

Ambient expression is deliberately sparse. The default Mote schedules rare idle micro-actions after long quiet windows rather than animating continuously.

## Mode-aware interaction

Editor mode changes the familiar's behavior budget, not just its face.

| Mode family | Presentation intent | Motion policy | Ambient behavior |
| --- | --- | --- | --- |
| Normal | observant, relaxed, playful | allowed | enabled |
| Insert | quietly focused alongside the user | strongly discouraged unless unsafe | disabled |
| Visual/Select | attentive to the active selection | discouraged | disabled |
| Operator-pending | anticipatory/focused | discouraged | disabled |
| Replace | alert/focused | discouraged | disabled |
| Command-line | compact and unobtrusive | freeze if safe | disabled |
| Terminal | quiet/background | freeze if safe | disabled |
| Prompt/temporary input | minimize distraction | freeze if safe | disabled |

The mode policy is deliberately independent from the skin. A skin decides what "focused" or "visual" looks like; the runtime decides when those semantics apply.

## Mote interaction language

Mote remains an abstract character rather than a fixed species. Its visual identity is small enough to read as cat-like or spirit-like without requiring that interpretation.

The v2 skin adds:

- normal idle and soft idle;
- focused insert pose;
- visual-selection attention gesture;
- operator anticipation;
- replace alert;
- compact command-line and terminal poses;
- left/right glances;
- ear/head silhouette twitch;
- stretch and relax;
- walk/run/dash poses;
- sparse appearance/disappearance particles;
- save acknowledgment;
- diagnostic-resolution success reaction;
- existing inspect, curious, sleep, wave, cheer, magic, panic, and peek actions.

The design rule remains: expressive in at most three terminal rows, with personality coming from timing and context more than detail density.

## Public configuration philosophy

Most users should choose a profile and perhaps override one or two values:

```lua
require("familiar").setup({
  skin = "mote",
  animation = {
    profile = "balanced",
    duration_ms = 250,
    fps = 60,
    easing = "cubic",
    trail = { mode = "auto" },
  },
})
```

Profiles:

- `balanced`: 60 FPS, 250 ms, cubic;
- `high_refresh`: 120 FPS, 250 ms, cubic;
- `economy`: 30 FPS, 280 ms, cubic.

Detailed thresholds remain available for advanced tuning, but they should not become required knowledge for normal installation.

## Performance acceptance direction

Before treating animation defaults as stable, real-terminal testing should continue to track:

- logical ticks versus actual `nvim_win_set_config` calls;
- actor content rewrites;
- frame callback jitter;
- CPU while actively moving;
- idle CPU when no animation is scheduled;
- behavior under repeated scrolling and resize events;
- nuisance rate: how often the character moves when staying put would have been acceptable.

The desired outcome is not the highest possible frame rate. It is stable wall-clock motion, low redundant work, and a familiar that knows when not to move.
