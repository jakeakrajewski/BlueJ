const std = @import("std");
const c = @cImport({
    @cInclude("termios.h");
});
const midi_learn_state = @import("../midi/controls.zig").midi_learn_state;

const stdin_fd = std.posix.STDIN_FILENO;
const stdout_fd = std.posix.STDOUT_FILENO;

const ANSI_RESET = "\x1b[0m";
const ANSI_REVERSE = "\x1b[7m";

const ViewHeader = struct {
    key: u8,
    name: []const u8,
    view: ViewMode,
};

const VIEW_HEADERS = [_]ViewHeader{
    .{ .key = 'm', .name = "aster", .view = .Master },
    .{ .key = 'p', .name = "erf", .view = .Performance },
    .{ .key = 'a', .name = "mp", .view = .Amp },
    .{ .key = 'f', .name = "ilter", .view = .Filter },
    .{ .key = 'l', .name = "FO", .view = .LFO },
    .{ .key = 'o', .name = "sc", .view = .Oscillators },
    .{ .key = 's', .name = "eq", .view = .Sequencer },
};


fn drawViewHeader(writer: *std.io.Writer) void {
    for (VIEW_HEADERS) |h| {
        if (h.view == current_view) {
            _ = writer.print(
                "{s}[{c}]{s}{s} ",
                .{ ANSI_REVERSE, h.key, h.name, ANSI_RESET },
            ) catch {};
        } else {
            _ = writer.print(
                "[{c}]{s} ",
                .{ h.key, h.name },
            ) catch {};
        }
    }

    _ = writer.writeAll("\r\n\r\n") catch {};
}

fn drawSubHeader(writer: *std.io.Writer) void {
    switch (current_view) {
        .Oscillators => {
            for (1..4) |i| {
                if (i == active_osc) {
                    _ = writer.print(
                        "{s}[Osc {d}]{s} ",
                        .{ ANSI_REVERSE, i, ANSI_RESET },
                    ) catch {};
                } else {
                    _ = writer.print("[Osc {d}] ", .{ i }) catch {};
                }
            }
            _ = writer.writeAll("\r\n\r\n") catch {};
        },

        .LFO => {
            for (1..3) |i| {
                if (i == active_lfo) {
                    _ = writer.print(
                        "{s}[LFO {d}]{s} ",
                        .{ ANSI_REVERSE, i, ANSI_RESET },
                    ) catch {};
                } else {
                    _ = writer.print("[LFO {d}] ", .{ i }) catch {};
                }
            }
            _ = writer.writeAll("\r\n\r\n") catch {};
        },

        else => {},
    }
}

pub var sequencer: Sequencer = undefined;

pub const Sequencer = struct {
    freq_steps: [32]std.atomic.Value(f32),
    midi_steps: [32]std.atomic.Value(f32),

    running: bool = false,

    pub fn init() Sequencer {
        var freq_steps: [32]std.atomic.Value(f32) = undefined;
        var midi_steps: [32]std.atomic.Value(f32) = undefined;

        for (0..32) |i| {
            freq_steps[i] = std.atomic.Value(f32).init(-1.0);
            midi_steps[i] = std.atomic.Value(f32).init(-1.0);
        }

        return .{
            .freq_steps = freq_steps,
            .midi_steps = midi_steps,
        };
    }

    pub fn setNote(self: *Sequencer, index: usize, midi_note: f32) void {
        if (index >= 32) return;

        self.midi_steps[index].store(midi_note, .release);

        if (midi_note == -2.0) {
            self.freq_steps[index].store(-2.0, .release);  // Preserve hold
        } else if (midi_note < 0.0) {
            self.freq_steps[index].store(-1.0, .release);  // Rest
        } else {
            const freq = midiNoteToFreq(@intFromFloat(midi_note));
            self.freq_steps[index].store(freq, .release);
        }
    }

    pub fn clearStep(self: *Sequencer, index: usize) void {
        if (index >= 32) return;
        self.midi_steps[index].store(-1.0, .release);
        self.freq_steps[index].store(-1.0, .release);
    }

    pub fn getFreq(self: *Sequencer, index: usize) f32 {
        return self.freq_steps[index].load(.acquire);
    }
};

fn midiNoteToFreq(note: i8) f32 {
    return 440.0 *
        std.math.pow(f32, 2.0,
            (@as(f32, @floatFromInt(note)) - 69.0) / 12.0);
}

