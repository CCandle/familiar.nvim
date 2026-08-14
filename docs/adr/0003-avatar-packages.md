# ADR 0003: avatars are data, not engine branches

- Status: Accepted direction; schema not yet stable
- Date: 2026-08-14

## Context

The initial familiar is a fox, but the engine should not encode fox-specific behavior. Future users should be able to author or generate different avatars with different animation timing, emotes, and personality tendencies.

## Decision

Treat an avatar as a package of declarative data:

```text
avatar/
  avatar.toml
  palette.toml
  sprites/
  animations.toml
  behavior.toml
  emotes.toml
```

The stable schema will be introduced only after the fox vertical slice reveals what data is actually required.

The engine must not contain `if avatar == fox` behavior branches.

## Personality

Avatar packages may eventually declare bounded personality parameters such as curiosity, energy, shyness, restlessness, and attention biases. These values influence the deterministic policy and become context for a future tiny model.

An avatar is therefore allowed to change behavior, not merely appearance.

## Model boundary

A model may select identifiers declared by an avatar package (`inspect`, `question`, `run`, etc.). It may not generate arbitrary visible strings, sprite bytes, RGB values, or executable behavior at runtime.

## Extensibility

The first behavior format should remain declarative. Arbitrary Lua/WASM scripting is explicitly deferred until there is a real need and a security/compatibility model.
