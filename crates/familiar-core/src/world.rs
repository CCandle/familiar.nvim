use crate::protocol::{EditorEvent, EditorSnapshot};

#[derive(Default)]
pub struct World {
    pub snapshot: Option<EditorSnapshot>,
    pub last_event: Option<EditorEvent>,
    pub event_generation: u64,
}

impl World {
    pub fn apply_snapshot(&mut self, snapshot: EditorSnapshot) {
        self.snapshot = Some(snapshot);
    }

    pub fn apply_event(&mut self, event: EditorEvent) {
        self.last_event = Some(event);
        self.event_generation = self.event_generation.wrapping_add(1);
    }
}