const ViewMode = enum { Master, Performance, Amp, Filter, LFO, Oscillators, Sequencer };
var current_view: ViewMode = .Master;
var active_osc: u8 = 1; // 1,2,3
var active_lfo: u8 = 1; // 1,2

pub const SharedParams = struct {

    master_volume: std.atomic.Value(f32),
    master_drive: std.atomic.Value(f32),

    amp_attack: std.atomic.Value(f32),
    amp_decay: std.atomic.Value(f32),
    amp_sustain: std.atomic.Value(f32),
    amp_release: std.atomic.Value(f32),

    filter_cutoff: std.atomic.Value(f32),
    filter_resonance: std.atomic.Value(f32),
    filter_attack: std.atomic.Value(f32),
    filter_decay: std.atomic.Value(f32),
    filter_sustain: std.atomic.Value(f32),
    filter_release: std.atomic.Value(f32),
    filter_feedback: std.atomic.Value(f32),
    filter_key_tracking: std.atomic.Value(f32),

    perf_portamento: std.atomic.Value(f32),

    // LFO 1
    lfo1_rate: std.atomic.Value(f32),
    lfo1_wave: std.atomic.Value(f32),
    lfo1_depth: std.atomic.Value(f32),
    lfo1_cutoff: std.atomic.Value(f32),
    lfo1_resonance: std.atomic.Value(f32),
    lfo1_amp: std.atomic.Value(f32),
    lfo1_volume: std.atomic.Value(f32),

    // LFO 2
    lfo2_rate: std.atomic.Value(f32),
    lfo2_wave: std.atomic.Value(f32),
    lfo2_depth: std.atomic.Value(f32),
    lfo2_cutoff: std.atomic.Value(f32),
    lfo2_resonance: std.atomic.Value(f32),
    lfo2_amp: std.atomic.Value(f32),
    lfo2_volume: std.atomic.Value(f32),

    osc1_wave: std.atomic.Value(f32),
    osc1_wave2: std.atomic.Value(f32),
    osc1_crossfade: std.atomic.Value(f32),
    osc1_level: std.atomic.Value(f32),
    osc1_octave: std.atomic.Value(f32),
    osc1_semitones: std.atomic.Value(f32),
    osc1_detune: std.atomic.Value(f32),
    osc1_unison_count: std.atomic.Value(f32),
    osc1_high: std.atomic.Value(f32),

    osc2_wave: std.atomic.Value(f32),
    osc2_wave2: std.atomic.Value(f32),
    osc2_crossfade: std.atomic.Value(f32),
    osc2_level: std.atomic.Value(f32),
    osc2_octave: std.atomic.Value(f32),
    osc2_semitones: std.atomic.Value(f32),
    osc2_detune: std.atomic.Value(f32),
    osc2_unison_count: std.atomic.Value(f32),
    osc2_high: std.atomic.Value(f32),

    osc3_wave: std.atomic.Value(f32),
    osc3_wave2: std.atomic.Value(f32),
    osc3_crossfade: std.atomic.Value(f32),
    osc3_level: std.atomic.Value(f32),
    osc3_octave: std.atomic.Value(f32),
    osc3_semitones: std.atomic.Value(f32),
    osc3_detune: std.atomic.Value(f32),
    osc3_unison_count: std.atomic.Value(f32),
    osc3_high: std.atomic.Value(f32),

    sequencer_enabled: std.atomic.Value(f32),
    sequencer_tempo: std.atomic.Value(f32),
    sequencer_index: std.atomic.Value(f32),
    sequencer_len: std.atomic.Value(f32),

    // delay_time_ms: std.atomic.Value(f32),  
    // delay_feedback: std.atomic.Value(f32),       
    // delay_mix: std.atomic.Value(f32),            
    
    pub fn init() SharedParams {
        return .{

            //MASTER CONTROL
            .master_volume = .init(0.8),
            .master_drive = .init(1.0),

            //AMP CONTROL
            .amp_attack = .init(0.01),
            .amp_decay = .init(0.1),
            .amp_sustain = .init(0.8),
            .amp_release = .init(0.2),

            //FILTER CONTROL
            .filter_cutoff = .init(800.0),
            .filter_resonance = .init(0.4),
            .filter_attack = .init(0.01),
            .filter_decay = .init(0.1),
            .filter_sustain = .init(0.8),
            .filter_release = .init(0.2),
            .filter_feedback = .init(0.0),
            .filter_key_tracking = .init(1.0),

            .perf_portamento = .init(0.0),

            // LFO 1
            .lfo1_rate = .init(2.0),
            .lfo1_wave = .init(1.0), // 1=sine, 2=tri, 3=saw, 4=square
            .lfo1_depth = .init(1.0),
            .lfo1_cutoff = .init(0.0),
            .lfo1_resonance = .init(0.0),
            .lfo1_amp = .init(0.0),
            .lfo1_volume = .init(0.0),

            // LFO 2
            .lfo2_rate = .init(0.5),
            .lfo2_wave = .init(1.0),
            .lfo2_depth = .init(1.0),
            .lfo2_cutoff = .init(0.0),
            .lfo2_resonance = .init(0.0),
            .lfo2_amp = .init(0.0),
            .lfo2_volume = .init(0.0),

            .osc1_wave = .init(3.0),
            .osc1_wave2 = .init(3.0),
            .osc1_crossfade = .init(0.0),
            .osc1_level = .init(1.0),
            .osc1_octave = .init(0.0),
            .osc1_semitones = .init(0.0),
            .osc1_detune = .init(0.0),
            .osc1_unison_count = .init(1.0),
            .osc1_high = .init(0.0),

            .osc2_wave = .init(3.0),
            .osc2_wave2 = .init(3.0),
            .osc2_crossfade = .init(0.0),
            .osc2_level = .init(1.0),
            .osc2_octave = .init(-1.0),
            .osc2_semitones = .init(0.0),
            .osc2_detune = .init(0.0),
            .osc2_unison_count = .init(1.0),
            .osc2_high = .init(0.0),

            .osc3_wave = .init(3.0),
            .osc3_wave2 = .init(3.0),
            .osc3_crossfade = .init(0.0),
            .osc3_level = .init(1.0),
            .osc3_octave = .init(0.0),
            .osc3_semitones = .init(0.0),
            .osc3_detune = .init(0.0),
            .osc3_unison_count = .init(1.0),
            .osc3_high = .init(1.0),

            //SEQUENCER CONTROL
            .sequencer_tempo = .init(2.0),
            .sequencer_enabled = .init(0.0),
            .sequencer_index = .init(0.0),
            .sequencer_len = .init(8.0),

            // .delay_time_ms = .init(250.0),
            // .delay_feedback = .init(0.4),
            // .delay_mix = .init(0.3),
        };
    }

    pub const SharedSequencer = struct {
        steps: [32]std.atomic.Value(i8),
        tempo_hz: std.atomic.Value(f32),
    };

};

