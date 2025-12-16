const std = @import("std");
const BlueJ = @import("BlueJ");
const builtin = @import("builtin");
const mem = @import("memory/memory.zig");

const is_stm32 = blk: {
    const target = builtin.target;
    break :blk
        target.os.tag == .freestanding and
        target.cpu.arch == .thumb and
        target.abi == .eabi;
};

pub const AudioBackend = blk: {
    if (is_stm32){
        @import("platform/stm32/audio_stm32.zig");
    } else {
        const os = builtin.os.tag;
        break :blk switch (os) {
            .macos => @import("platform/macos/audio_macos.zig"),
            else => @panic("Unsupported platform"),
        };
    }
};

pub fn main() !void {
    mem.initMemory();
    try AudioBackend.init();
    AudioBackend.start();
}

