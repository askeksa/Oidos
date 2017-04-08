# Oidos

**Oidos** is a software synthesizer, based on additive synthesis, for making
music for very small executables, such as 4 kilobyte intros.

The synth has two parts: a VST instrument, **Oidos**, and an accompanying VST
effect, **OidosReverb**. The VSTs can in principle be used in any DAW, but the
toolchain for using the music in an executable assumes that the music is
made using **Renoise**.


## The synthesizer

**Oidos** is an additive synthesizer, which means it produces sound by adding
together a large number of sine waves, known as *partials*. The frequencies
and amplitudes of these sine waves, along with their variation over time,
determines the character of each sound. All of this is controlled by the
VST parameters:

### Seed

Random seed for all random choices in the synth. Changing this will often
change the sound dramatically, even with the same values for the other
parameters. Experimentation is the key here.

### Modes

The partials are grouped into a number of *modes* - characteristic frequencies
of the sound. This parameter specifies the number of modes.

### Fat

Each mode contains a number of partials, grouped around the mode's center
frequency. This parameter specifies the number of partials per mode.

### Width

Controls how spread out the frequencies are of the partials belonging to the
same mode.

### Overtones

Controls the distribution of the center frequencies of the modes. The
frequencies are randomly distributed between the *base frequency* (the played
key) and this many semitones above the base frequency.

### Sharpness

Controls how the amplitude of a mode depends on its frequency. With low
sharpness, the amplitudes fall off rapidly, resulting in a soft sound. With
high sharpness, the amplitudes fall off less, or even rise with frequency,
resulting in a sharp sound.

### Harmonicity

If all frequencies in a sound are close to overtones (integer multiples) of
the base frequency, the sound is perceived as *harmonious*. Harmonious
instruments are used for the tonal parts of music. Disharmonious instruments
are for instance drums, which don't have a specific tone.

The *harmonicity* parameter pulls the mode frequencies towards (or pushes them
away from) overtones of the base frequency in order to make the sound more or
less harmonious.

### Decay

The *decaylow* and *decayhigh* parameters control how quickly the amplitudes
of modes fall off over time. They specify the falloff rate for low and high
frequencies, respectively. The falloff of each frequency is determined by
interpolating between these two values.

### Filter

A filter is applied to the partials before summing them. The *filterlow* and
*filterhigh* parameters specify the low and high limits of this filter.
Frequencies outside these limits are discarded or attenuated. The *fslopelow*
and *fslopehigh* parameters specify the sizes of the sloped regions at the
filter limits, i.e. the frequencies which are (increasingly) attenuated before
the filter cuts off completely. The *fsweeplow* and *fsweephigh* parameters
specify the movement of the filter limits over time.

### Gain

A non-linear distortion is applied to the summed partials. The *gain* parameter
controls the strength of this distortion.

### Attack

Specifies the attack time of the sound, i.e. the time before the sound reaches
its full volume.

### Release

Specifies the release time of the sound, i.e. the time before the sound reaches
zero volume after the note is released.

### Quantization

All parameters beginning with **q** are *quantization parameters*. These
parameters round off the internal floating point representations of the
parameters to "nicer" values which compress better, thereby reducing the
compressed size of the parameter data.

When finalizing a piece of music, go through all the quantization parameters
of all the instruments and pull them up as high as you can without ruining the
sound.

The quantization parameters will show the quantized values of the quantized
parameters, and so will the parameters themselves. You can adjust a parameter
which has been quantized, at which point it will jump between the values
allowed by the quantization.


## The reverb

The **OidosReverb** effect VST can be added as a Track DSP to add a reverb
effect to some of the tracks in a piece of **Oidos** music. It is a simple,
"strength in numbers" reverb, which simply consists of a large number of
filtered feedback delays.

The parameters are:

### Mix

The strength of the reverb.

### Pan

Panning of the reverb. Can be used to center the reverb of a non-centered
reverb source.

### Delay

Each feedback delay making up the reverb will have a feedback delay length
randomly distributed between *delaymin* and *delaymax*. Additionally, the
whole reverb will be delayed by *delayadd*.

### Halftime

Controls how quickly the reverb dies out.

### Filter

Filters the sound prior to the reverb. Frequencies below *filterlow* or above
*filterhigh* will be attenuated.

### Dampen

Dampens the sound as it goes around the feedback delays. Frequencies below
*dampenlow* or above *dampenhigh* will be increasingly attenuated as the
reverb progresses.

### Quantization

All parameters beginning with **q** are quantization parameters, working the
same way as described for the synthesizer above.


## Constraints

## The toolchain