const Param = struct {
    name: []const u8,
    value: *std.atomic.Value(f32),
    min: f32,
    max: f32,
    step: f32,
    // controller_map: f32,

    fn inc(self: *Param) void {
        const v = self.value.load(.acquire);
        self.value.store(@min(v + self.step, self.max), .release);
    }

    fn dec(self: *Param) void {
        const v = self.value.load(.acquire);
        self.value.store(@max(v - self.step, self.min), .release);
    }

    fn get(self: *const Param) f32 {
        return self.value.load(.acquire);
    }
};

pub fn enableRawMode(orig: *std.posix.termios) !void {
    orig.* = try std.posix.tcgetattr(stdin_fd);

    var raw = orig.*;

    {
        var flags: u64 = @bitCast(raw.lflag);
        flags &= ~(@as(u64,
            c.ECHO |
            c.ICANON 
            // c.ISIG
        ));
        raw.lflag = @bitCast(flags);
    }

    {
        var flags: u64 = @bitCast(raw.iflag);
        flags &= ~(@as(u64,
            c.IXON |
            c.ICRNL
        ));
        raw.iflag = @bitCast(flags);
    }

    {
        var flags: u64 = @bitCast(raw.oflag);
        flags &= ~(@as(u64, c.OPOST));
        raw.oflag = @bitCast(flags);
    }

    {
        var flags: u64 = @bitCast(raw.cflag);
        flags |= @as(u64, c.CS8);
        raw.cflag = @bitCast(flags);
    }

    try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);
}
fn disableRawMode(orig: *const std.posix.termios) !void {
    _ = try std.posix.tcsetattr(stdin_fd, .FLUSH, orig.*);
}

