const std = @import("std");
const globalAlloc = @import("../memory/memory.zig").globalAlloc;

const TABLE_SIZE: usize = 2048;

// --- Waveform Structs ---
const SineTable = struct {
    data: []f32,
};
const SquareTable = struct {
    data: []f32,
};
const SawTable = struct {
    data: []f32,
};
const TriTable = struct {
    data: []f32,
};

// --- Container Struct for All Wavetables ---
pub const Wavetables = struct {
    sine: SineTable,
    square: SquareTable,
    saw: SawTable,
    tri: TriTable,
};

pub fn initTables() !Wavetables {
    const alloc = globalAlloc();
    
    const sine_data = try alloc.alloc(f32, TABLE_SIZE);
    const square_data = try alloc.alloc(f32, TABLE_SIZE);
    const saw_data = try alloc.alloc(f32, TABLE_SIZE);
    const tri_data = try alloc.alloc(f32, TABLE_SIZE);
    
    // --- Sine Wave --- 
    // Formula: sin(2 * pi * i / N)
    for (sine_data, 0..) |*v, i| {
        v.* = @sin(@as(f32, i) * 2.0 * std.math.pi / @as(f32, TABLE_SIZE));
    }
    
    // --- Square Wave --- 
    const half_size = TABLE_SIZE / 2;
    for (square_data, 0..) |*v, i| {
        // We use a slight offset at the transition point to ensure a value is set.
        if (i < half_size) {
            v.* = 1.0;
        } else {
            v.* = -1.0;
        }
    }
    
    // --- Sawtooth Wave --- 
    for (saw_data, 0..) |*v, i| {
        // 2 * (i / N) is a linear ramp from 0.0 to approx 2.0
        // -1.0 shifts it to be a linear ramp from -1.0 to approx 1.0
        v.* = (2.0 * @as(f32, i) / @as(f32, TABLE_SIZE)) - 1.0;
    }
    
    // --- Triangle Wave --- 
    const quarter_size = TABLE_SIZE / 4;
    for (tri_data, 0..) |*v, i| {
        const x = @as(f32, i);
        const n = @as(f32, TABLE_SIZE);
        
        // This calculates the value as a linear map from [0, 1] for the whole cycle,
        // which can then be folded into a triangle shape.
        const normalized_i = x / n;
        
        // The core logic is abs(2*x - 1) * 2 - 1, mapped to the range [-1, 1].
        // This is equivalent to: 
        // 4 * normalized_i (for i=0 to N/4)
        // 4 * (0.5 - normalized_i) (for i=N/4 to 3N/4)
        // 4 * (normalized_i - 1.0) (for i=3N/4 to N)
        // A cleaner way is using the `std.math.abs` of the sawtooth-like pattern.
        
        // This common simplification maps the absolute value of the sawtooth
        // (which is 0 at the center) into the range [-1, 1].
        const saw_val = (2.0 * normalized_i) - 1.0; // Range: [-1, 1]
        // This takes the absolute value, scales it (x2), and shifts it (-1)
        // to form the triangle wave in the range [-1, 1]
        v.* = 2.0 * std.math.abs(saw_val) - 1.0;
    }

    return Wavetables {
        .sine = .{ .data = sine_data },
        .square = .{ .data = square_data },
        .saw = .{ .data = saw_data },
        .tri = .{ .data = tri_data },
    };
}
