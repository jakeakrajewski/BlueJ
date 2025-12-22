const std = @import("std");

const Oscillator = @import("oscillator.zig").Oscillator;
const Wavetables = @import("tables.zig").Wavetables;
const ADSR = @import("adsr.zig").ADSR;
const LowPassFilter = @import("filter.zig").LowPassFilter;
const ResonantLPF = @import("filter.zig").ResonantLPF;

pub const MAX_OSCS: usize = 3;
const TABLE_SIZE: usize = 2048;

/// Per-oscillator configuration
pub const OscParams = struct {
    level: f32 = 1.0,
    detune_cents: f32 = 0.0,
    waveform: Oscillator.Waveform = .saw,
    octave: i8 = 0,
    semitone: i8 = 0,
};

/// Monophonic synth voice
pub const Voice = struct {
    oscs: [MAX_OSCS]Oscillator,
    osc_params: [MAX_OSCS]OscParams,

    master_volume: f32 = 0.8,
    drive: f32 = 2.5,

    active: bool = false,
    base_freq: f32 = 0.0,

    current_freq: f32 = 0.0,
    target_freq: f32 = 0.0,
    portamento_time: f32 = 0.0, // seconds
    portamento_step: f32 = 0.0,
    legato: bool,
    key_tracking_amount: f32,  // e.g., 0.0 .. 1.0
    midi_note: u8,             // for key tracking

    amp_env: ADSR,
    filter_env: ADSR,

    filter: ResonantLPF,
    filter_resonance: f32 = 0.5, // 0..0.99

    base_cutoff: f32 = 200.0,
    filter_env_amount: f32 = 6000.0,


    /// Initialize voice and internal oscillators


    pub fn init(tables: Wavetables, sample_rate: f32) Voice {
        var v = Voice{
            .oscs = undefined,
            .osc_params = undefined,

            .amp_env = ADSR.init(sample_rate),
            .filter_env = ADSR.init(sample_rate),
            .filter = ResonantLPF.init(sample_rate),

            .legato = false,
            .key_tracking_amount = 0.0,
            .midi_note = 69, //A4
        };

        for (&v.oscs, &v.osc_params) |*osc, *params| {
            osc.* = Oscillator.init(tables);
            params.* = .{};
        }

        return v;
    }



    // ------------------------
    // NOTE CONTROL
    // ------------------------


    pub fn noteOn(self: *Voice, freq: f32) void {
        self.target_freq = freq;

        if (self.active and self.portamento_time > 0.0) {
            // Glide: compute per-sample increment
            const delta = self.target_freq - self.current_freq;
            self.portamento_step = delta / (self.portamento_time * self.amp_env.sample_rate);
        } else {
            self.current_freq = freq;
            self.portamento_step = 0.0;
        }

        self.active = true;
        self.amp_env.noteOn();
        self.filter_env.noteOn();
    }


    pub fn noteOff(self: *Voice) void {
        self.amp_env.noteOff();
        self.filter_env.noteOff();
    }

    // ------------------------
    // OSC CONTROL
    // ------------------------

    pub fn setOscLevel(self: *Voice, index: usize, level: f32) void {
        if (index >= MAX_OSCS) return;
        self.osc_params[index].level = level;
    }

    pub fn setOscDetune(self: *Voice, index: usize, cents: f32) void {
        if (index >= MAX_OSCS) return;
        self.osc_params[index].detune_cents = cents;
        self.updateOscFrequencies();
    }

    pub fn setOscWaveform(
        self: *Voice,
        index: usize,
        wf: Oscillator.Waveform,
    ) void {
        if (index >= MAX_OSCS) return;
        self.osc_params[index].waveform = wf;
        self.oscs[index].setWaveform(wf);
    }

pub fn nextSample(self: *Voice) f32 {
    if (!self.active) return 0.0;

    if (!self.legato or self.portamento_time == 0.0) {
        self.current_freq = self.target_freq;
        self.portamento_step = 0.0;
    } else if (self.portamento_step != 0.0) {
        const delta = self.target_freq - self.current_freq;
        if (@abs(delta) <= @abs(self.portamento_step)) {
            self.current_freq = self.target_freq;
        } else {
            self.current_freq += self.portamento_step;
        }
    }

    self.base_freq = self.current_freq;

    for (&self.oscs, self.osc_params) |*osc, params| {
        const cents = pitchOffsetCents(params);

        osc.setFrequency(self.base_freq * centsToRatio(cents));
        osc.setWaveform(params.waveform);

        if (osc.sync_slave) |slave| {
            if (osc.phase >= @as(f32, TABLE_SIZE)) {
                slave.phase = 0.0;
            }
        }
    }

    const amp = self.amp_env.next();
    const filt_env = self.filter_env.next();

    if (!self.amp_env.isActive()) {
        self.active = false;
        self.filter.reset();
        return 0.0;
    }

    var mix: f32 = 0.0;
    var power: f32 = 0.0;

    for (&self.oscs, self.osc_params) |*osc, params| {
        const s = osc.nextSample();
        mix += s * params.level;
        power += params.level * params.level;
    }

    if (power > 0.0) {
        mix /= std.math.sqrt(power);
    }

    mix = std.math.tanh(mix * self.drive);

    const key_mod =
        self.key_tracking_amount *
        @as(f32, @floatFromInt(self.midi_note - 69)); // A4 reference

    const cutoff =
        self.base_cutoff +
        filt_env * self.filter_env_amount +
        key_mod;

    self.filter.setCutoff(cutoff);
    self.filter.setResonance(self.filter_resonance);

    var filtered = self.filter.process(mix);

    filtered = std.math.tanh(filtered * self.drive);

    return filtered * amp * self.master_volume;
}

    fn updateOscFrequencies(self: *Voice) void {
        for (&self.oscs, self.osc_params) |*osc, params| {
            const ratio = centsToRatio(params.detune_cents);
            osc.setFrequency(self.base_freq * ratio);
            osc.setWaveform(params.waveform);
        }
    }
};

fn centsToRatio(cents: f32) f32 {
    return std.math.pow(f32, 2.0, cents / 1200.0);
}

fn pitchOffsetCents(params: OscParams) f32 {
    return
        @as(f32, @floatFromInt(params.octave)) * 1200.0 +
        @as(f32, @floatFromInt(params.semitone)) * 100.0 +
        params.detune_cents;
}