fn draw(params: []Param, cursor: usize, writer: *std.io.Writer) !void {
    // Clear screen + home
    _ = writer.writeAll("\x1b[2J\x1b[H") catch {};

    drawViewHeader(writer);
    drawSubHeader(writer);

    _ = writer.writeAll("↑↓ select  ←→ adjust \r\n\r\n") catch {};

    const view: []const u8 = switch(current_view) {
        .Oscillators => "Osc",
        .Sequencer => "Sequencer",
        .Filter => "Filter",
        .Master => "Master",
        .Amp => "Amp",
        .Performance => "Perf",
        .LFO => "LFO",
    };
    

    for (params, 0..) |p, i| {
        if (!std.mem.startsWith(u8, p.name, view)) continue;
        if (!paramVisible(p)) continue;

        const label = stripFirstWord(p.name);

        if (i == cursor) {
            if (std.mem.endsWith(u8, p.name, "Wave")) {
                _ = writer.print("> {s:<10} {s}\r\n", .{
                    label,
                    waveName(p.get()),
                }) catch {};
            } else {
                _ = writer.print("> {s:<10} {d:.3}\r\n", .{
                    label,
                    p.get(),
                }) catch {};
            }
        } else {
            if (std.mem.endsWith(u8, p.name, "Wave")) {
                _ = writer.print("  {s:<10} {s}\r\n", .{
                    label,
                    waveName(p.get()),
                }) catch {};
            } else {
                _ = writer.print("  {s:<10} {d:.3}\r\n", .{
                    label,
                    p.get(),
                }) catch {};
            }
        }
    }


    if (current_view == .Sequencer){
        _ = writer.print("\r\n", .{  }) catch {};
        _ = writer.print("Sequencer:\r\n", .{  }) catch {};
        for (sequencer.midi_steps, params.len..) |p, i| {
            var buf: [3]u8 = undefined;
            const step: i8 = @as(i8, @intCast(i)) - @as(i8, @intCast(params.len));
            if (i == cursor) {
                _ = writer.print("> [ {s} ]", .{ midiToName(@intFromFloat(p.load(.acquire)), &buf) }) catch {};
            } else {
                _ = writer.print("  [ {s} ]", .{ midiToName(@intFromFloat(p.load(.acquire)), &buf) }) catch {};
            }
            if (step > 0 and @mod(step + 1 , 8) == 0){
                _ = writer.print("\r\n", .{  }) catch {};
            }
        }
    }
    writer.flush() catch {};
}

