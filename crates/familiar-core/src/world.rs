use crate::protocol::{EditorEvent, EditorSnapshot};

#[derive(Default)]
pub struct World {
    pub snapshot: Option<EditorSnapshot>,
    pub last_event: Option<EditorEvent>,
}

impl World {
    pub fn apply_snapshot(&mut self, snapshot: EditorSnapshot) {
        self.snapshot = Some(snapshot);
    }

    pub fn apply_event(&mut self, event: EditorEvent) {
        self.last_event = Some(event);
    }
}
