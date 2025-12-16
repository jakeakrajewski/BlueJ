pub const MidiEvent = struct {
    kind: Kind,
    note: u8 = 0,
    velocity: u8 = 0,
    cc: u8 = 0,
    value: u8 = 0,
    pitch_bend: i16 = 0,

    pub const Kind = enum {
        note_on,
        note_off,
        cc,
        pitch_bend,
    };
};
    
const MAX_KEYS = 8;

pub const NoteStack = struct {
    notes: [MAX_KEYS]u8 = [_]u8{0} ** MAX_KEYS,
    count: usize = 0,

    pub fn push(self: *NoteStack, note: u8) void {
        if (self.count < MAX_KEYS) {
            self.notes[self.count] = note;
            self.count += 1;
        }
    }

    pub fn remove(self: *NoteStack, note: u8) void {
        var i: usize = 0;
        while (i < self.count) {
            if (self.notes[i] == note) {
                self.notes[i] = self.notes[self.count - 1];
                self.count -= 1;
                return;
            }
            i += 1;
        }
    }

    pub fn top(self: *NoteStack) ?u8 {
        if (self.count == 0) return null;
        return self.notes[self.count - 1];
    }
};

