# Oidos

**Oidos** is a software synthesizer, based on additive synthesis, for making
music for very small executables, such as 4 and 8 kilobyte intros.

You can follow the devopment on [GitHub](https://github.com/askeksa/Oidos).
For discussion, visit the
[Pouet forum](http://www.pouet.net/prod.php?which=69524).


## Using the synth

The synth has two parts: a VST instrument, **Oidos**, and an accompanying VST
effect, **OidosReverb**. The VSTs can in principle be used in any DAW, but the
toolchain for using the music in an executable assumes that the music is
made using **Renoise**.

Each instrument uses its own **Oidos** VST instance. The **OidosReverb**
effect VST can be added as a Track DSP to add a reverb effect to some of the
tracks.

The synth is quite computationally heavy, especially when the *modes* and
*fat* parameters are set to high values. The VST internally caches the sound
produced by each tone, so as it gets "warmed up" on particular instruments,
it gets less heavy to work with. You will sometimes hear some stuttering in
the sound the first time a tone is played. It can be useful to disable
"overload prevention" in the **Renoise** settings.

To be able to convert your music into executable form, you must adhere to
these guidelines:
- You can use as many tracks, and as many note columns within each track,
  as you like.
- Each note column must contain notes from only one instrument. You can use
  each instrument in as many tracks and columns as you like.
- You can use per-note velocity, which will scale the volume of individual
  notes.
- You can not use the panning, delay or effect columns.
- You can use Send devices, but only in "Mute Source" mode.
- You can adjust volume and panning using Instrument Volume, Track
  Volume/Panning, Mixer Volume/Panning, Send Volume/Panning and Master
  Volume/Panning. However, all tracks using the same instrument must have the
  same volume and panning. This is most easily accomplished by grouping all
  notes played using the same instrument into one or more note columns within
  the same track.
- You can only use one **OidosReverb** instance. This is typically placed
  on a Send track, with some tracks routed to it. For each instrument, either
  all or none of the note columns using that instrument can have reverb.
- You can use group tracks, but only for visual grouping. You can not use
  volume, panning, Send devices or reverb on group tracks.
- You can use the pattern sequence matrix to selectively mute tracks at
  certain pattern positions.
- Globally muted tracks or note columns will not be included. Solo state is
  ignored.


## Converting and playing the music

The `OidosConvert` program in the `convert` directory will convert a Renoise
song using **Oidos** and **OidosReverb** into an assembly source file to be
included with the supplied player source. See the [`oidos.h`](player/oidos.h)
file for documentation on how to invoke the **Oidos** player.

Run the converter from the commandline with input and output file names, like
this:

`OidosConvert music.xrns music.asm`

If your terminal supports *ANSI escape codes* and you want some nice colors
for enhanced readability, use:

`OidosConvert -ansi music.xrns music.asm`

Pay close attention to the output from the converter, as it will tell you if
it encountered an error along the way (for instance if one of the guidelines
are violated).

If you are only interested in a stand-alone executable that just plays the
music (for instance for an executable music compo), there is a complete
setup for this in the [`easy_exe`](easy_exe/) directory. It also produces a
WAV writer, as required by many executable music compo rules.


## Optimization

An important part of the workflow when producing music for a size-limited
executable is optimizing the size and computation time requirements of the
music. The `OidosConvert` program outputs some statistics about the music
which can be used to guide this process:

**Burden**: The total computation time requirements of all tracks using this
instrument. The time requirement is a product of these 4 factors:
- The value of the *modes* parameter
- The value of the *fat* parameter
- The number of different tones the instrument is played with
- The longest note played by the instrument

The total burden for all instruments is printed at the end, along with an
estimate of the real time for a reasonably fast CPU.

**Tones**: Lists all the tones the instrument is played with. The number
after the colon indicates how many times in the song the instrument is played
with that tone.

**Velocities**: Lists all the velocities the instrument is played with. The
velocity values are automatically quantized to the largest power of two
dividing all used values (with **7F** treated as **80**). Sticking to more
"round" values will reduce the number of bits required to represent each note
velocity. The number after the colon indicates how many times in the song the
instrument is played with that velocity.

**Lengths**: Lists all the lengths (distance from each note until the next note
or **OFF**) in this column, with the number after the colon indicating how many
times that length occurs in the column. If all notes in a column have the same
length, a more compact representation of the track is used, omitting all
**OFF**s.

**Notes**: Lists the tone/velocity combinations used in the column, with the
number after the colon indicating how many times that combination occurs in
the column. Notes are represented as indices into a list of these combinations,
so reducing the number of combinations will typically reduce the size of the
music.

Using reverb will add around 100 bytes to the compressed size for the reverb
code and parameters. Using panning will usually add some 10-30 bytes depending
on the number of instruments.

Also be sure to quantize all parameters, as described below.


## Synth parameters

**Oidos** is an additive synthesizer, which means it produces sound by adding
together a large number of sine waves, known as *partials*. The frequencies
and amplitudes of these sine waves, along with their variation over time,
determines the character of the sound. All of this is controlled by the
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
sharpness, the amplitudes fall off strongly, resulting in a soft sound. With
high sharpness, the amplitudes fall off less, or even rise with frequency,
resulting in a sharp sound.

### Harmonicity

If all frequencies in a sound are close to overtones (integer multiples) of
the base frequency, the sound is perceived as *harmonious*. Harmonious
instruments are used for the tonal parts of music. Disharmonious instruments
are for instance drums, which don't have a specific tone.

The *harmonicity* parameter pulls the mode center frequencies towards (or
pushes them away from) overtones of the base frequency in order to make the
sound more or less harmonious.

### Decay

The *decaylow* and *decayhigh* parameters control how quickly the amplitudes
of modes fall off over time. They specify the falloff rate for low and high
frequencies, respectively. The falloff of each frequency is determined by
interpolating between these two values.

### Filter

A filter is applied to the partials before summing them. The *filterlow* and
*filterhigh* parameters specify the low and high limits of this filter,
relative to the base frequency of the note.
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


## Reverb parameters

The included reverb effect is a simple, "strength in numbers" reverb, which
simply consists of a large number of filtered feedback delays.

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

### N

Number of feedback delays making up the reverb. The more delays, the smoother
the reverb.

### Seed

Random seed for the random delay lengths. Some seeds cause the delays to
interfere with each other, resulting in faint echos and irregularities in
the reverb. Experiment with the seed to finetune the reverb.

### Quantization

All parameters beginning with **q** are quantization parameters, working the
same way as described for the synth above.
