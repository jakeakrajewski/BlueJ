const std = @import("std");

pub const midi_learn_state = MidiLearnState{};

pub const MidiLearnState = struct {
    armed: std.atomic.Value(bool) = .init(false),
    target_param_index: std.atomic.Value(i32) = .init(-1),
};

pub const CC_BINDINGS = 128;

pub const MidiCCMap = struct {
    bindings: [CC_BINDINGS]i32 = [_]i32{-1} ** CC_BINDINGS,
};

