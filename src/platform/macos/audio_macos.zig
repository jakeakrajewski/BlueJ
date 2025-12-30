const std = @import("std");
const synth = @import("../../synth/engine.zig");
const Wavetables = synth.Wavetables;
const Oscillator = synth.Oscillator;
const Waveform = Oscillator.Waveform;
const Voice = synth.Voice;
const MidiParser = @import("../../midi/midi.zig").MidiParser;
const MidiEvent = @import("../../midi/midi.zig").MidiEvent;
const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
    @cInclude("AudioUnit/AudioUnit.h");
    @cInclude("CoreMIDI/CoreMIDI.h");
});

const tui = @import("../../ui/termios.zig");
const waveform_count: u8 = @intCast(@typeInfo(Waveform).@"enum".fields.len);
var midi_client: c.MIDIClientRef = 0;
var midi_input_port: c.MIDIPortRef = 0;

var parser = MidiParser{};

fn handleMidiByte(b: u8) void {
    if (parser.parseByte(b)) |event| {
        handleMidiEvent(event);
    }
}

fn cfString(str: []const u8) c.CFStringRef {
    return c.CFStringCreateWithCString(
        null,
        str.ptr,
        c.kCFStringEncodingUTF8,
    );
}

var active_note: ?u8 = null;

fn handleMidiEvent(ev: MidiEvent) void {
    switch (ev.event_type) {

        .note_on => {
            const freq = midiNoteToFreq(ev.note);
            active_note = ev.note;
            voice.noteOn(freq, ev.note);
        },

        .note_off => {
            voice.noteOff(ev.note);
        },


        .cc => switch (ev.controller) {
            1 => voice.lfo1.depth = @as(f32, @floatFromInt(ev.value)) / 127.0, // mod wheel
            74 => voice.base_cutoff = 200.0 + @as(f32, @floatFromInt(ev.value)) * 80.0,
            else => {},
        },

        .pitch_bend => {
            // const bend = @as(f32, @floatFromInt(ev.pitch_bend)) / 8192.0;
            // voice.pitch_bend = bend * 2.0; // ±2 semitones
        },

        else => {},
    }
}


fn handleMidiPacket(packet: *const c.MIDIPacket) void {
    const data = packet.data[0..packet.length];

    for (data) |b| {
        handleMidiByte(b);
    }
}


fn midiNoteToFreq(note: u8) f32 {
    return 440.0 * std.math.pow(
        f32,
        2.0,
        (@as(f32, @floatFromInt(note)) - 69.0) / 12.0,
    );
}

var tables: Wavetables = undefined;
// var osc: Oscillator = undefined;
var voice: Voice = undefined;
var shared_params = tui.SharedParams.init();

pub fn init() !void { 
    tables = Wavetables.init();
    // osc = Oscillator.init(&tables);
    // osc.setFrequency(440.0);
    // osc.setWaveform(.square);

    voice = try Voice.init(tables, 48000.0);



}

export fn midiReadCallback(
    pkt_list: [*c]const c.MIDIPacketList,
    readProcRefCon: ?*anyopaque,
    srcConnRefCon: ?*anyopaque,
) callconv(.c) void {
    _ = readProcRefCon;
    _ = srcConnRefCon;

    if (pkt_list == null) return;
    
    const raw_bytes: [*]const u8 = @ptrCast(pkt_list);
    const num_packets = @as(u32, raw_bytes[0]) |
                       (@as(u32, raw_bytes[1]) << 8) |
                       (@as(u32, raw_bytes[2]) << 16) |
                       (@as(u32, raw_bytes[3]) << 24);
    
    
    var offset: usize = 4;
    
    var i: u32 = 0;
    while (i < num_packets) : (i += 1) {
        const length = @as(u16, raw_bytes[offset + 8]) |
                      (@as(u16, raw_bytes[offset + 9]) << 8);
        
        
        if (length > 0 and length <= 256) {
            const data_offset = offset + 10;
            const data = raw_bytes[data_offset..][0..length];
            
            for (data) |b| {
                handleMidiByte(b);
            }
        }
        
        const packet_size = 10 + length;
        const aligned_size = (packet_size + 3) & ~@as(usize, 3);
        offset += aligned_size;
    }
}