pub fn run(shared: *SharedParams) !void {

    var buffer: [4096]u8 = undefined;
    var writer = std.fs.File.writer(std.fs.File.stdout(), &buffer).interface;

    var orig_term: std.posix.termios = undefined;
    try enableRawMode(&orig_term);


    var params = [_]Param{

        .{ .name = "Master Volume", .value = &shared.master_volume, .min = 0.0, .max = 1.0, .step = 0.02 },
        .{ .name = "Master Drive", .value = &shared.master_drive, .min = 1.0, .max = 4.0, .step = 0.02 },

        // Amp envelope
        .{ .name = "Amp Attack", .value = &shared.amp_attack, .min = 0.001, .max = 2.0, .step = 0.01 },
        .{ .name = "Amp Decay", .value = &shared.amp_decay, .min = 0.001, .max = 2.0, .step = 0.01 },
        .{ .name = "Amp Sustain", .value = &shared.amp_sustain, .min = 0.0, .max = 1.0, .step = 0.02 },
        .{ .name = "Amp Release", .value = &shared.amp_release, .min = 0.001, .max = 5.0, .step = 0.05 },

        // Filter envelope
        .{ .name = "Filter Cutoff", .value = &shared.filter_cutoff, .min = 20.0, .max = 8000.0, .step = 20.0 },
        .{ .name = "Filter Resonance", .value = &shared.filter_resonance, .min = 0.0, .max = 1.0, .step = 0.02 },
        .{ .name = "Filter Attack", .value = &shared.filter_attack, .min = 0.001, .max = 2.0, .step = 0.01 },
        .{ .name = "Filter Decay", .value = &shared.filter_decay, .min = 0.001, .max = 2.0, .step = 0.01 },
        .{ .name = "Filter Sustain", .value = &shared.filter_sustain, .min = 0.0, .max = 1.0, .step = 0.02 },
        .{ .name = "Filter Release", .value = &shared.filter_release, .min = 0.001, .max = 5.0, .step = 0.05 },
        .{ .name = "Filter Key Track", .value = &shared.filter_key_tracking, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "Filter Feedback", .value = &shared.filter_feedback, .min = 0.00, .max = 0.25, .step = 0.01 },

        .{ .name = "Perf Portamento", .value = &shared.perf_portamento, .min = 0.0, .max = 1.0, .step = 0.01 },

        // -------- LFO 1 --------
        .{ .name = "LFO1 Rate", .value = &shared.lfo1_rate, .min = 0.05, .max = 20.0, .step = 0.05 },
        .{ .name = "LFO1 Wave", .value = &shared.lfo1_wave, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "LFO1 Depth", .value = &shared.lfo1_depth, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "LFO1 → Cut", .value = &shared.lfo1_cutoff, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "LFO1 → Res", .value = &shared.lfo1_resonance, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "LFO1 → Amp", .value = &shared.lfo1_amp, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "LFO1 → Vol", .value = &shared.lfo1_volume, .min = 0.0, .max = 1.0, .step = 0.05 },

        // -------- LFO 2 --------
        .{ .name = "LFO2 Rate", .value = &shared.lfo2_rate, .min = 0.05, .max = 20.0, .step = 0.05 },
        .{ .name = "LFO2 Wave", .value = &shared.lfo2_wave, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "LFO2 Depth", .value = &shared.lfo2_depth, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "LFO2 → Cut", .value = &shared.lfo2_cutoff, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "LFO2 → Res", .value = &shared.lfo2_resonance, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "LFO2 → Amp", .value = &shared.lfo2_amp, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "LFO2 → Vol", .value = &shared.lfo2_volume, .min = 0.0, .max = 1.0, .step = 0.05 },

        // Osc 1
        .{ .name = "Osc1 Wave", .value = &shared.osc1_wave, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc1 Wave2", .value = &shared.osc1_wave2, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc1 Crossfade", .value = &shared.osc1_crossfade, .min = 0.05, .max = 20.0, .step = 0.05 },
        .{ .name = "Osc1 Level", .value = &shared.osc1_level, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "Osc1 Octave", .value = &shared.osc1_octave, .min = -4.0, .max = 4.0, .step = 1.00 },
        .{ .name = "Osc1 Semitones", .value = &shared.osc1_semitones, .min = -12.0, .max = 12.0, .step = 1.00 },
        .{ .name = "Osc1 Unison", .value = &shared.osc1_unison_count, .min = 1.0, .max = 8.0, .step = 1.0 },
        .{ .name = "Osc1 Detune", .value = &shared.osc1_detune, .min = 0.0, .max = 100.0, .step = 1.0 },
        .{ .name = "Osc1 Voice Priority", .value = &shared.osc1_high, .min = 0.0, .max = 1.0, .step = 1.0 },

        // Osc 2
        .{ .name = "Osc2 Wave", .value = &shared.osc2_wave, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc2 Wave2", .value = &shared.osc2_wave2, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc2 Crossfade", .value = &shared.osc2_crossfade, .min = 0.05, .max = 20.0, .step = 0.05 },
        .{ .name = "Osc2 Level", .value = &shared.osc2_level, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "Osc2 Octave", .value = &shared.osc2_octave, .min = -4.0, .max = 4.0, .step = 1.00 },
        .{ .name = "Osc2 Semitones", .value = &shared.osc2_semitones, .min = -12.0, .max = 12.0, .step = 1.00 },
        .{ .name = "Osc2 Unison", .value = &shared.osc2_unison_count, .min = 1.0, .max = 8.0, .step = 1.0 },
        .{ .name = "Osc2 Detune", .value = &shared.osc2_detune, .min = 0.0, .max = 100.0, .step = 1.0 },
        .{ .name = "Osc2 Voice Priority", .value = &shared.osc2_high, .min = 0.0, .max = 1.0, .step = 1.0 },

        // Osc 3
        .{ .name = "Osc3 Wave", .value = &shared.osc3_wave, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc3 Wave2", .value = &shared.osc3_wave2, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc3 Crossfade", .value = &shared.osc3_crossfade, .min = 0.05, .max = 20.0, .step = 0.05 },
        .{ .name = "Osc3 Level", .value = &shared.osc3_level, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "Osc3 Octave", .value = &shared.osc3_octave, .min = -4.0, .max = 4.0, .step = 1.00 },
        .{ .name = "Osc3 Semitones", .value = &shared.osc3_semitones, .min = -12.0, .max = 12.0, .step = 1.00 },
        .{ .name = "Osc3 Unison", .value = &shared.osc3_unison_count, .min = 1.0, .max = 8.0, .step = 1.0 },
        .{ .name = "Osc3 Detune", .value = &shared.osc3_detune, .min = -100.0, .max = 100.0, .step = 1.0 },
        .{ .name = "Osc3 Voice Priority", .value = &shared.osc3_high, .min = 0.0, .max = 1.0, .step = 1.0 },

        .{ .name = "Sequencer Enabled", .value = &shared.sequencer_enabled, .min = 0.0, .max = 1.0, .step = 1.0 },
        .{ .name = "Sequencer Speed", .value = &shared.sequencer_tempo, .min = 1.0, .max = 20.0, .step = 0.25 },
        .{ .name = "Sequencer Position", .value = &shared.sequencer_index, .min = 1.0, .max = 32.0, .step = 1.0 },
        .{ .name = "Sequence Length", .value = &shared.sequencer_len, .min = 0.0, .max = 32.0, .step = 1.0 },

        // .{ .name = "Delay Time ms", .value = &shared.delay_time_ms, .min = 0.0, .max = 1000.0, .step = 20.0 },
        // .{ .name = "Delay Feedback", .value = &shared.delay_feedback, .min = 0.0, .max = 0.95, .step = 0.05 },
        // .{ .name = "Delay Mix", .value = &shared.delay_mix, .min = 0.0, .max = 1.0, .step = 0.05 },
    };

    sequencer = Sequencer.init();

    var cursor: usize = 0;
    var buf: [8]u8 = undefined;

    
    while (true) {
        try draw(&params, cursor, &writer);

        const view = switch(current_view){
            .Oscillators => "Osc",
            .Sequencer => "Sequencer",
            .Filter => "Filter",
            .Master => "Master",
            .Amp => "Amp",
            .Performance => "Perf",
            .LFO => "LFO",
        };

        const n = try std.posix.read(stdin_fd, &buf);

        // Single-key commands
        if (n == 1) {
            switch (buf[0]) {
                '1', '2', '3' => {
                    const v: u8 = buf[0] - '0';

                    switch (current_view) {
                        .Oscillators => {
                            if (v <= 3) {
                                active_osc = v;
                                cursor = findFirstIndex(0, &params,
                                    switch (v) {
                                        1 => "Osc1",
                                        2 => "Osc2",
                                        3 => "Osc3",
                                        else => unreachable,
                                    }
                                );
                            }
                        },

                        .LFO => {
                            if (v <= 2) {
                                active_lfo = v;
                                cursor = findFirstIndex(0, &params,
                                    if (v == 1) "LFO1" else "LFO2"
                                );
                            }
                        },

                        else => {},
                    }
                },
                'm' => {
                    current_view = .Master;
                    cursor = findFirstIndex(0, &params, "Master");
                },
                'p' => {
                    current_view = .Performance;
                    cursor = findFirstIndex(0, &params, "Perf");
                },
                'l' => {
                    current_view = .LFO;
                    cursor = findFirstIndex(0, &params, "LFO");
                },
                'f' => {
                    current_view = .Filter;
                    cursor = findFirstIndex(0, &params, "Filter");
                },
                's' => {
                    current_view = .Sequencer;
                    cursor = findFirstIndex(0, &params, "Sequencer");
                },
                'o' => {
                    current_view = .Oscillators;
                    cursor = findFirstIndex(0, &params, "Osc");
                },
                'a' => {
                    current_view = .Amp;
                    cursor = findFirstIndex(0, &params, "Amp");
                },
                // 'c' => {
                //     midi_learn_state.armed.store(true, .release);
                //     midi_learn_state.target_param_index.store(
                //         @intCast(cursor),
                //         .release,
                //     );
                // },
                'q' => break,

                'r' => { // rest
                    if (cursor >= params.len) {
                        const step = cursor - params.len;
                        sequencer.setNote(step, -1);
                    }
                },

                'h' => { // hold
                    if (cursor >= params.len) {
                        const step = cursor - params.len;
                        sequencer.setNote(step, -2);
                    }
                },

                else => {},
            }
        }


        // Normal arrow keys
        if (n == 3 and buf[0] == 0x1b and buf[1] == '[') {
            switch (buf[2]) {
                'A' => {cursor = findFirstPrevious(cursor, &params, view);}, // up
                'B' => {cursor = findFirstIndex(cursor, &params, view);}, // down
                'C' => {
                    if (cursor < params.len) {
                        params[cursor].inc();
                    } else {
                        const step = cursor - params.len;
                        const cur = sequencer.midi_steps[step].load(.acquire);
                        if (cur < 127 - 1){
                            sequencer.setNote(step, cur + 1);
                        }
                    }
                },
                'D' => {
                    if (cursor < params.len) {
                        params[cursor].dec();
                    } else {
                        const step = cursor - params.len;
                        const cur = sequencer.midi_steps[step].load(.acquire);
                        if (cur > -2) {
                            sequencer.setNote(step, cur - 1);
                        }
                    }
                },
                else => {},
            }
        }

        // Shift + Arrow keys (octave jump)
        else if (n == 6 and buf[0] == 0x1b and buf[1] == '[' and
                 buf[2] == '1' and buf[3] == ';' and buf[4] == '2')
        {
            switch (buf[5]) {
                'C' => { // Shift + Right → octave up
                    if (cursor >= params.len) {
                        const step = cursor - params.len;
                        const cur = sequencer.midi_steps[step].load(.acquire);
                        if (cur + 12 < 127){
                            sequencer.setNote(step, cur + 12);
                        }
                    }
                },
                'D' => { // Shift + Left → octave down
                    if (cursor >= params.len) {
                        const step = cursor - params.len;
                        const cur = sequencer.midi_steps[step].load(.acquire);
                        if (cur > 11){
                            sequencer.setNote(step, cur - 12);
                        }
                    }
                },
                else => {},
            }
        }
    }
    try disableRawMode(&orig_term);
}

