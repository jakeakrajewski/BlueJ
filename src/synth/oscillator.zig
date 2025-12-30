const std = @import("std");
const tables_mod = @import("tables.zig");

const TABLE_SIZE = tables_mod.TABLE_SIZE;

pub const SAMPLE_RATE: f32 = 48_000.0;

pub const Oscillator = struct {
    phase: f32 = 0.0,
    crossfade_rate: f32 = 0.0,
    morph_pos: f32 = 0.0, 
    morph_dir: f32 = 1.0,     
    phase_inc: f32 = 0.0,
    frequency: f32 = 440.0,
    tables: tables_mod.Wavetables,
    waveform: Waveform = .saw,
    waveform2: Waveform = .saw,
    sync_slave1: ?*Oscillator = null,
    sync_slave2: ?*Oscillator = null,
    unison_count: u8 = 1,
    unison_detune_cents: f32 = 0.0,
    unison_phases: [MAX_UNISON]f32 = [_]f32{0.0} ** MAX_UNISON,

    high: bool = false,

    pub const MAX_UNISON = 8;

    pub const Waveform = enum {
        sine,
        tri,
        saw,
        square,
    };

    pub fn init(tables: tables_mod.Wavetables) Oscillator {
        return .{
            .tables = tables,
        };
    }

  
    pub fn reset(self: *Oscillator) void {
        self.phase = 0.0;
        for (&self.unison_phases, 0..) |*p, i| {
            p.* = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(MAX_UNISON));
        }
    }


    pub fn setFrequency(self: *Oscillator, freq: f32) void {
        self.frequency = freq;
        self.phase_inc = freq / SAMPLE_RATE;
    }

    pub fn setWaveform(self: *Oscillator, wf: Waveform) void {
        self.waveform = wf;
    }

    pub fn setUnison(self: *Oscillator, count: u8, detune_cents: f32) void {
        self.unison_count = std.math.clamp(count, 1, MAX_UNISON);
        self.unison_detune_cents = detune_cents;
    }

    pub fn setSyncMaster(self: *Oscillator, master: ?*Oscillator) void {
        self.sync_master = master;
    }

    pub fn nextSample(self: *Oscillator) f32 {
        var sum_a: f32 = 0.0;
        var sum_b: f32 = 0.0;
        const count = self.unison_count;
        
        for (0..count) |i| {
            const detune =
                self.unison_detune_cents *
                (@as(f32, @floatFromInt(i)) -
                 @as(f32, @floatFromInt(count - 1)) * 0.5);
            const inc = self.phase_inc * centsToRatio(detune);
            var p = self.unison_phases[i];
            
            const sa = self.sampleAtWaveform(p, inc, self.waveform);
            const sb = self.sampleAtWaveform(p, inc, self.waveform2);
            
            sum_a += sa;
            sum_b += sb;
            
            p += inc;
            if (p >= 1.0) p -= 1.0;
            self.unison_phases[i] = p;
        }
        
        const norm = @sqrt(@as(f32, @floatFromInt(count)));
        sum_a /= norm;
        sum_b /= norm;

        self.phase += self.phase_inc;

        var wrapped = false;
        if (self.phase >= 1.0) {
            self.phase -= 1.0;
            wrapped = true;
        }

        if (wrapped) {
            if (self.sync_slave1) |slave| {
                slave.reset();
            }
            if (self.sync_slave2) |slave| {
                slave.reset();
            }
        }

        if (self.crossfade_rate > 0.0) {
            const inc = self.crossfade_rate / SAMPLE_RATE;
            self.morph_pos += inc * self.morph_dir;

            if (self.morph_pos >= 1.0) {
                self.morph_pos = 1.0;
                self.morph_dir = -1.0;
            } else if (self.morph_pos <= 0.0) {
                self.morph_pos = 0.0;
                self.morph_dir = 1.0;
            }
        }

        const t = self.morph_pos;
        const m = t * t * (3.0 - 2.0 * t);
        return (1.0 - m) * sum_a + m * sum_b;
    }

fn sampleAtWaveform(self: *Oscillator, phase: f32, phase_inc: f32, waveform: Waveform) f32 {
    return switch (waveform) {
        .sine => {
            const idx = @as(usize, @intFromFloat(phase * TABLE_SIZE)) % TABLE_SIZE;
            return self.tables.sine[idx];
        },
        .tri => {
            const idx = @as(usize, @intFromFloat(phase * TABLE_SIZE)) % TABLE_SIZE;
            return self.tables.tri[idx];
        },
        .saw => tables_mod.sawPolyBLEP(phase, phase_inc),
        .square => tables_mod.squarePolyBLEP(phase, phase_inc),
    };
}
};

inline fn centsToRatio(cents: f32) f32 {
    return std.math.exp2(cents / 1200.0);
}
