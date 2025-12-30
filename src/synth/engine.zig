pub const tables = @import("tables.zig");
pub const osc = @import("oscillator.zig");
pub const voice = @import("voice.zig");
pub const adsr = @import("adsr.zig");
pub const Reverb = @import("effects.zig").Reverb;
pub const Oscillator = osc.Oscillator;
pub const Wavetables = tables.Wavetables;
pub const Voice = voice.Voice;
pub const ADSR = adsr.ADSR;
pub const LFO = voice.LFO;
pub const initTables = tables.initTables;

pub const Synth = @This();