fn findFirstIndex(start: usize, params: []Param, contains: []const u8) usize {
    for (start..params.len) |i| {
        if (i == start) continue;
        if (std.mem.startsWith(u8, params[i].name, contains)) return i;
    }
    return start;
}

fn findFirstPrevious(start: usize, params: []Param, contains: []const u8) usize {
    for (1..start + 1) |i| {
        const index = start - i;
        if (std.mem.startsWith(u8, params[index].name, contains)) return index;
    }
    return start;
}

const note_names = [_][]const u8{
    "C ", "C#", "D ", "D#", "E ", "F ",
    "F#", "G ", "G#", "A ", "A#", "B ",
};

fn midiToName(note: i8, buf: []u8) []u8 {
    var rest: [3]u8 = [3]u8{ ' ', ' ', ' '};
    var hold: [3]u8 = [3]u8{ '-', '-', '-'};
    if (note == -1) return &rest;
    if (note == -2) return &hold;
    const octave = (@divFloor(note, 12)) + 1;
    const name = note_names[@intCast(@rem(note, 12))];
    return std.fmt.bufPrint(buf, "{s}{d}", .{ name, octave }) catch &rest;
}

fn waveName(v: f32) []const u8 {
    return switch (@as(usize, @intFromFloat(v))) {
        1 => "SIN",
        2 => "TRI",
        3 => "SAW",
        4 => "SQR",
        else => "???",
    };
}

fn paramVisible(p: Param) bool {
    return switch (current_view) {
        .Oscillators => blk: {
            const prefix = switch (active_osc) {
                1 => "Osc1",
                2 => "Osc2",
                3 => "Osc3",
                else => unreachable,
            };
            break :blk std.mem.startsWith(u8, p.name, prefix);
        },
        .LFO => blk: {
            const prefix = if (active_lfo == 1) "LFO1" else "LFO2";
            break :blk std.mem.startsWith(u8, p.name, prefix);
        },
        else => true,
    };
}

fn stripFirstWord(name: []const u8) []const u8 {
    for (name, 0..) |n, i| {
        if (n == ' ') {
            return name[i + 1 ..];
        }
    }
    return name;
}

