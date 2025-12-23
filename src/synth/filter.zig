const std = @import("std");

pub const LowPassFilter = struct {
    sample_rate: f32,
    cutoff: f32 = 1000.0,
    z1: f32 = 0.0,
    a: f32 = 0.0,

    pub fn init(sample_rate: f32) LowPassFilter {
        var f = LowPassFilter{
            .sample_rate = sample_rate,
        };
        f.recalc();
        return f;
    }

    pub fn setCutoff(self: *LowPassFilter, hz: f32) void {
        self.cutoff = std.math.clamp(hz, 20.0, self.sample_rate * 0.45);
        self.recalc();
    }

    fn recalc(self: *LowPassFilter) void {
        const x = std.math.exp(
            -2.0 * std.math.pi * self.cutoff / self.sample_rate,
        );
        self.a = 1.0 - x;
    }

    pub fn process(self: *LowPassFilter, input: f32) f32 {
        self.z1 += self.a * (input - self.z1);
        return self.z1;
    }

    pub fn reset(self: *LowPassFilter) void {
        self.z1 = 0.0;
    }
};

pub const ResonantLPF = struct {
    sample_rate: f32,
    cutoff: f32 = 1000.0,
    resonance: f32 = 0.0, // 0..1
    y1: f32 = 0.0,
    y2: f32 = 0.0,
    x1: f32 = 0.0,
    g: f32 = 0.0,
    k: f32 = 0.0,

    pub fn init(sample_rate: f32) ResonantLPF {
        var f = ResonantLPF{
            .sample_rate = sample_rate,
        };
        f.recalc();
        return f;
    }

    pub fn setCutoff(self: *ResonantLPF, hz: f32) void {
        self.cutoff = std.math.clamp(hz, 20.0, self.sample_rate * 0.45);
        self.recalc();
    }

    pub fn setResonance(self: *ResonantLPF, res: f32) void {
        self.resonance = std.math.clamp(res, 0.0, 0.99);
        self.recalc();
    }

    fn recalc(self: *ResonantLPF) void {
        const fc = self.cutoff / self.sample_rate;
        self.g = std.math.tan(std.math.pi * fc);
        self.k = 2.0 * self.resonance;
    }

    pub fn process(self: *ResonantLPF, input: f32) f32 {
        const v = (input - self.k * self.y2 - self.y1) / (1.0 + self.g);
        const y = self.g * v + self.y2;
        self.y2 = self.y2 + 2.0 * self.g * v;
        self.y1 = y;
        return y;
    }

    pub fn reset(self: *ResonantLPF) void {
        self.y1 = 0.0;
        self.y2 = 0.0;
    }
};

pub const LadderLPF = struct {
    sample_rate: f32,
    cutoff: f32 = 1000.0,
    resonance: f32 = 0.0, // 0..1

    // integrator states
    z: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },

    g: f32 = 0.0,
    k: f32 = 0.0,

    pub fn init(sample_rate: f32) LadderLPF {
        var f = LadderLPF{
            .sample_rate = sample_rate,
        };
        f.recalc();
        return f;
    }

    pub fn setCutoff(self: *LadderLPF, hz: f32) void {
        self.cutoff = std.math.clamp(hz, 20.0, self.sample_rate * 0.45);
        self.recalc();
    }

    pub fn setResonance(self: *LadderLPF, res: f32) void {
        // keep just below full self-oscillation
        self.resonance = std.math.clamp(res, 0.0, 0.98);
        self.recalc();
    }

    fn recalc(self: *LadderLPF) void {
        const fc = self.cutoff / self.sample_rate;
        self.g = std.math.tan(std.math.pi * fc);
        self.k = 4.0 * self.resonance;
    }

    inline fn sat(x: f32) f32 {
        // soft saturation
        return std.math.tanh(x);
    }

    pub fn process(self: *LadderLPF, input: f32) f32 {
        // feedback from last stage
        var x = input - self.k * self.z[3];
        x = sat(x);

        inline for (0..4) |i| {
            const v = (x - self.z[i]) * self.g;
            const y = v + self.z[i];
            self.z[i] = y + v;
            x = sat(y);
        }

        return self.z[3];
    }

    pub fn reset(self: *LadderLPF) void {
        self.z = .{ 0.0, 0.0, 0.0, 0.0 };
    }
};

