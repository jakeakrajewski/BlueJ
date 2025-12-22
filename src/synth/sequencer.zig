const std = @import("std");

pub var running = false;
pub var sequence: [32]f32 = undefined;
pub var midi_id: [32]i8 = undefined;

pub fn init() void {
    for (0..sequence.len) |i| {
        sequence[i] == -1.0;
        midi_id[i] == -1;
    }
}

pub fn setNote(index: usize, note: i8 ) void {
    midi_id[index] = note;
    sequence[index] = midiNoteToFreq(note);
}

fn midiNoteToFreq(note: i8) f32 {
    return 440.0 *
        std.math.pow(f32, 2.0,
            (@as(f32, @floatFromInt(note)) - 69.0) / 12.0);
}

