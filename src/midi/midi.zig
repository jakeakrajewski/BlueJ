pub const MidiEventType = enum {
    note_on,
    note_off,
    cc,
    pitch_bend,
    program_change,
    channel_pressure,
    realtime,
};
pub const MidiEvent = struct {
    event_type: MidiEventType,
    channel: u4 = 0,

    note: u7 = 0,
    velocity: u7 = 0,

    controller: u7 = 0,
    value: u7 = 0,

    pitch_bend: i14 = 0, // -8192 .. +8191

    realtime: u8 = 0,
};
pub const MidiParser = struct {
    running_status: u8 = 0,
    data_buf: [2]u8 = undefined,
    data_count: u8 = 0,

    pub fn reset(self: *MidiParser) void {
        self.running_status = 0;
        self.data_count = 0;
    }

    pub fn parseByte(
        self: *MidiParser,
        byte: u8,
    ) ?MidiEvent {
        if (isRealtime(byte)) {
            return MidiEvent{
                .event_type = .realtime,
                .realtime = byte,
            };
        }

        if (isStatusByte(byte)) {
            self.running_status = byte;
            self.data_count = 0;
            return null;
        }

        if (self.running_status == 0) {
            return null;         }

        self.data_buf[self.data_count] = byte;
        self.data_count += 1;

        const needed = dataBytesNeeded(self.running_status);
        if (self.data_count < needed) return null;

        const status = self.running_status;
        self.data_count = 0;

        const channel: u4 = @truncate(status & 0x0F);

        return switch (status & 0xF0) {
            0x80 => MidiEvent{
                .event_type = .note_off,
                .channel = channel,
                .note = @truncate(self.data_buf[0]),
                .velocity = @truncate(self.data_buf[1]),
            },

            0x90 => blk: {
                const vel = self.data_buf[1];
                if (vel == 0) {
                    break :blk MidiEvent{
                        .event_type = .note_off,
                        .channel = channel,
                        .note = @truncate(self.data_buf[0]),
                        .velocity = 0,
                    };
                }
                break :blk MidiEvent{
                    .event_type = .note_on,
                    .channel = channel,
                    .note = @truncate(self.data_buf[0]),
                    .velocity = @truncate(vel),
                };
            },

            0xB0 => MidiEvent{
                .event_type = .cc,
                .channel = channel,
                .controller = @truncate(self.data_buf[0]),
                .value = @truncate(self.data_buf[1]),
            },

            0xC0 => MidiEvent{
                .event_type = .program_change,
                .channel = channel,
                .value = @truncate(self.data_buf[0]),
            },

            0xD0 => MidiEvent{
                .event_type = .channel_pressure,
                .channel = channel,
                .value = @truncate(self.data_buf[0]),
            },

            0xE0 => blk: {
                const lsb = self.data_buf[0];
                const msb = self.data_buf[1];
                const value = (@as(i16, msb) << 7) | lsb;
                break :blk MidiEvent{
                    .event_type = .pitch_bend,
                    .channel = channel,
                    .pitch_bend = @intCast(value - 8192),
                };
            },

            else => null,
        };
    }
};

fn isStatusByte(b: u8) bool {
    return (b & 0x80) != 0;
}

fn isRealtime(b: u8) bool {
    return b >= 0xF8;
}

fn dataBytesNeeded(status: u8) u8 {
    return switch (status & 0xF0) {
        0xC0, 0xD0 => 1, 
        else => 2,
    };
}

const MidiLearnState = @import("controls.zig").MidiLearnState;
const MidiCCMap = @import("controls.zig").MidiCCMap;

// fn handleCC(
//     cc: u8,
//     value: u8,
//     cc_map: *MidiCCMap,
//     params: []Param,
//     midi_learn: *MidiLearnState,
// ) void {
//     if (midi_learn.armed.load(.acquire)) {
//         const param_index =
//             midi_learn.target_param_index.load(.acquire);
//
//         if (param_index >= 0 and param_index < params.len) {
//             cc_map.bindings[cc] = param_index;
//         }
//
//         midi_learn.armed.store(false, .release);
//         midi_learn.target_param_index.store(-1, .release);
//         return;
//     }
//
//     const idx = cc_map.bindings[cc];
//     if (idx >= 0 and idx < params.len) {
//         const norm = @as(f32, value) / 127.0;
//         params[@intCast(usize, idx)].setNormalized(norm);
//     }
// }

