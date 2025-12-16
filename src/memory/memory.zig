const std = @import("std");

pub const GLOBAL_ARENA_SIZE = 64 * 1024;
pub const PATCH_ARENA_SIZE = 64 * 1024;
pub const SCRATCH_ARENA_SIZE = 16 * 1024;

var global_arena_buf: [GLOBAL_ARENA_SIZE]u8 align(8) = undefined;
var patch_arena_buf: [PATCH_ARENA_SIZE]u8 align(8) = undefined;
var scratch_arena_buf: [SCRATCH_ARENA_SIZE]u8 align(8) = undefined;

var global_fba: std.heap.FixedBufferAllocator = undefined;
var patch_fba: std.heap.FixedBufferAllocator = undefined;
var scratch_fba: std.heap.FixedBufferAllocator = undefined;

var global_arena: std.heap.ArenaAllocator = undefined;
var patch_arena: std.heap.ArenaAllocator = undefined;
var scratch_arena: std.heap.ArenaAllocator = undefined;

pub fn initMemory() void {
    global_fba = std.heap.FixedBufferAllocator.init(&global_arena_buf);
    patch_fba = std.heap.FixedBufferAllocator.init(&patch_arena_buf);
    scratch_fba = std.heap.FixedBufferAllocator.init(&scratch_arena_buf);

    global_arena = std.heap.ArenaAllocator.init(global_fba.allocator());
    patch_arena = std.heap.ArenaAllocator.init(patch_fba.allocator());
    scratch_arena = std.heap.ArenaAllocator.init(scratch_fba.allocator());
}

pub fn globalAlloc() std.mem.Allocator {
    return global_arena.allocator();
}

pub fn patchAlloc() std.mem.Allocator {
    return patch_arena.allocator();
}

pub fn scratchAlloc() std.mem.Allocator {
    return scratch_arena.allocator();
}


pub fn resetPatchArena() void {
    patch_arena.reset( .free_all );
}

