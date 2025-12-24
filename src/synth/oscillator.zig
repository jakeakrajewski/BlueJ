const std = @import("std");
const tables_mod = @import("tables.zig");

const TABLE_SIZE = tables_mod.TABLE_SIZE;

pub const SAMPLE_RATE: f32 = 48_000.0;

pub const Oscillator = struct {
    phase: f32 = 0.0,
    phase_inc: f32 = 0.0,
    frequency: f32 = 440.0,
    tables: tables_mod.Wavetables,
    waveform: Waveform = .saw,
    sync_slave: ?*Oscillator = null,
    unison_count: u8 = 1,
    unison_detune_cents: f32 = 0.0,
    unison_phases: [MAX_UNISON]f32 = [_]f32{0.0} ** MAX_UNISON,

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
        // Spread initial phases across unison voices
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
        var sum: f32 = 0.0;
        const count = self.unison_count;
        
        for (0..count) |i| {
            const detune =
                self.unison_detune_cents *
                (@as(f32, @floatFromInt(i)) -
                 @as(f32, @floatFromInt(count - 1)) * 0.5);
            const inc = self.phase_inc * centsToRatio(detune);
            var p = self.unison_phases[i];
            const s = self.sampleAtPhase(p, inc);
            p += inc;
            if (p >= 1.0) p -= 1.0;
            self.unison_phases[i] = p;
            sum += s;
        }
        
        // Power normalization for perceptually consistent loudness
        sum /= @sqrt(@as(f32, @floatFromInt(count)));

        // ---- MASTER PHASE ADVANCE ----
        self.phase += self.phase_inc;

        var wrapped = false;
        if (self.phase >= 1.0) {
            self.phase -= 1.0;
            wrapped = true;
        }

        // ---- HARD SYNC ----
        if (wrapped) {
            if (self.sync_slave) |slave| {
                slave.reset();
            }
        }

        return sum;
    }

    fn sampleAtPhase(self: *Oscillator, phase: f32, phase_inc: f32) f32 {
        switch (self.waveform) {
            .sine => {
                const idx = @as(usize, @intFromFloat(phase * TABLE_SIZE)) % TABLE_SIZE;
                return self.tables.sine[idx];
            },
            .tri => {
                const idx = @as(usize, @intFromFloat(phase * TABLE_SIZE)) % TABLE_SIZE;
                return self.tables.tri[idx];
            },
            .saw => return tables_mod.sawPolyBLEP(phase, phase_inc),
            .square => return tables_mod.squarePolyBLEP(phase, phase_inc),
        }
    }
};

inline fn centsToRatio(cents: f32) f32 {
    return std.math.exp2(cents / 1200.0);
}
