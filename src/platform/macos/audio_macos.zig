const std = @import("std");
const synth = @import("../../synth/engine.zig");
const Wavetables = synth.Wavetables;
const Oscillator = synth.Oscillator;
const Waveform = Oscillator.Waveform;
const Voice = synth.Voice;
const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
    @cInclude("AudioUnit/AudioUnit.h");
});
const tui = @import("../../ui/termios.zig");
const waveform_count: u8 = @intCast(@typeInfo(Waveform).@"enum".fields.len);

var tables: Wavetables = undefined;
// var osc: Oscillator = undefined;
var voice: Voice = undefined;
var shared_params = tui.SharedParams.init();

pub fn init() !void { 
    tables = Wavetables.init();
    // osc = Oscillator.init(&tables);
    // osc.setFrequency(440.0);
    // osc.setWaveform(.square);

    voice = Voice.init(tables, 48000.0);

    // Filter envelope
    voice.filter_env.attack_time = 0.05;
    voice.filter_env.decay_time = 0.2;
    voice.filter_env.sustain_level = 0.2;
    voice.filter_env.release_time = 0.3;
    voice.filter_env.recalc();

    // Filter response
    voice.base_cutoff = 400.0;
    voice.filter_env_amount = 3000.0;

    // Amp envelope
    voice.amp_env.attack_time = 0.005;
    voice.amp_env.decay_time = 0.201;
    voice.amp_env.sustain_level = 0.02;
    voice.amp_env.release_time = 0.22;
    voice.amp_env.recalc();

    voice.portamento_time = 0.00; // 50 ms glide
    // voice.noteOn(440.0); // A4
    // // play
    // voice.noteOn(660.0); // E5, glides smoothly from 440 → 660

    voice.noteOn(110.0); // A2

    voice.setOscWaveform(0, .saw);
    voice.setOscWaveform(1, .sine);
    voice.setOscWaveform(2, .saw);

    voice.setOscDetune(1, -5.0);
    voice.setOscDetune(2, 7.0);

    voice.setOscLevel(0, 1.0);
    voice.setOscLevel(1, 0.7);
    voice.setOscLevel(2, 0.7);
}

pub fn start() !void {
    std.debug.print("macOS audio start\n", .{});
    const thread = try std.Thread.spawn(.{}, tui.run, .{&shared_params});
    // try tui.run(&shared_params);

    createAudioUnit() catch |e| {
        std.debug.print("Audio init error: {}\n", .{e});
        return;
    };

    _ = c.AudioOutputUnitStart(audio_unit);

    // const start_time = std.time.milliTimestamp();

    while(true){
        // const stop_time = std.time.milliTimestamp();
        // if (stop_time - start_time > 5000) break;
    }

    _ = c.AudioOutputUnitStop(audio_unit);
    _ = c.AudioUnitUninitialize(audio_unit);
    _ = c.AudioComponentInstanceDispose(audio_unit);

    try std.Thread.join(thread);
}

pub fn stop() void { return; }
pub fn deinit() void { return; }

pub fn setSampleRate(rate: f32) void { _ = rate; }
pub fn setBufferSize(frames: u32) void { _ = frames; }

var audio_unit: c.AudioUnit = null;
var frames_rendered: u64 = 0;
const SAMPLE_RATE: f32 = 48_000.0;

var ARP_RATE_HZ: f32 = 2.0;

const base_freq_a2: f32 = 110.0; 

const arp_intervals = [_]i32{ 0, 3, 7, 12 };

var arp_step: u32 = 0;
var arp_sample_counter: u32 = 0;
fn semitonesToFreq(base: f32, semitones: i32) f32 {
    return base * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(semitones)) / 12.0);
}

