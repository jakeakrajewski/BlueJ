const std = @import("std");

const c = @cImport({
    @cInclude("termios.h");
});


const stdin_fd = std.posix.STDIN_FILENO;
const stdout_fd = std.posix.STDOUT_FILENO;

/// ===============================
/// Shared Synth Parameters
/// ===============================
pub const SharedParams = struct {
    cutoff: std.atomic.Value(f32),
    resonance: std.atomic.Value(f32),
    attack: std.atomic.Value(f32),
    decay: std.atomic.Value(f32),
    sustain: std.atomic.Value(f32),
    release: std.atomic.Value(f32),

    pub fn init() SharedParams {
        return .{
            .cutoff = .init(800.0),
            .resonance = .init(0.4),
            .attack = .init(0.01),
            .decay = .init(0.1),
            .sustain = .init(0.8),
            .release = .init(0.2),
        };
    }
};

/// ===============================
/// Parameter UI Model
/// ===============================
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

/// ===============================
/// Termios Helpers
/// ===============================



pub fn enableRawMode(orig: *std.posix.termios) !void {
    orig.* = try std.posix.tcgetattr(stdin_fd);

    var raw = orig.*;

    // --- lflag ---
    {
        var flags: u64 = @bitCast(raw.lflag);
        flags &= ~(@as(u64,
            c.ECHO |
            c.ICANON |
            c.ISIG
        ));
        raw.lflag = @bitCast(flags);
    }

    // --- iflag ---
    {
        var flags: u64 = @bitCast(raw.iflag);
        flags &= ~(@as(u64,
            c.IXON |
            c.ICRNL
        ));
        raw.iflag = @bitCast(flags);
    }

    // --- oflag ---
    {
        var flags: u64 = @bitCast(raw.oflag);
        flags &= ~(@as(u64, c.OPOST));
        raw.oflag = @bitCast(flags);
    }

    // --- cflag ---
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


/// ===============================
/// Rendering
/// ===============================
fn draw(params: []Param, cursor: usize) !void {
    var buffer = try std.ArrayListUnmanaged(u8).initCapacity(@import("../memory/memory.zig").globalAlloc(), 4096);
    defer buffer.deinit(@import("../memory/memory.zig").globalAlloc());

    var value_writer = std.Io.Writer.Allocating.init(@import("../memory/memory.zig").globalAlloc());
    defer value_writer.deinit();
    const  writer_ptr = &value_writer.writer;

    // Clear screen + home
    _ = writer_ptr.writeAll("\x1b[2J\x1b[H") catch {};
    _ = writer_ptr.writeAll("ZIG SYNTH TUI\n") catch {};
    _ = writer_ptr.writeAll("↑↓ select  ←→ adjust  q quit\n\n") catch {};
    
    for (params, 0..) |p, i| {
        if (i == cursor) {
            _ = writer_ptr.print("> {s:<10} {d:.3}\n", .{ p.name, p.get() }) catch {};
        } else {
            _ = writer_ptr.print("  {s:<10} {d:.3}\n", .{ p.name, p.get() }) catch {};
        }
    }
    writer_ptr.flush() catch {};
}
/// ===============================
/// TUI Loop
/// ===============================
pub fn run(shared: *SharedParams) !void {
    var orig_term: std.posix.termios = undefined;
    try enableRawMode(&orig_term);

    var params = [_]Param{
        .{ .name = "Cutoff",    .value = &shared.cutoff,    .min = 20.0,  .max = 8000.0, .step = 20.0 },
        .{ .name = "Resonance", .value = &shared.resonance, .min = 0.0,   .max = 1.0,    .step = 0.02 },
        .{ .name = "Attack",    .value = &shared.attack,    .min = 0.001, .max = 2.0,    .step = 0.01 },
        .{ .name = "Decay",     .value = &shared.decay,     .min = 0.001, .max = 2.0,    .step = 0.01 },
        .{ .name = "Sustain",   .value = &shared.sustain,  .min = 0.0,   .max = 1.0,    .step = 0.02 },
        .{ .name = "Release",   .value = &shared.release,  .min = 0.001, .max = 5.0,    .step = 0.05 },
    };

    var cursor: usize = 0;
    var buf: [3]u8 = undefined;

    while (true) {
        try draw(&params, cursor);

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

