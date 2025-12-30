const std = @import("std");
const mem = @import("../memory/memory.zig");

pub const Reverb = struct {
    sample_rate: f32,
    mix: f32 = 0.2,
    feedback: f32 = 0.5,
    delay_buffer_l: []f32,
    delay_buffer_r: []f32,
    write_pos: usize = 0,

    pub fn init(sample_rate: f32, max_delay_sec: f32) !Reverb {
        const allocator = mem.globalAlloc();
        const delay_len: usize = @intFromFloat(sample_rate * max_delay_sec);
        return Reverb{
            .sample_rate = sample_rate,
            .mix = 0.2,
            .feedback = 0.5,
            .delay_buffer_l = try allocator.alloc(f32, delay_len),
            .delay_buffer_r = try allocator.alloc(f32, delay_len),
            .write_pos = 0,
        };
    }

    pub fn process(self: *Reverb, input: [2]f32) [2]f32 {
        const len = self.delay_buffer_l.len;

        var out: [2]f32 = undefined;

        out[0] = input[0] + self.delay_buffer_l[self.write_pos] * self.mix;
        out[1] = input[1] + self.delay_buffer_r[self.write_pos] * self.mix;

        // store feedback
        self.delay_buffer_l[self.write_pos] = input[0] + self.delay_buffer_l[self.write_pos] * self.feedback;
        self.delay_buffer_r[self.write_pos] = input[1] + self.delay_buffer_r[self.write_pos] * self.feedback;

        self.write_pos += 1;
        if (self.write_pos >= len) self.write_pos = 0;

        return out;
    }
};

