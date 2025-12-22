const std = @import("std");
const c = @cImport({
    @cInclude("termios.h");
});

const stdin_fd = std.posix.STDIN_FILENO;
const stdout_fd = std.posix.STDOUT_FILENO;

pub var sequencer: Sequencer = undefined;

pub const Sequencer = struct {
    /// Frequency used by audio engine
    freq_steps: [32]std.atomic.Value(f32),

    /// MIDI note stored only for UI display
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

        if (midi_note < 0.0) {
            self.freq_steps[index].store(-1.0, .release);
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

pub const SharedParams = struct {
    sequencer_tempo: std.atomic.Value(f32),
    cutoff: std.atomic.Value(f32),
    resonance: std.atomic.Value(f32),

    master_volume: std.atomic.Value(f32),
    drive: std.atomic.Value(f32),

    amp_attack: std.atomic.Value(f32),
    amp_decay: std.atomic.Value(f32),
    amp_sustain: std.atomic.Value(f32),
    amp_release: std.atomic.Value(f32),

    filter_attack: std.atomic.Value(f32),
    filter_decay: std.atomic.Value(f32),
    filter_sustain: std.atomic.Value(f32),
    filter_release: std.atomic.Value(f32),

    portamento: std.atomic.Value(f32),
    key_tracking: std.atomic.Value(f32),

    osc1_wave: std.atomic.Value(f32),
    osc1_level: std.atomic.Value(f32),
    osc1_octave: std.atomic.Value(f32),
    osc1_semitones: std.atomic.Value(f32),
    osc1_detune: std.atomic.Value(f32),
    osc1_unison_count: std.atomic.Value(f32),

    osc2_wave: std.atomic.Value(f32),
    osc2_level: std.atomic.Value(f32),
    osc2_octave: std.atomic.Value(f32),
    osc2_semitones: std.atomic.Value(f32),
    osc2_detune: std.atomic.Value(f32),
    osc2_unison_count: std.atomic.Value(f32),

    osc3_wave: std.atomic.Value(f32),
    osc3_level: std.atomic.Value(f32),
    osc3_octave: std.atomic.Value(f32),
    osc3_semitones: std.atomic.Value(f32),
    osc3_detune: std.atomic.Value(f32),
    osc3_unison_count: std.atomic.Value(f32),

    sequencer_index: std.atomic.Value(f32),
    sequencer_len: std.atomic.Value(f32),

    pub fn init() SharedParams {
        return .{
            .sequencer_tempo = .init(2.0),
            .cutoff = .init(800.0),
            .resonance = .init(0.4),

            .master_volume = .init(0.8),
            .drive = .init(1.0),

            .amp_attack = .init(0.01),
            .amp_decay = .init(0.1),
            .amp_sustain = .init(0.8),
            .amp_release = .init(0.2),

            .filter_attack = .init(0.01),
            .filter_decay = .init(0.1),
            .filter_sustain = .init(0.8),
            .filter_release = .init(0.2),

            .portamento = .init(0.0),
            .key_tracking = .init(1.0),

            .osc1_wave = .init(1.0),
            .osc1_level = .init(1.0),
            .osc1_octave = .init(0.0),
            .osc1_semitones = .init(0.0),
            .osc1_detune = .init(0.0),
            .osc1_unison_count = .init(1.0),

            .osc2_wave = .init(1.0),
            .osc2_level = .init(0.0),
            .osc2_octave = .init(0.0),
            .osc2_semitones = .init(0.0),
            .osc2_detune = .init(0.0),
            .osc2_unison_count = .init(1.0),

            .osc3_wave = .init(1.0),
            .osc3_level = .init(0.0),
            .osc3_octave = .init(0.0),
            .osc3_semitones = .init(0.0),
            .osc3_detune = .init(0.0),
            .osc3_unison_count = .init(1.0),
            .sequencer_index = .init(0.0),
            .sequencer_len = .init(8.0),
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
    _ = writer.writeAll("↑↓ select  ←→ adjust \r\n\r\n") catch {};
    
    for (params, 0..) |p, i| {
        if (i == cursor) {
            _ = writer.print("> {s:<10} {d:.3}\r\n", .{ p.name, p.get() }) catch {};
        } else {
            _ = writer.print("  {s:<10} {d:.3}\r\n", .{ p.name, p.get() }) catch {};
        }
    }
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
    writer.flush() catch {};
}
pub fn run(shared: *SharedParams) !void {

    var buffer: [4096]u8 = undefined;
    var writer = std.fs.File.writer(std.fs.File.stdout(), &buffer).interface;

    var orig_term: std.posix.termios = undefined;
    try enableRawMode(&orig_term);


    var params = [_]Param{
        .{ .name = "Sequencer Speed", .value = &shared.sequencer_tempo, .min = 1.0, .max = 20.0, .step = 0.25 },
        .{ .name = "Cutoff", .value = &shared.cutoff, .min = 20.0, .max = 8000.0, .step = 20.0 },
        .{ .name = "Resonance", .value = &shared.resonance, .min = 0.0, .max = 1.0, .step = 0.02 },

        .{ .name = "Master Volume", .value = &shared.master_volume, .min = 0.0, .max = 1.0, .step = 0.02 },
        .{ .name = "Drive", .value = &shared.drive, .min = 1.0, .max = 4.0, .step = 0.02 },

        // Amp envelope
        .{ .name = "Amp Attack", .value = &shared.amp_attack, .min = 0.001, .max = 2.0, .step = 0.01 },
        .{ .name = "Amp Decay", .value = &shared.amp_decay, .min = 0.001, .max = 2.0, .step = 0.01 },
        .{ .name = "Amp Sustain", .value = &shared.amp_sustain, .min = 0.0, .max = 1.0, .step = 0.02 },
        .{ .name = "Amp Release", .value = &shared.amp_release, .min = 0.001, .max = 5.0, .step = 0.05 },

        // Filter envelope
        .{ .name = "Filt Attack", .value = &shared.filter_attack, .min = 0.001, .max = 2.0, .step = 0.01 },
        .{ .name = "Filt Decay", .value = &shared.filter_decay, .min = 0.001, .max = 2.0, .step = 0.01 },
        .{ .name = "Filt Sustain", .value = &shared.filter_sustain, .min = 0.0, .max = 1.0, .step = 0.02 },
        .{ .name = "Filt Release", .value = &shared.filter_release, .min = 0.001, .max = 5.0, .step = 0.05 },

        .{ .name = "Portamento", .value = &shared.portamento, .min = 0.0, .max = 1.0, .step = 0.01 },
        .{ .name = "Key Track", .value = &shared.key_tracking, .min = 0.0, .max = 1.0, .step = 0.05 },

        // Osc 1
        .{ .name = "Osc1 Wave", .value = &shared.osc1_wave, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc1 Level", .value = &shared.osc1_level, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "Osc1 Octave", .value = &shared.osc1_octave, .min = -4.0, .max = 4.0, .step = 1.00 },
        .{ .name = "Osc1 Semitones", .value = &shared.osc1_semitones, .min = -12.0, .max = 12.0, .step = 1.00 },
        .{ .name = "Osc1 Unison", .value = &shared.osc1_unison_count, .min = 1.0, .max = 8.0, .step = 1.0 },
        .{ .name = "Osc1 Detune", .value = &shared.osc1_detune, .min = 0.0, .max = 100.0, .step = 1.0 },

        // Osc 2
        .{ .name = "Osc2 Wave", .value = &shared.osc2_wave, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc2 Level", .value = &shared.osc2_level, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "Osc2 Octave", .value = &shared.osc2_octave, .min = -4.0, .max = 4.0, .step = 1.00 },
        .{ .name = "Osc2 Semitones", .value = &shared.osc2_semitones, .min = -12.0, .max = 12.0, .step = 1.00 },
        .{ .name = "Osc2 Unison", .value = &shared.osc2_unison_count, .min = 1.0, .max = 8.0, .step = 1.0 },
        .{ .name = "Osc2 Detune", .value = &shared.osc2_detune, .min = 0.0, .max = 100.0, .step = 1.0 },

        // Osc 3
        .{ .name = "Osc3 Wave", .value = &shared.osc3_wave, .min = 1.0, .max = 4.0, .step = 1.0 },
        .{ .name = "Osc3 Level", .value = &shared.osc3_level, .min = 0.0, .max = 1.0, .step = 0.05 },
        .{ .name = "Osc3 Octave", .value = &shared.osc3_octave, .min = -4.0, .max = 4.0, .step = 1.00 },
        .{ .name = "Osc3 Semitones", .value = &shared.osc3_semitones, .min = -12.0, .max = 12.0, .step = 1.00 },
        .{ .name = "Osc3 Unison", .value = &shared.osc3_unison_count, .min = 1.0, .max = 8.0, .step = 1.0 },
        .{ .name = "Osc3 Detune", .value = &shared.osc3_detune, .min = -100.0, .max = 100.0, .step = 1.0 },

        .{ .name = "Sequencer Position", .value = &shared.sequencer_index, .min = 1.0, .max = 32.0, .step = 1.0 },
        .{ .name = "Sequence Length", .value = &shared.sequencer_len, .min = 0.0, .max = 32.0, .step = 1.0 },
    };

    sequencer = Sequencer.init();

    var cursor: usize = 0;
    var buf: [8]u8 = undefined;

    
    while (true) {
        try draw(&params, cursor, &writer);

        const n = try std.posix.read(stdin_fd, &buf);
        if (n == 1 and buf[0] == 'q') break;

        // Normal arrow keys
        if (n == 3 and buf[0] == 0x1b and buf[1] == '[') {
            switch (buf[2]) {
                'A' => {if (cursor > 0) cursor -= 1;}, // up
                'B' => {if (cursor + 1 < params.len + sequencer.freq_steps.len) cursor += 1; }, // down
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
                        if (cur > -1) {
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

const note_names = [_][]const u8{
    "C ", "C#", "D ", "D#", "E ", "F ",
    "F#", "G ", "G#", "A ", "A#", "B ",
};

fn midiToName(note: i8, buf: []u8) []u8 {
    var rest: [3]u8 = [3]u8{ ' ', ' ', ' '};
    if (note < 0) return &rest;
    const octave = (@divFloor(note, 12)) + 1;
    const name = note_names[@intCast(@rem(note, 12))];
    return std.fmt.bufPrint(buf, "{s}{d}", .{ name, octave }) catch &rest;
}
// fn midiToName(note: i8, buf: []u8) []u8 {
//     // Require at least 5 bytes
//     if (buf.len < 5) return buf[0..0];
//
//     // Default: blank
//     @memset(buf[0..5], ' ');
//
//     if (note < 0) {
//         return buf[0..5];
//     }
//
//     const octave: i8 = @divFloor(note, 12) - 1;
//     const idx: usize = @intCast(@rem(note, 12));
//     const name = note_names[idx]; // "C" or "C#"
//
//     // Write note name (1–2 chars)
//     buf[0] = name[0];
//     if (name.len == 2) {
//         buf[1] = '#';
//     }
//
//     // Write octave right-aligned in last 2 columns
//     // Positions: [3,4]
//     const oct_str = std.fmt.bufPrint(buf[3..5], "{d}", .{ octave }) catch return buf[0..5];
//
//     // Pad if octave is 1 char
//     if (oct_str.len == 1) {
//         buf[4] = oct_str[0];
//         buf[3] = ' ';
//     }
//
//     return buf[0..5];
// }

