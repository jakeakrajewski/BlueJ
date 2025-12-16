const std = @import("std");

pub const TABLE_SIZE: usize = 2048;

/// ===========================================================
/// COMPTIME SINE TABLE
/// ===========================================================

pub const sine_table: [TABLE_SIZE]f32 =  blk: {
    @setEvalBranchQuota(2048);
    var t: [TABLE_SIZE]f32 = undefined;
    for (t, 0..) |_, i| {
        t[i] = @sin(
            2.0 * std.math.pi *
            @as(f32, @floatFromInt(i)) /
            @as(f32, @floatFromInt(TABLE_SIZE))
        );
    }
    break :blk t;
};

/// ===========================================================
/// TRIANGLE TABLE (BAND-LIMITED VIA PARTIAL SUM)
/// ===========================================================

pub const tri_table: [TABLE_SIZE]f32 =  blk: {
    @setEvalBranchQuota(2048 * 35);
    var t: [TABLE_SIZE]f32 = undefined;
    @memset(&t, 0.0);

    const max_harmonics = 32; // safe up to high mids

    for (1..max_harmonics + 1) |n| {
        if (n % 2 == 0) continue; // odd harmonics only
        const nf = @as(f32, @floatFromInt(n));
        const amp = 1.0 / (nf * nf);

        for (t, 0..) |_, i| {
            const phase =
                2.0 * std.math.pi *
                nf *
                @as(f32, @floatFromInt(i)) /
                @as(f32, @floatFromInt(TABLE_SIZE));
            t[i] += amp * @sin(phase);
        }
    }

    // normalize
    const scale = 8.0 / (std.math.pi * std.math.pi);
    for (t, 0..) |_, i| t[i] *= scale;

    break :blk t;
};

/// ===========================================================
/// PUBLIC TABLE CONTAINER
/// ===========================================================

pub const Wavetables = struct {
    sine: []const f32,
    tri: []const f32,

    pub fn init() Wavetables {
        return .{
            .sine = sine_table[0..],
            .tri = tri_table[0..],
        };
    }
};

/// ===========================================================
/// POLYBLEP HELPERS (FOR SAW & SQUARE)
/// ===========================================================

/// PolyBLEP correction function
pub inline fn polyBLEP(t: f32, dt: f32) f32 {
    if (t < dt) {
        const x = t / dt;
        return x + x - x * x - 1.0;
    }
    if (t > 1.0 - dt) {
        const x = (t - 1.0) / dt;
        return x * x + x + x + 1.0;
    }
    return 0.0;
}

/// Band-limited saw
pub inline fn sawPolyBLEP(phase: f32, phase_inc: f32) f32 {
    const t = phase;
    const dt = phase_inc;

    var v = 2.0 * t - 1.0;
    v -= polyBLEP(t, dt);
    return v;
}

/// Band-limited square
pub inline fn squarePolyBLEP(phase: f32, phase_inc: f32) f32 {
    const t = phase;
    const dt = phase_inc;

    var v: f32 = if (t < 0.5) 1.0 else -1.0;
    v += polyBLEP(t, dt);
    v -= polyBLEP(@mod(t + 0.5, 1.0), dt);
    return v;
}
