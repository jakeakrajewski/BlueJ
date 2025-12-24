const std = @import("std");

const Oscillator = @import("oscillator.zig").Oscillator;
const Wavetables = @import("tables.zig").Wavetables;
const ADSR = @import("adsr.zig").ADSR;
const LowPassFilter = @import("filter.zig").LowPassFilter;
const ResonantLPF = @import("filter.zig").ResonantLPF;
const LadderLPF = @import("filter.zig").LadderLPF;

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


pub const LfoRouting = struct {
    cutoff: f32 = 0.0,   // Hz depth
    resonance: f32 = 0.0, // 0..1
    pitch: f32 = 0.0,    // semitones
    amp: f32 = 0.0,      // bipolar tremolo
    volume: f32 = 0.0,   // post-amp volume modulation
};


pub const LFO = struct {
    osc: Oscillator,
    freq_hz: f32 = 1.0,
    depth: f32 = 1.0,
    routing: LfoRouting,
    value: f32 = 0.0, // cached output (-1..1)
};

/// Monophonic synth voice
pub const Voice = struct {
    oscs: [MAX_OSCS]Oscillator,
    osc_params: [MAX_OSCS]OscParams,

    lfo1: LFO,
    lfo2: LFO,

    lfo_counter: u32 = 0,
    lfo_update_rate: u32 = 32, // control-rate (samples)
    
    master_volume: f32 = 0.8,
    drive: f32 = 2.5,

    active: bool = false,
    base_freq: f32 = 0.0,

    current_freq: f32 = 0.0,
    target_freq: f32 = 0.0,
    portamento_time: f32 = 0.0, // seconds
    portamento_step: f32 = 0.0,
    key_tracking_amount: f32,  // e.g., 0.0 .. 1.0
    midi_note: u8,             // for key tracking

    amp_env: ADSR,
    filter_env: ADSR,

    filter: LadderLPF,
    // filter: ResonantLPF,
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
            .filter = LadderLPF.init(sample_rate),
            // .filter = ResonantLPF.init(sample_rate),

            .key_tracking_amount = 0.0,
            .midi_note = 69, //A4
            //

            .lfo1 = .{
                .osc = Oscillator.init(tables),
                .routing = .{}
            },
            .lfo2 = .{
                .osc = Oscillator.init(tables),
                .routing = .{}
            },

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

pub fn nextSample(self: *Voice) [2]f32 {
    if (!self.active) return [2]f32{0.0, 0.0 };

    self.lfo_counter += 1;

    if (self.lfo_counter >= self.lfo_update_rate) {
        self.lfo_counter = 0;

        self.lfo1.osc.setFrequency(self.lfo1.freq_hz);
        self.lfo2.osc.setFrequency(self.lfo2.freq_hz);

        // Ensure bipolar output
        self.lfo1.value = self.lfo1.osc.nextSample() * 2.0 - 1.0;
        self.lfo2.value = self.lfo2.osc.nextSample() * 2.0 - 1.0;
    }

    if (self.portamento_time == 0.0) {
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


    var pitch_mod_semitones: f32 = 0.0;

    pitch_mod_semitones += self.lfo1.value * self.lfo1.routing.pitch * self.lfo1.depth;
    pitch_mod_semitones += self.lfo2.value * self.lfo2.routing.pitch * self.lfo2.depth;

    const pitch_ratio =
        std.math.pow(f32, 2.0, pitch_mod_semitones / 12.0);

    self.base_freq = self.current_freq * pitch_ratio;


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
        return [2]f32{0.0, 0.0 };
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


    var cutoff = self.base_cutoff;

    cutoff += filt_env * self.filter_env_amount;
    cutoff += key_mod;
    cutoff += self.lfo1.value * self.lfo1.routing.cutoff * self.lfo1.depth * 8000.0;
    cutoff += self.lfo2.value * self.lfo2.routing.cutoff * self.lfo2.depth * 8000.0;
    cutoff = std.math.clamp(cutoff, 20.0, 20000.0);


    self.filter.setCutoff(cutoff);
 
    var resonance = self.filter_resonance;

    resonance += self.lfo1.value * self.lfo1.routing.resonance * self.lfo1.depth;
    resonance += self.lfo2.value * self.lfo2.routing.resonance * self.lfo2.depth;

    resonance = std.math.clamp(resonance, 0.0, 0.99);
    self.filter.setResonance(resonance);


    var filtered = self.filter.process(mix);

    filtered = std.math.tanh(filtered * self.drive);


    // --- AMP MOD (musical tremolo) ---
    var amp_mod: f32 = 1.0;

    // Square wave tremolo should be unipolar
    if (self.lfo1.routing.amp > 0.0) {
        const t = bipolarToUnipolar(self.lfo1.value);
        amp_mod *= std.math.lerp(
            1.0,
            t,
            self.lfo1.routing.amp * self.lfo1.depth,
        );
    }

    if (self.lfo2.routing.amp > 0.0) {
        const t = bipolarToUnipolar(self.lfo2.value);
        amp_mod *= std.math.lerp(
            1.0,
            t,
            self.lfo2.routing.amp * self.lfo2.depth,
        );
    }

    amp_mod = std.math.clamp(amp_mod, 0.0, 1.0);

    // --- VOLUME MOD (hard chop / gate) ---
    var volume_mod: f32 = 1.0;

    if (self.lfo1.routing.volume > 0.0) {
        volume_mod *= std.math.lerp(
            1.0,
            hardTremolo(self.lfo1.value),
            self.lfo1.routing.volume * self.lfo1.depth,
        );
    }

    if (self.lfo2.routing.volume > 0.0) {
        volume_mod *= std.math.lerp(
            1.0,
            hardTremolo(self.lfo2.value),
            self.lfo2.routing.volume * self.lfo2.depth,
        );
    }

    const mono_out =
        filtered *
        amp *
        amp_mod *
        self.master_volume *
        volume_mod; 
        const stereo_out = [2]f32{mono_out, mono_out};

    return stereo_out;
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

fn bipolarToUnipolar(x: f32) f32 {
    // -1..1 → 0..1
    return 0.5 * (x + 1.0);
}

fn hardTremolo(x: f32) f32 {
    // square-wave style gating
    return if (x > 0.0) 1.0 else 0.0;
}