fn initMidi() !void {
    const client_name = cfString("Blue J Midi Client");
    defer c.CFRelease(client_name);

    if (c.MIDIClientCreate(
        client_name,
        null,
        null,
        &midi_client,
    ) != c.noErr) {
        return error.MidiClientCreateFailed;
    }


    const port_name = cfString("Blue J Midi In");
    defer c.CFRelease(port_name);

    if (c.MIDIInputPortCreate(
        midi_client,
        port_name,
        midiReadCallback,
        null,
        &midi_input_port,
    ) != c.noErr) {
        return error.MidiInputPortCreateFailed;
    }

    // Connect to all MIDI sources
    const source_count = c.MIDIGetNumberOfSources();
    var i: u32 = 0;
    while (i < source_count) : (i += 1) {
        const src = c.MIDIGetSource(i);
        if (src != 0) {
            _ = c.MIDIPortConnectSource(
                midi_input_port,
                src,
                null,
            );
        }
    }

}

pub fn start() !void {
    std.debug.print("macOS audio start\n", .{});
    const thread = try std.Thread.spawn(.{}, tui.run, .{&shared_params});

    try initMidi();     
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

inline fn lfoSample(lfo: *synth.LFO) f32 {
    return lfo.osc.nextSample();
}

inline fn applyLfo(
    base: f32,
    lfo_val: f32,
    depth: f32,
    amount: f32,
) f32 {
    return base + (lfo_val * depth * amount);
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
    var sequencer = &tui.sequencer;

    while (i < inNumberFrames) : (i += 1) {
        const lfo1 = lfoSample(&voice.lfo1);
        const lfo2 = lfoSample(&voice.lfo2);

        if (shared_params.sequencer_enabled.load(.acquire) > 0.0 and arp_sample_counter == 0) {
            const note = sequencer.midi_steps[arp_step].load(.acquire);
            const freq = sequencer.freq_steps[arp_step].load(.acquire);
            if (freq > -1.0) {
                voice.noteOn(freq, @as(u8, @intFromFloat(note)));
            } 
            else if (freq == -1.0 and note >= 0) voice.noteOff(@as(u8, @intFromFloat(note)));

            arp_step += 1;
            if (@as(f32, @floatFromInt(arp_step)) >= shared_params.sequencer_len.load(.acquire)) arp_step = 0;
        }


        ARP_RATE_HZ =
            shared_params.sequencer_tempo.load(.acquire);


        const base_cutoff =
            shared_params.filter_cutoff.load(.acquire);

        voice.base_cutoff =
            applyLfo(
                applyLfo(
                    base_cutoff,
                    lfo1,
                    voice.lfo1.depth,
                    shared_params.lfo1_cutoff.load(.acquire),
                ),
                lfo2,
                voice.lfo2.depth,
                shared_params.lfo2_cutoff.load(.acquire),
            );

        const base_res =
            shared_params.filter_resonance.load(.acquire);

        voice.filter_resonance =
            std.math.clamp(
                applyLfo(
                    applyLfo(
                        base_res,
                        lfo1,
                        voice.lfo1.depth,
                        shared_params.lfo1_resonance.load(.acquire),
                    ),
                    lfo2,
                    voice.lfo2.depth,
                    shared_params.lfo2_resonance.load(.acquire),
                ),
                0.0,
                0.99,
            );

        const base_vol =
            shared_params.master_volume.load(.acquire);

        // Smooth tremolo (sine / triangle)
        const amp_lfo =
            (lfo1 * shared_params.lfo1_amp.load(.acquire) +
             lfo2 * shared_params.lfo2_amp.load(.acquire));

        // Hard gate 
        const vol_lfo =
            (lfo1 * shared_params.lfo1_volume.load(.acquire) +
             lfo2 * shared_params.lfo2_volume.load(.acquire));

        voice.master_volume =
            std.math.clamp(
                base_vol *
                (1.0 + amp_lfo * 0.5) *
                (1.0 + vol_lfo),
                0.0,
                1.5,
            );


        voice.drive =
            shared_params.master_drive.load(.acquire);

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

        voice.filter_feedback =
            shared_params.filter_feedback.load(.acquire);

        voice.filter_env.recalc();

        // === Modulation / performance ===
        voice.portamento_time =
            shared_params.perf_portamento.load(.acquire);

        voice.key_tracking_amount =
            shared_params.filter_key_tracking.load(.acquire);

        // === LFO 1 params ===
        voice.lfo1.freq_hz =
            shared_params.lfo1_rate.load(.acquire);
        voice.lfo1.depth =
            shared_params.lfo1_depth.load(.acquire);
        voice.lfo1.osc.setFrequency(voice.lfo1.freq_hz);

        voice.lfo1.osc.setWaveform(
            @enumFromInt(@as(usize, @intFromFloat(
                shared_params.lfo1_wave.load(.acquire) - 1
            )))
        );

        // === LFO 2 params ===
        voice.lfo2.freq_hz =
            shared_params.lfo2_rate.load(.acquire);
        voice.lfo2.depth =
            shared_params.lfo2_depth.load(.acquire);
        voice.lfo2.osc.setFrequency(voice.lfo2.freq_hz);

        voice.lfo2.osc.setWaveform(
            @enumFromInt(@as(usize, @intFromFloat(
                shared_params.lfo2_wave.load(.acquire) - 1
            )))
        );

        // === Oscillator parameters ===

        // Osc 1
        const osc1_wave_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc1_wave.load(.acquire)))
        );
        voice.osc_params[0].waveform =
            @enumFromInt(osc1_wave_idx);

        const osc1_wave2_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc1_wave2.load(.acquire)))
        );
        voice.osc_params[0].waveform2 =
            @enumFromInt(osc1_wave2_idx);

        voice.osc_params[0].crossfade_rate =
            shared_params.osc1_crossfade.load(.acquire);

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

        voice.oscs[0].high = if (shared_params.osc1_high.load(.acquire) > 0.0) true else false;

        // Osc 2
        const osc2_wave_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc2_wave.load(.acquire)))
        );
        voice.osc_params[1].waveform =
            @enumFromInt(osc2_wave_idx);

        const osc2_wave2_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc2_wave2.load(.acquire)))
        );
        voice.osc_params[1].waveform2 =
            @enumFromInt(osc2_wave2_idx);

        voice.osc_params[1].semitone =
            @intFromFloat(
                shared_params.osc2_semitones.load(.acquire));

        voice.osc_params[1].octave =
            @intFromFloat(
                shared_params.osc2_octave.load(.acquire));

        voice.osc_params[1].crossfade_rate =
            shared_params.osc2_crossfade.load(.acquire);

        voice.osc_params[1].level =
            shared_params.osc2_level.load(.acquire);

        voice.osc_params[1].detune_cents =
            shared_params.osc2_detune.load(.acquire);

        voice.oscs[1].unison_count =
            @intFromFloat(
                shared_params.osc2_unison_count.load(.acquire));

        voice.oscs[1].high = if (shared_params.osc2_high.load(.acquire) > 0.0) true else false;

        // Osc 3
        const osc3_wave_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc3_wave.load(.acquire)))
        );
        voice.osc_params[2].waveform =
            @enumFromInt(osc3_wave_idx);

        const osc3_wave2_idx: u8 = @min(
            waveform_count - 1,
            @as(u8, @intFromFloat(
                shared_params.osc3_wave2.load(.acquire)))
        );
        voice.osc_params[2].waveform2 =
            @enumFromInt(osc3_wave2_idx);

        voice.osc_params[2].semitone =
            @intFromFloat(
                shared_params.osc3_semitones.load(.acquire));

        voice.osc_params[2].octave =
            @intFromFloat(
                shared_params.osc3_octave.load(.acquire));

        voice.osc_params[2].crossfade_rate =
            shared_params.osc3_crossfade.load(.acquire);

        voice.osc_params[2].level =
            shared_params.osc3_level.load(.acquire);

        voice.osc_params[2].detune_cents =
            shared_params.osc3_detune.load(.acquire);

        voice.oscs[2].unison_count =
            @intFromFloat(
                shared_params.osc3_unison_count.load(.acquire));

        voice.oscs[2].high = if (shared_params.osc3_high.load(.acquire) > 0.0) true else false;

        // voice.delay.delay_time_ms =
        //         shared_params.delay_time_ms.load(.acquire);
        //
        // voice.delay.feedback =
        //         shared_params.delay_feedback.load(.acquire);
        //
        // voice.delay.mix =
        //         shared_params.delay_mix.load(.acquire);
        //
        arp_sample_counter += 1;
        if (arp_sample_counter >= @as(u32,@intFromFloat(SAMPLE_RATE / ARP_RATE_HZ))) {
            arp_sample_counter = 0;
        }

        const stereo = voice.nextSample();

        // mono → stereo
        out[i * 2 + 0] = stereo[0];
        out[i * 2 + 1] = stereo[1];
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



