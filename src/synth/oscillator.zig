const std = @import("std");
const globalAlloc = @import("../memory/memory.zig").globalAlloc;

const Wavetables = @import("tables.zig").Wavetables;
const TABLE_SIZE: usize = 2048;

pub const Oscillator = struct {
    // Current position in the wavetable, as a fractional index.
    // This allows for smooth movement between integer table indices.
    phase: f32, 
    
    // How much to advance the phase on each sample.
    // phaseIncrement = (frequency / sample_rate) * TABLE_SIZE
    phase_increment: f32, 
    
    // Pointer to the set of tables created earlier.
    tables: *const Wavetables, 
    
    // Which waveform is currently active.
    waveform: Waveform,
    
    pub const Waveform = enum {
        sine,
        square,
        saw,
        tri,
    };

    // Initialize a new oscillator
    pub fn init(tables: *const Wavetables) Oscillator {
        return Oscillator {
            .phase = 0.0,
            .phase_increment = 0.0, // Set later by setFrequency()
            .tables = tables,
            .waveform = .sine,
        };
    }
    
    // Calculates and sets the phase increment based on desired frequency
    // sample_rate is typically 44100.0 or 48000.0
    pub fn setFrequency(self: *Oscillator, frequency: f32, sample_rate: f32) void {
        const normalized_freq = frequency / sample_rate;
        self.phase_increment = normalized_freq * @as(f32, TABLE_SIZE);
    }

    // --- Core Sample Generation Function ---
    // Returns the next sample value (f32 between -1.0 and 1.0)
    pub fn nextSample(self: *Oscillator) f32 {
        // 1. Get the current wavetable based on the selected waveform
        const table_data: []f32 = switch (self.waveform) {
            .sine => self.tables.sine.data,
            .square => self.tables.square.data,
            .saw => self.tables.saw.data,
            .tri => self.tables.tri.data,
        };
        
        // 2. Calculate the sample index and the fractional part for interpolation
        // @floor(self.phase) gives the integer index for the sample before the phase
        const index_f32 = self.phase;
        const index_a: usize = @int(index_f32); 
        
        // The fractional part (0.0 to 1.0) determines how much to blend sample A and B
        const frac = index_f32 - @floor(index_f32); 
        
        // 3. Find the next sample index (B) for interpolation
        // The % TABLE_SIZE ensures we wrap around the table correctly (circular buffer)
        const index_b: usize = (index_a + 1) % TABLE_SIZE;
        
        // 4. Read the samples from the table
        const sample_a = table_data[index_a];
        const sample_b = table_data[index_b];
        
        // 5. Linear Interpolation (X-fade between sample A and sample B)
        // Interpolated_value = A + (B - A) * frac
        const sample = sample_a + (sample_b - sample_a) * frac;
        
        // 6. Advance the phase and wrap it around
        self.phase += self.phase_increment;
        if (self.phase >= @as(f32, TABLE_SIZE)) {
            // Subtract TABLE_SIZE instead of setting to 0.0 to maintain fractional precision
            self.phase -= @as(f32, TABLE_SIZE); 
        }
        
        return sample;
    }
};
