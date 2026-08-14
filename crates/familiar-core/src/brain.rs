use crate::protocol::{Behavior, BehaviorIntent, Locomotion, Mood, Target};
use crate::world::World;

pub trait Brain {
    fn decide(&mut self, world: &World) -> BehaviorIntent;
}

#[derive(Default)]
pub struct RuleBrain;

impl Brain for RuleBrain {
    fn decide(&mut self, world: &World) -> BehaviorIntent {
        let Some(snapshot) = world.snapshot.as_ref() else {
            return BehaviorIntent {
                behavior: Behavior::Hide,
                target: Target::ScreenEdge,
                locomotion: Locomotion::None,
                mood: Mood::Calm,
                emote: None,
                duration_ms: 3_000,
            };
        };

        if snapshot.viewport.width < 48 || snapshot.viewport.height < 12 {
            return BehaviorIntent {
                behavior: Behavior::Hide,
                target: Target::ScreenEdge,
                locomotion: Locomotion::Vanish,
                mood: Mood::Calm,
                emote: None,
                duration_ms: 5_000,
            };
        }

        if snapshot.activity.idle_ms >= 120_000 {
            return BehaviorIntent {
                behavior: Behavior::Sleep,
                target: Target::QuietCorner,
                locomotion: Locomotion::Walk,
                mood: Mood::Sleepy,
                emote: Some("sleep"),
                duration_ms: 30_000,
            };
        }

        if snapshot.diagnostics.errors > 0 {
            return BehaviorIntent {
                behavior: Behavior::Inspect,
                target: Target::CursorArea,
                locomotion: Locomotion::Walk,
                mood: Mood::Concerned,
                emote: Some("question"),
                duration_ms: 7_000,
            };
        }

        let just_switched_buffer = world
            .last_event
            .as_ref()
            .is_some_and(|event| event.kind == "buffer_enter");

        if snapshot.activity.buffer_switches_10s >= 3
            || (just_switched_buffer && snapshot.activity.buffer_switches_10s >= 2)
        {
            return BehaviorIntent {
                behavior: Behavior::Curious,
                target: Target::QuietCorner,
                locomotion: Locomotion::Run,
                mood: Mood::Curious,
                emote: Some("question"),
                duration_ms: 6_000,
            };
        }

        if snapshot.activity.typing || snapshot.mode.starts_with('i') {
            return BehaviorIntent {
                behavior: Behavior::Focus,
                target: Target::QuietCorner,
                locomotion: Locomotion::None,
                mood: Mood::Focused,
                emote: None,
                duration_ms: 8_000,
            };
        }

        BehaviorIntent {
            behavior: Behavior::Idle,
            target: Target::QuietCorner,
            locomotion: Locomotion::Auto,
            mood: Mood::Calm,
            emote: None,
            duration_ms: 10_000,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{
        ActivitySnapshot, BufferSnapshot, DiagnosticSnapshot, EditorSnapshot, ViewportSnapshot,
    };

    fn snapshot() -> EditorSnapshot {
        EditorSnapshot {
            mode: "n".into(),
            buffer: BufferSnapshot {
                id: 1,
                name: "notes.md".into(),
                filetype: "markdown".into(),
                modified: false,
                line_count: 120,
            },
            viewport: ViewportSnapshot {
                width: 120,
                height: 40,
                cursor_row: 10,
                cursor_col: 3,
                topline: 1,
                botline: 40,
                line_display_widths: vec![20, 30],
            },
            diagnostics: DiagnosticSnapshot {
                errors: 0,
                warnings: 0,
            },
            activity: ActivitySnapshot {
                idle_ms: 0,
                typing: false,
                buffer_switches_10s: 0,
            },
        }
    }

    #[test]
    fn hides_in_small_windows() {
        let mut snapshot = snapshot();
        snapshot.viewport.width = 30;
        let world = World {
            snapshot: Some(snapshot),
            last_event: None,
        };
        assert_eq!(RuleBrain.decide(&world).behavior, Behavior::Hide);
    }

    #[test]
    fn sustained_idle_prefers_sleep() {
        let mut snapshot = snapshot();
        snapshot.activity.idle_ms = 130_000;
        let world = World {
            snapshot: Some(snapshot),
            last_event: None,
        };
        assert_eq!(RuleBrain.decide(&world).behavior, Behavior::Sleep);
    }

    #[test]
    fn diagnostics_take_attention_before_focus() {
        let mut snapshot = snapshot();
        snapshot.activity.typing = true;
        snapshot.diagnostics.errors = 1;
        let world = World {
            snapshot: Some(snapshot),
            last_event: None,
        };
        assert_eq!(RuleBrain.decide(&world).behavior, Behavior::Inspect);
    }

    #[test]
    fn typing_prefers_focus_without_more_important_event() {
        let mut snapshot = snapshot();
        snapshot.activity.typing = true;
        let world = World {
            snapshot: Some(snapshot),
            last_event: None,
        };
        assert_eq!(RuleBrain.decide(&world).behavior, Behavior::Focus);
    }
}