const ARP_SEQUENCE: [24]f32 = [_]f32{
    36.78, // D1
    43.654, //F1
    55.00, // A1
    69.296, // C#2     
    73.461, // D2 
    82.401, // E2 
    87.307, // F#2,
    82.401, // E2 
    73.461, // D2 
    48.999, //G1
    58.270, // Bb2
    55.00, // A2
    55.00, // A2
    73.461, // D2 
    55.00, // A2
    48.999, //G1
    55.00, // A2
    58.270, // Bb2
    43.654, //F1
    55.00, // A2
    43.654, //F1
    41.203, //E1
    36.78, // D1
    41.203, //E1

};


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
    var sequencer = &tui.sequencer;

    while (i < inNumberFrames) : (i += 1) {

        if (arp_sample_counter == 0) {
            const note = sequencer.freq_steps[arp_step].load(.acquire);
            if (note > -1.0) {
                voice.noteOn(note);
            } else if (note == -1.0) voice.noteOff();

            arp_step += 1;
            if (@as(f32, @floatFromInt(arp_step)) >= shared_params.sequencer_len.load(.acquire)) arp_step = 0;
        }


        ARP_RATE_HZ =
            shared_params.sequencer_tempo.load(.acquire);

        voice.base_cutoff =
            shared_params.cutoff.load(.acquire);

        voice.filter_resonance =
            shared_params.resonance.load(.acquire);

        voice.master_volume =
            shared_params.master_volume.load(.acquire);

        voice.drive =
            shared_params.drive.load(.acquire);

        // === Amp envelope ===
        voice.amp_env.attack_time =
            shared_params.amp_attack.load(.acquire);

        voice.amp_env.decay_time =
            shared_params.amp_decay.load(.acquire);

        voice.amp_env.sustain_level =
            shared_params.amp_sustain.load(.acquire);

        voice.amp_env.release_time =
            shared_params.amp_release.load(.acquire);

        voice.amp_env.recalc();

        // === Filter envelope ===
        voice.filter_env.attack_time =
            shared_params.filter_attack.load(.acquire);

        voice.filter_env.decay_time =
            shared_params.filter_decay.load(.acquire);

        voice.filter_env.sustain_level =
            shared_params.filter_sustain.load(.acquire);

        voice.filter_env.release_time =
            shared_params.filter_release.load(.acquire);

        voice.filter_env.recalc();

        // === Modulation / performance ===
        voice.portamento_time =
            shared_params.portamento.load(.acquire);

        voice.key_tracking_amount =
            shared_params.key_tracking.load(.acquire);

        // === Oscillator parameters ===

        // Osc 1
        const osc1_wave_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc1_wave.load(.acquire)))
        );
        voice.osc_params[0].waveform =
            @enumFromInt(osc1_wave_idx);

        voice.osc_params[0].level =
            shared_params.osc1_level.load(.acquire);

        voice.osc_params[0].detune_cents =
            shared_params.osc1_detune.load(.acquire);

        voice.osc_params[0].semitone =
            @intFromFloat(
                shared_params.osc1_semitones.load(.acquire));

        voice.osc_params[0].octave =
            @intFromFloat(
                shared_params.osc1_octave.load(.acquire));

        voice.oscs[0].unison_count =
            @intFromFloat(
                shared_params.osc1_unison_count.load(.acquire));

        // Osc 2
        const osc2_wave_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc2_wave.load(.acquire)))
        );
        voice.osc_params[1].waveform =
            @enumFromInt(osc2_wave_idx);

        voice.osc_params[1].semitone =
            @intFromFloat(
                shared_params.osc2_semitones.load(.acquire));

        voice.osc_params[1].octave =
            @intFromFloat(
                shared_params.osc2_octave.load(.acquire));

        voice.osc_params[1].level =
            shared_params.osc2_level.load(.acquire);

        voice.osc_params[1].detune_cents =
            shared_params.osc2_detune.load(.acquire);

        voice.oscs[1].unison_count =
            @intFromFloat(
                shared_params.osc2_unison_count.load(.acquire));

        // Osc 3
        const osc3_wave_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc3_wave.load(.acquire)))
        );
        voice.osc_params[2].waveform =
            @enumFromInt(osc3_wave_idx);

        voice.osc_params[2].semitone =
            @intFromFloat(
                shared_params.osc3_semitones.load(.acquire));

        voice.osc_params[2].octave =
            @intFromFloat(
                shared_params.osc3_octave.load(.acquire));

        voice.osc_params[2].level =
            shared_params.osc3_level.load(.acquire);

        voice.osc_params[2].detune_cents =
            shared_params.osc3_detune.load(.acquire);

        voice.oscs[2].unison_count =
            @intFromFloat(
                shared_params.osc3_unison_count.load(.acquire));


        arp_sample_counter += 1;
        if (arp_sample_counter >= @as(u32,@intFromFloat(SAMPLE_RATE / ARP_RATE_HZ))) {
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



