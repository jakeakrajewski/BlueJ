const std = @import("std");

const c = @cImport({
    @cInclude("termios.h");
});


const stdin_fd = std.posix.STDIN_FILENO;
const stdout_fd = std.posix.STDOUT_FILENO;

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

    pub fn init() SharedParams {
        return .{
            .sequencer_tempo = .init(8.0),
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
        };
    }
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
    };


    var cursor: usize = 0;
    var buf: [3]u8 = undefined;

    while (true) {
        try draw(&params, cursor, &writer);

        const n = try std.posix.read(stdin_fd, &buf);
        if (n == 1 and buf[0] == 'q') break;

        if (n == 3 and buf[0] == 0x1b and buf[1] == '[') {
            switch (buf[2]) {
                'A' => {if (cursor > 0) cursor -= 1;},                 // up
                'B' => {if (cursor + 1 < params.len) cursor += 1;},   // down
                'C' => params[cursor].inc(),                       // right
                'D' => params[cursor].dec(),                       // left
                else => {},
            }
        }
    }
    try disableRawMode(&orig_term);
}

