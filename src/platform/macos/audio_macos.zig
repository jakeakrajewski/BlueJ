const std = @import("std");
const synth = @import("../../synth/engine.zig");
const Wavetables = synth.Wavetables;
const Oscillator = synth.Oscillator;
const Voice = synth.Voice;
const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
    @cInclude("AudioUnit/AudioUnit.h");
});

var tables: Wavetables = undefined;
// var osc: Oscillator = undefined;
var voice: Voice = undefined;

pub fn init() !void { 
    tables = Wavetables.init();
    // osc = Oscillator.init(&tables);
    // osc.setFrequency(440.0);
    // osc.setWaveform(.square);

    voice = Voice.init(tables, 48000.0);

    // Filter envelope
    voice.filter_env.attack_time = 0.001;
    voice.filter_env.decay_time = 0.2;
    voice.filter_env.sustain_level = 0.2;
    voice.filter_env.release_time = 0.3;
    voice.filter_env.recalc();

    // Filter response
    voice.base_cutoff = 400.0;
    voice.filter_env_amount = 3000.0;

    // Amp envelope
    voice.amp_env.attack_time = 0.005;
    voice.amp_env.decay_time = 0.1;
    voice.amp_env.sustain_level = 0.8;
    voice.amp_env.release_time = 0.2;
    voice.amp_env.recalc();

    voice.portamento_time = 0.05; // 50 ms glide
    // voice.noteOn(440.0); // A4
    // // play
    // voice.noteOn(660.0); // E5, glides smoothly from 440 → 660

    voice.noteOn(110.0); // A2

    voice.setOscWaveform(0, .saw);
    voice.setOscWaveform(1, .square);
    voice.setOscWaveform(2, .sine);

    voice.setOscDetune(1, -5.0);
    voice.setOscDetune(2, 7.0);

    voice.setOscLevel(0, 1.0);
    voice.setOscLevel(1, 0.7);
    voice.setOscLevel(2, 0.4);
}

pub fn start() void {
    std.debug.print("macOS audio start\n", .{});

    createAudioUnit() catch |e| {
        std.debug.print("Audio init error: {}\n", .{e});
        return;
    };

    _ = c.AudioOutputUnitStart(audio_unit);

    const start_time = std.time.milliTimestamp();

    while(true){
        const stop_time = std.time.milliTimestamp();
        if (stop_time - start_time > 5000) break;
    }

    _ = c.AudioOutputUnitStop(audio_unit);
    _ = c.AudioUnitUninitialize(audio_unit);
    _ = c.AudioComponentInstanceDispose(audio_unit);
}

pub fn stop() void { return; }
pub fn deinit() void { return; }

pub fn setSampleRate(rate: f32) void { _ = rate; }
pub fn setBufferSize(frames: u32) void { _ = frames; }

var audio_unit: c.AudioUnit = null;
var frames_rendered: u64 = 0;
const SAMPLE_RATE: f32 = 48_000.0;

const ARP_RATE_HZ: f32 = 8.0;

const SAMPLES_PER_STEP: u32 =
    @intFromFloat(SAMPLE_RATE / ARP_RATE_HZ);

const base_freq_a2: f32 = 110.0; // A2

const arp_intervals = [_]i32{ 0, 3, 7, 12 };

var arp_step: u32 = 0;
var arp_sample_counter: u32 = 0;
fn semitonesToFreq(base: f32, semitones: i32) f32 {
    return base * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(semitones)) / 12.0);
}


fn renderCallback(
    inRefCon: ?*anyopaque,
    ioActionFlags: [*c]c.AudioUnitRenderActionFlags,
    inTimeStamp: [*c]const c.AudioTimeStamp,
    inBusNumber: c.UInt32,
    inNumberFrames: c.UInt32,
    ioData: [*c]c.AudioBufferList,
) callconv(.c) c.OSStatus {
    _ = inRefCon;
    _ = ioActionFlags;
    _ = inTimeStamp;
    _ = inBusNumber;

    const buffer = ioData.*.mBuffers[0];
    const out: [*]f32 = @ptrCast(@alignCast(buffer.mData));

    var i: u32 = 0;
    while (i < inNumberFrames) : (i += 1) {

        // --- Arpeggio timing ---
        if (arp_sample_counter == 0) {
            const octave = @as(i32, @intCast(arp_step / arp_intervals.len));
            const interval = arp_intervals[arp_step % arp_intervals.len];

            const semitones = interval + octave * 12;
            const freq = semitonesToFreq(base_freq_a2, semitones);

            voice.noteOn(freq);

            arp_step += 1;
            if (octave >= 4) { // A2 → A6
                arp_step = 0;
            }
        }

        arp_sample_counter += 1;
        if (arp_sample_counter >= SAMPLES_PER_STEP) {
            arp_sample_counter = 0;
        }

        const s = voice.nextSample();

        // mono → stereo
        out[i * 2 + 0] = s;
        out[i * 2 + 1] = s;
    }

    return c.noErr;
}

fn createAudioUnit() !void {
    var desc = c.AudioComponentDescription{
        .componentType = c.kAudioUnitType_Output,
        .componentSubType = c.kAudioUnitSubType_DefaultOutput,
        .componentManufacturer = c.kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0,
    };

    const comp = c.AudioComponentFindNext(null, &desc);
    if (comp == null) return error.AudioComponentNotFound;

    if (c.AudioComponentInstanceNew(comp, &audio_unit) != c.noErr)
        return error.AudioUnitCreateFailed;

    // Set render callback
    var cb = c.AURenderCallbackStruct{
        .inputProc = renderCallback,
        .inputProcRefCon = null,
    };

    if (c.AudioUnitSetProperty(
        audio_unit,
        c.kAudioUnitProperty_SetRenderCallback,
        c.kAudioUnitScope_Input,
        0,
        &cb,
        @sizeOf(c.AURenderCallbackStruct),
    ) != c.noErr)
        return error.SetCallbackFailed;

    // Set format (32-bit float, stereo)
    var format = c.AudioStreamBasicDescription{
        .mSampleRate = 48_000,
        .mFormatID = c.kAudioFormatLinearPCM,
        .mFormatFlags =
            c.kAudioFormatFlagIsFloat |
            c.kAudioFormatFlagIsPacked,
        .mBitsPerChannel = 32,
        .mChannelsPerFrame = 2,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = 8,
        .mBytesPerPacket = 8,
        .mReserved = 0,
    };

    if (c.AudioUnitSetProperty(
        audio_unit,
        c.kAudioUnitProperty_StreamFormat,
        c.kAudioUnitScope_Input,
        0,
        &format,
        @sizeOf(c.AudioStreamBasicDescription),
    ) != c.noErr)
        return error.SetFormatFailed;

    if (c.AudioUnitInitialize(audio_unit) != c.noErr)
        return error.AudioUnitInitFailed;
}



