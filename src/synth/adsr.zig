const std = @import("std");

pub const ADSR = struct {
    pub const Stage = enum {
        idle,
        attack,
        decay,
        sustain,
        release,
    };

    attack_time: f32 = 0.01,
    decay_time: f32 = 0.1,
    sustain_level: f32 = 0.7,
    release_time: f32 = 0.2,

    sample_rate: f32 = 48_000.0,

    stage: Stage = .idle,
    value: f32 = 0.0,

    attack_step: f32 = 0.0,
    decay_step: f32 = 0.0,
    release_step: f32 = 0.0,

    pub fn init(sample_rate: f32) ADSR {
        var env = ADSR{
            .sample_rate = sample_rate,
        };
        env.recalc();
        return env;
    }

    pub fn recalc(self: *ADSR) void {
        self.attack_step =
            if (self.attack_time > 0.0)
                1.0 / (self.attack_time * self.sample_rate)
            else
                1.0;

        self.decay_step =
            if (self.decay_time > 0.0)
                (1.0 - self.sustain_level) / (self.decay_time * self.sample_rate)
            else
                1.0;

        self.release_step =
            if (self.release_time > 0.0)
                self.sustain_level / (self.release_time * self.sample_rate)
            else
                1.0;
    }

    pub fn noteOn(self: *ADSR) void {
        self.stage = .attack;
    }

    pub fn noteOff(self: *ADSR) void {
        if (self.stage != .idle)
            self.stage = .release;
    }

    pub fn next(self: *ADSR) f32 {
        switch (self.stage) {
            .idle => {
                self.value = 0.0;
            },
            .attack => {
                self.value += self.attack_step;
                if (self.value >= 1.0) {
                    self.value = 1.0;
                    self.stage = .decay;
                }
            },
            .decay => {
                self.value -= self.decay_step;
                if (self.value <= self.sustain_level) {
                    self.value = self.sustain_level;
                    self.stage = .sustain;
                }
            },
            .sustain => {
                self.value = self.sustain_level;
            },
            .release => {
                self.value -= self.release_step;
                if (self.value <= 0.0) {
                    self.value = 0.0;
                    self.stage = .idle;
                }
            },
        }

        return self.value;
    }

    pub fn isActive(self: *const ADSR) bool {
        return self.stage != .idle;
    }
};

