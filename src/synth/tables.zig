const std = @import("std");
const globalAlloc = @import("../memory/memory.zig").globalAlloc;

const SineTable = struct {
    data: []f32,
};


pub fn initTables() !SineTable {
    const alloc = globalAlloc();
    const table = try alloc.alloc(f32, 2048);

    for (table, 0..) |*v, i| {
        v.* = @sin(@as(f32, i) * 2 * std.math.pi / 2048.0);
    }

    return .{ .data = table};
}
