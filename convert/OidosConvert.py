#!/usr/bin/env python

import sys
import zipfile
import XML
import struct
import ctypes
import math
import datetime

TOTAL_SEMITONES = 120
SAMPLERATE = 44100

class InputException(Exception):
	def __init__(self, message):
		Exception.__init__(self)
		self.message = message


class Volume:
	def __init__(self, left, right):
		self.left = left
		self.right = right

	def __mul__(self, other):
		return Volume(self.left * other.left, self.right * other.right)

	def __eq__(self, other):
		return self.left == other.left and self.right == other.right

	def isPanned(self):
		return self.left != self.right

def makeVolume(xvolume):
	v = float(xvolume)
	return Volume(v,v)

def makePanning(xpanning):
	p = float(xpanning)
	return Volume(math.sqrt(2.0 * (1.0 - p)), math.sqrt(2.0 * p))


class Instrument:
	NAMES = ["seed", "modes", "fat", "width",
			 "overtones", "sharpness", "harmonicity", "decaylow", "decayhigh",
			 "filterlow", "fslopelow", "fsweeplow", "filterhigh", "fslopehigh", "fsweephigh",
			 "gain", "attack", "release",
			 "dummy",
			 "q_decaydiff", "q_decaylow", "q_harmonicity", "q_sharpness", "q_width",
			 "q_f_low", "q_fs_low", "q_fsw_low", "q_f_high", "q_fs_high", "q_fsw_high",
			 "q_gain", "q_attack", "q_release"
	]

	def __init__(self, number, name, params, legacy):
		if legacy:
			# Duplicate filter sweep parameter
			params = params[:11] + [params[13]] + params[11:17] + [0.0] + params[20:27] + [params[29]] + params[27:33]

		names = Instrument.NAMES
		self.number = number
		self.name = name
		self.params = params
		for i,p in enumerate(self.params):
			self.__dict__[names[i]] = p
		self.volume = Volume(1.0, 1.0)
		self.maxsamples = 0
		self.title = "%02X|%s" % (self.number, self.name)


class Reverb:
	NAMES = ["mix", "pan", "delaymin", "delaymax", "delayadd",
			 "halftime", "filterlow", "filterhigh", "dampenlow", "dampenhigh",
			 "n", "seed", "dummy1", "dummy2", "dummy3",
			 "q_mixpan", "q_flow", "q_fhigh", "q_dlow", "q_dhigh"
	]

	def __init__(self, params):
		names = Reverb.NAMES
		self.params = (params + [0.0] * len(names))[:len(names)]
		for i,p in enumerate(self.params):
			self.__dict__[names[i]] = p

		self.p_min_delay   = math.floor(self.delaymin * 100 + 0.5) * 256
		self.p_max_delay   = math.floor(self.delaymax * 100 + 0.5) * 256
		self.p_add_delay   = math.floor(self.delayadd * 100 + 0.5) * 256
		self.p_filter_low  = min(1, quantize(math.pow(self.filterlow,  2), self.q_flow))
		self.p_filter_high = min(1, quantize(math.pow(self.filterhigh, 2), self.q_fhigh))
		self.p_dampen_low  = min(1, quantize(math.pow(self.dampenlow,  2), self.q_dlow))
		self.p_dampen_high = min(1, quantize(math.pow(self.dampenhigh, 2), self.q_dhigh))
		self.p_num_delays  = math.floor(self.n * 100 + 0.5) * 2
		self.p_seed        = math.floor(self.seed * 100 + 0.5) * 2048
		self.p_decay_mul   = math.pow(2.0, 1.0 / (self.halftime * SAMPLERATE))
		self.p_max_decay   = math.pow(self.p_decay_mul, -self.p_max_delay)

		mix = self.mix * 10 / math.sqrt(self.p_num_delays)
		self.p_volumes     = [quantize(mix * math.sqrt(1 + s - 2 * s * self.pan), self.q_mixpan) for s in [1,-1]]

	def __eq__(self, other):
		return all(p1 == p2 for p1,p2 in zip(self.params, other.params))


class Note:
	NOTEBASES = {
		"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
	}

	NOTENAMES = {
		0: "C-", 1: "C#", 2: "D-", 3: "D#", 4: "E-", 5: "F-",
		6: "F#", 7: "G-", 8: "G#", 9: "A-", 10: "A#", 11: "B-"
	}

	def __init__(self, tname, column, line, songpos, pat, patline, note, instr, velocity):
		note = str(note)
		self.line = int(line)
		self.songpos = int(songpos)
		self.pat = int(pat)
		self.patline = patline
		if note == "OFF":
			self.off = True
			self.tone = None
			self.instr = 0
			self.velocity = 0
		else:
			self.off = False
			octave = int(note[2])
			notebase = Note.NOTEBASES[note[0]]
			sharp = int(note[1] == "#")
			self.tone = octave * 12 + notebase + sharp
			self.instr = int(str(instr), 16)
			try:
				self.velocity = 127 if str(velocity) == "" or str(velocity) == ".." else int(str(velocity), 16)
			except ValueError:
				print "Track '%s' column %d pattern %d line %d: Illegal velocity value '%s'" % (tname, column, pat, patline, str(velocity));
				self.velocity = 127

def notename(tone):
	return Note.NOTENAMES[tone%12] + str(tone/12)


def instplugins(xinst):
	xplugins = xinst.PluginProperties
	if xplugins:
		return xplugins
	return xinst.PluginGenerator

def isactive(xdevice):
	if not xdevice:
		return False
	if xdevice.IsActive.Value:
		return float(xdevice.IsActive.Value) != 0.0
	else:
		return str(xdevice.IsActive) == "true"


def f2i(f):
	return struct.unpack('I', struct.pack('f', f))[0]

def i2f(i):
	return struct.unpack('f', struct.pack('I', i))[0]

def quantize(value, level):
	bit = 1 << int(math.floor(level * 31))
	mask = 0x100000000 - bit
	add = bit >> 1
	i = f2i(value)
	i = (i + add) & mask
	if i == 0x80000000:
		i = 0x00000000
	q = i2f(i)
	return q

def makeParamBlock(inst, uses_panning):
	modes = max(1, math.floor(0.5 + inst.modes * 100))
	fat = max(1, math.floor(0.5 + inst.fat * 100))
	seed = math.floor(0.5 + inst.seed * 100)
	overtones = math.floor(0.5 + inst.overtones * 100)
	decaydiff = inst.decayhigh - inst.decaylow
	decaylow = inst.decaylow
	harmonicity = inst.harmonicity * 2 - 1
	sharpness = inst.sharpness * 5 - 4
	width = 100 * math.pow(inst.width, 5)

	fsweeplow = -math.pow(inst.fsweeplow - 0.5, 3) * 100 * TOTAL_SEMITONES / SAMPLERATE
	fsweephigh = -math.pow(inst.fsweephigh - 0.5, 3) * 100 * TOTAL_SEMITONES / SAMPLERATE
	fslopelow = math.pow((1 - inst.fslopelow), 3)
	fslopehigh = -math.pow((1 - inst.fslopehigh), 3)
	filterlow = (inst.filterlow * 2 - 1) * TOTAL_SEMITONES
	filterhigh = (inst.filterhigh * 2 - 1) * TOTAL_SEMITONES

	gain = math.pow(4096, inst.gain - 0.25)
	attack = 2.0 if inst.attack == 0.0 else 1 / (inst.attack * inst.attack) / SAMPLERATE
	release = -(2.0 if inst.release == 0.0 else 1 / inst.release / SAMPLERATE)

	decaydiff = quantize(decaydiff, inst.q_decaydiff)
	decaylow = quantize(decaylow, inst.q_decaylow)
	harmonicity = quantize(harmonicity, inst.q_harmonicity)
	sharpness = quantize(sharpness, inst.q_sharpness)
	width = quantize(width, inst.q_width)
	filterlow = quantize(filterlow, inst.q_f_low)
	fslopelow = quantize(fslopelow, inst.q_fs_low)
	fsweeplow = quantize(fsweeplow, inst.q_fsw_low)
	filterhigh = quantize(filterhigh, inst.q_f_high)
	fslopehigh = quantize(fslopehigh, inst.q_fs_high)
	fsweephigh = quantize(fsweephigh, inst.q_fsw_high)
	gain = quantize(gain, inst.q_gain)
	attack = quantize(attack, inst.q_attack)
	release = quantize(release, inst.q_release)

	maxdecay = max(decaylow, decaylow + decaydiff)
	releasetime = inst.maxtime * SAMPLERATE + 1.0 / -release if release != 0.0 else float('inf')
	decaytime = (math.log(0.01, maxdecay)) * 4096 if maxdecay < 1.0 else float('inf')
	if math.isinf(releasetime) and math.isinf(decaytime):
		raise InputException("Instrument '%s' has infinite duration" % inst.title)
	inst.maxsamples = int(min(releasetime, decaytime) + 65535) & -65536

	left_volume = inst.volume.left * inst.velocity_quantum * 128
	right_volume = inst.volume.right * inst.velocity_quantum * 128
	volume = (left_volume + right_volume) / 2
	pan = right_volume / volume - 1
	volume = quantize(volume, 0.65)
	pan = quantize(pan, 0.55)

	return [int(modes), int(fat), int(seed), int(overtones),
			decaydiff, decaylow, harmonicity, sharpness, width,
			filterlow, filterhigh, fslopelow, fslopehigh, fsweeplow, fsweephigh,
			gain, inst.maxsamples, release, attack,
			volume] + ([pan] if uses_panning else [])


class Track:
	def __init__(self, number, column, name, notes, volume, instruments):
		self.number = number
		self.column = column
		self.name = name
		self.notes = notes
		self.volume = volume
		self.notemap = dict()
		self.tav_repr = dict()
		self.note_lengths = dict()

		self.title = "%s, column %d" % (self.name, self.column)

		self.labelname = ""
		for c in self.name:
			if c.isalnum() or c == '_':
				self.labelname += c

		self.instr = None
		self.latest_note = 0
		self.max_length = 0

		prev = None
		for note in notes:
			if prev is not None and not prev.off:
				if prev.instr is None:
					raise InputException("Track '%s' column %d pattern %d line %d: Undefined instrument" % (name, column, prev.pat, prev.patline));
				if self.instr is not None and prev.instr != self.instr:
					raise InputException("Track '%s' column %d pattern %d line %d: More than one instrument in track" % (name, column, prev.pat, prev.patline))
				self.instr = prev.instr
				length = note.line - prev.line
				if length < 0:
					raise InputException("Track '%s' column %d pattern %d: Reversed note order from %d to %d" % (name, column, prev.pat, prev.patline, note.patline))
				if prev.tone is None:
					raise InputException("Track '%s' column %d pattern %d line %d: Toneless note" % (name, column, prev.pat, prev.patline))
				self.latest_note = max(self.latest_note, prev.line)
				self.max_length = max(self.max_length, length)
				tav = (prev.tone, prev.velocity)
				self.notemap[prev] = tav

				if length not in self.note_lengths:
					self.note_lengths[length] = 0
				self.note_lengths[length] += 1

			prev = note

		if not prev.off:
			 raise InputException("Track '%s' column %d pattern %d line %d: Note not terminated (insert OFF)" % (name, column, prev.pat, prev.patline))

		if len(self.note_lengths) == 1:
			for l in self.note_lengths:
				self.singular_length = l
		else:
			self.singular_length = None

		self.tavs = sorted(set(self.notemap.values()), key = (lambda (t,v) : (t,v)))
		for i,tav in enumerate(self.tavs):
			if tav[0] is None:
				raise InputException("Track '%s' has a toneless note" % name)
			self.tav_repr[tav] = i

		self.longest_sample = None
		self.sample_length_sum = None


class Music:
	def __init__(self, tracks, instruments, length, ticklength, n_reverb_tracks, reverb, master_volume):
		self.tracks = tracks
		self.instruments = instruments
		self.length = length
		self.ticklength = ticklength
		self.n_reverb_tracks = n_reverb_tracks
		self.reverb = reverb
		self.master_volume = master_volume

		# Reorder instruments according to reverb
		self.instrument_map = dict()
		with_reverb = set(t.instr for t in self.tracks[:self.n_reverb_tracks])
		without_reverb = set(t.instr for t in self.tracks[self.n_reverb_tracks:])
		instruments_with_reverb = []
		instruments_without_reverb = []
		for instr in self.instruments:
			if instr is None:
				continue
			self.instrument_map[instr.number] = instr

			if instr.number in with_reverb:
				if instr.number in without_reverb:
					raise InputException("Instrument '%s' is used both with and without reverb" % instr.title)
				instruments_with_reverb.append(instr)
			if instr.number in without_reverb:
				instruments_without_reverb.append(instr)

		self.instruments = instruments_with_reverb + instruments_without_reverb
		self.n_reverb_instruments = len(instruments_with_reverb)

		# Calculate track order and velocity set
		self.track_order = []
		self.uses_panning = False
		for instr in self.instruments:
			velocities = set()
			instr.columns = 0
			instr.latest_note = 0
			volume = None
			for ti,track in enumerate(self.tracks):
				if track.instr == instr.number:
					self.track_order.append(ti)
					instr.columns += 1
					instr.latest_note = max(instr.latest_note, track.latest_note)
					v = track.volume * self.master_volume
					if volume is not None and not v == volume:
						raise InputException("Track '%s' has different volume/panning than previous tracks with same instrument" % track.title)
					volume = v
					for t,v in track.tavs:
						velocities.add(v)
			instr.volume *= volume
			instr.velocities = sorted(list(velocities))
			if instr.volume.isPanned():
				self.uses_panning = True

			quantum = 128
			while quantum > 1:
				if all(v == 127 or v % quantum == 0 for v in instr.velocities):
					break
				quantum /= 2
			instr.velocity_quantum = quantum

		# Calculate longest sample
		self.max_maxsamples = 0
		self.max_total_samples = 0
		self.end_of_sound = 0
		for instr in self.instruments:
			instr.maxtime = 0
			tonecount = dict()
			velocitycount = dict()
			for ti,track in enumerate(self.tracks):
				if track.instr != instr.number:
					continue
				instr.maxtime = max(instr.maxtime, track.max_length * ticklength)
				for note in track.notes:
					if note.tone is not None:
						tonecount[note.tone] = tonecount[note.tone] + 1 if note.tone in tonecount else 1
						velocitycount[note.velocity] = velocitycount[note.velocity] + 1 if note.velocity in velocitycount else 1

			instr.tonecount = tonecount
			instr.velocitycount = velocitycount
			instr.tones = sorted(list(tonecount.keys()))
			instr.tonemap = dict()
			for i,t in enumerate(instr.tones):
				instr.tonemap[t] = i

			instr.paramblock = makeParamBlock(instr, self.uses_panning)

			instr.end_of_sound = instr.latest_note * ticklength * SAMPLERATE + instr.maxsamples
			if instr.number in with_reverb:
				instr.end_of_sound += reverb.halftime * 10 * SAMPLERATE

			self.max_maxsamples = max(self.max_maxsamples, instr.maxsamples)
			self.max_total_samples = max(self.max_total_samples, instr.maxsamples * len(instr.tones))
			self.end_of_sound = max(self.end_of_sound, instr.end_of_sound)

		self.datainit = None
		self.out = None

	def dataline(self, data):
		if len(data) > 0:
			line = self.datainit
			first = True
			for d in data:
				if not first:
					line += ","
				line += str(d)
				first = False
			line += "\n"
			self.out += line

	def comment(self, c):
		self.out += "\t; %s\n" % c

	def label(self, l):
		self.out += "%s:\n" % l

	def notelist(self, datafunc, trackterm, prefix):
		for ti in self.track_order:
			track = self.tracks[ti]
			self.comment(track.title)
			self.label("%s%s_%d" % (prefix, track.labelname, track.column))
			prev_n = None
			pat_data = []
			for n in track.notes:
				if track.singular_length and n.off and n.line > 0:
					continue
				if prev_n is not None:
					pat_data += datafunc(track,prev_n,n)
				if not n.off if prev_n is None else n.songpos != prev_n.songpos:
					self.dataline(pat_data)
					pat_data = []
					self.comment("Position %d, pattern %d" % (n.songpos, n.pat))
				prev_n = n
			pat_data += datafunc(track,prev_n,None)
			self.dataline(pat_data)
			self.dataline(trackterm)
			self.out += "\n"

	def lendata(self, t, pn, n):
		if n is None:
			return []
		step = n.line-pn.line
		return [-1 - (step >> 8), step & 255] if step > 127 else [step]

	def samdata(self, t, pn, n):
		if pn.off:
			return [0]
		return [1 + t.tav_repr[t.notemap[pn]]]

	def export(self):
		self.datainit = "\tdb\t"
		self.out = ""

		spt = int(self.ticklength * SAMPLERATE)
		total_samples = max((self.length * self.ticklength) * SAMPLERATE, self.end_of_sound)

		def roundup(v):
			return (int(v) & -0x10000) + 0x10000

		global infile
		self.out += "; Music converted from %s %s\n" % (infile, str(datetime.datetime.now())[:-7])
		self.out += "\n"
		self.out += "%%define MUSIC_LENGTH %d\n" % self.length
		self.out += "%%define TOTAL_SAMPLES %d\n" % roundup(total_samples)
		self.out += "%%define MAX_TOTAL_INSTRUMENT_SAMPLES %d\n" % roundup(self.max_total_samples)
		self.out += "\n"
		self.out += "%%define SAMPLES_PER_TICK %d\n" % spt
		self.out += "%%define TICKS_PER_SECOND %.9f\n" % (1.0 / self.ticklength)
		self.out += "\n"
		self.out += "%%define NUM_TRACKS_WITH_REVERB %d\n" % self.n_reverb_instruments
		self.out += "%%define NUM_TRACKS_WITHOUT_REVERB %d\n" % (len(self.instruments) - self.n_reverb_instruments)

		if self.n_reverb_instruments > 0:
			reverb = self.reverb
			self.out += "\n"
			self.out += "%%define REVERB_NUM_DELAYS   %d\n" % reverb.p_num_delays
			self.out += "%%define REVERB_MIN_DELAY    %d\n" % reverb.p_min_delay
			self.out += "%%define REVERB_MAX_DELAY    %d\n" % reverb.p_max_delay
			self.out += "%%define REVERB_ADD_DELAY    %d\n" % reverb.p_add_delay
			self.out += "%%define REVERB_RANDOMSEED   %d\n" % reverb.p_seed
			self.out += "%%define REVERB_MAX_DECAY    %.9f\n" % reverb.p_max_decay
			self.out += "%%define REVERB_DECAY_MUL    %.9f\n" % reverb.p_decay_mul
			self.out += "%%define REVERB_FILTER_HIGH  0x%08X ; %.9f\n" % (f2i(reverb.p_filter_high), reverb.p_filter_high)
			self.out += "%%define REVERB_FILTER_LOW   0x%08X ; %.9f\n" % (f2i(reverb.p_filter_low), reverb.p_filter_low)
			self.out += "%%define REVERB_DAMPEN_HIGH  0x%08X ; %.9f\n" % (f2i(reverb.p_dampen_high), reverb.p_dampen_high)
			self.out += "%%define REVERB_DAMPEN_LOW   0x%08X ; %.9f\n" % (f2i(reverb.p_dampen_low), reverb.p_dampen_low)
			self.out += "%%define REVERB_VOLUME_LEFT  0x%08X ; %.9f\n" % (f2i(reverb.p_volumes[0]), reverb.p_volumes[0])
			self.out += "%%define REVERB_VOLUME_RIGHT 0x%08X ; %.9f\n" % (f2i(reverb.p_volumes[1]), reverb.p_volumes[1])

		if self.uses_panning:
			self.out += "\n%define USES_PANNING\n"

		# Instrument parameters
		self.out += "\n\n\tsection iparam data align=4\n"
		self.out += "\n_InstrumentParams:\n"
		for instr in self.instruments:
			self.label(".i%02d" % instr.number)
			self.comment(instr.title)
			self.out += "\tdd\t"
			first = True
			for p in instr.paramblock:
				if not first:
					self.out += ","
				if isinstance(p, float):
					self.out += "0x%08X" % f2i(p)
				else:
					self.out += "%d" % p
				first = False
			self.out += "\n"
		self.out += "\n"

		# Instrument tones
		self.out += "\n\n\tsection itones data align=1\n"
		self.out += "\n_InstrumentTones:\n"
		for instr in self.instruments:
			self.label(".i%02d" % instr.number)
			self.comment(instr.title)
			self.out += "\tdb\t"
			prev_tone = 0
			for tone in instr.tones:
				self.out += str(tone - prev_tone) + ","
				prev_tone = tone
				first = False
			self.out += "%d\n" % (-129 + instr.columns)

		# Track data
		self.out += "\n\n\tsection trdata data align=1\n"
		self.out += "\n_TrackData:\n"
		for ti in self.track_order:
			track = self.tracks[ti]
			instr = self.instrument_map[track.instr]

			self.label(".t_%s_%d" % (track.labelname, track.column))
			self.comment(track.title)

			# List tones and velocities
			tavdata = [track.singular_length if track.singular_length else 0]
			prev_tone_id = 0
			for t,v in track.tavs:
				tone_id = instr.tonemap[t]
				vol = (v + instr.velocity_quantum / 2) / instr.velocity_quantum
				tavdata += [tone_id - prev_tone_id, vol]
				prev_tone_id = tone_id
			tavdata += [-128]
			self.dataline(tavdata)

		# Lengths of notes
		self.out += "\n\tsection notelen data align=1\n"
		self.out += "\n_NoteLengths:\n"
		self.notelist(self.lendata, [0], "L_")

		# Samples for notes
		self.out += "\n\tsection notesamp data align=1\n"
		self.out += "\n_NoteSamples:\n"
		self.notelist(self.samdata, [], "S_")

		return self.out

	def makeDeltas(self, init_delta, lines_per_beat):
		beats_per_line = 1.0/lines_per_beat
		deltas = []
		for t in self.tracks:
			tdeltas = []
			delta = init_delta
			note_i = 0
			for p in range(0, self.length):
				while t.notes[note_i].line <= p:
					if not t.notes[note_i].off:
						delta = p * beats_per_line
					note_i += 1
				tdeltas.append(delta)
			deltas.append(tdeltas)
		return deltas


def extractTrackNotes(xsong, tr, column):
	outside_pattern = 0
	xsequence = xsong.PatternSequence.PatternSequence
	if not xsequence:
		xsequence = xsong.PatternSequence.SequenceEntries.SequenceEntry
	xpatterns = xsong.PatternPool.Patterns.Pattern
	tname = str(xsong.Tracks.SequencerTrack[tr].Name)

	notes = []

	pattern_top = 0
	prev_instr = None
	for posn,xseq in enumerate(xsequence):
		patn = int(xseq.Pattern)
		xpat = xpatterns[patn]
		nlines = int(xpat.NumberOfLines)
		if tr in [int(xmt) for xmt in xseq.MutedTracks.MutedTrack]:
			off = Note(tname, column, pattern_top, posn, patn, 0, "OFF", None, 127)
			notes.append(off)
		else:
			xtrack = xpat.Tracks.PatternTrack[tr]
			for xline in xtrack.Lines.Line:
				index = int(xline("index"))
				if index < nlines:
					line = pattern_top + index
					xcol = xline.NoteColumns.NoteColumn[column - 1]
					if xcol.Note and str(xcol.Note) != "---":
						instr = str(xcol.Instrument)
						if instr == ".." and str(xcol.Note) != "OFF":
							if prev_instr is None:
								raise InputException("Track '%s' column %d pattern %d line %d: Unspecified instrument" % (tname, column, patn, index))
							instr = prev_instr
						prev_instr = instr

						note = Note(tname, column, line, posn, patn, index, xcol.Note, instr, xcol.Volume)
						notes.append(note)

						if (note.velocity == 0 or note.velocity > 127) and not note.off:
							raise InputException("Track '%s' column %d pattern %d line %d: Illegal velocity value" % (tname, column, patn, index))

					# Check for illegal uses of panning, delay and effect columns
					def checkColumn(x, allow_zero, msg):
						if x and not (str(x) == "" or str(x) == ".." or (allow_zero and str(x) == "00")):
							raise InputException("Track '%s' column %d pattern %d line %d: %s" % (tname, column, patn, index, msg))
					checkColumn(xcol.Panning, False, "Panning column used")
					checkColumn(xcol.Delay, True, "Delay column used")
					for xeff in xline.EffectColumns.EffectColumn.Number:
						checkColumn(xeff, True, "Effect column used")
				else:
					outside_pattern += 1
		pattern_top += nlines

	# Add inital OFF and remove redundant OFFs
	if len(notes) > 0 and notes[0].line == 0:
		notes2 = []
		off = False
	else:
		notes2 = [Note(tname, column, 0, 0, int(xsequence[0].Pattern), 0, "OFF", 0, 127)]
		off = True
	for n in notes:
		if n.off:
			if not off:
				notes2.append(n)
				off = True
		else:
			notes2.append(n)
			off = False

	if outside_pattern > 0:
		print " * Track '%s': %d note%s outside patterns ignored" % (tname, outside_pattern, "s" * (outside_pattern > 1))

	return notes2

def pickupReverb(xdevices, reverb, tname, ticklength):
	xplugin = xdevices.AudioPluginDevice
	if len(xplugin) > 1:
		raise InputException("Track '%s' has more than one plugin device" % tname);

	if isactive(xplugin):
		plugin_id = str(xplugin.PluginIdentifier)
		if plugin_id not in ["MetaEffect", "OidosReverb"]:
			raise InputException("Track '%s' has an unknown plugin device" % tname);

		params = [float(x) for x in xplugin.Parameters.Parameter.Value]
		new_reverb = Reverb(params)

		if reverb is not None and not new_reverb == reverb:
			raise InputException("Track '%s' has different reverb from an earlier track" % tname);
		reverb = new_reverb

	return reverb

def makeTracks(xsong, ticklength):
	instruments = []
	reverb_tracks = []
	non_reverb_tracks = []
	reverb = None

	for ii,xinst in enumerate(xsong.Instruments.Instrument):
		params = [float(v) for v in instplugins(xinst).PluginDevice.Parameters.Parameter.Value]
		if params:
			legacy = str(instplugins(xinst).PluginDevice.PluginIdentifier) == "MetaSynth"
			instrument = Instrument(ii, str(xinst.Name), params, legacy)
			instrument.volume = makeVolume(instplugins(xinst).Volume)
			instruments.append(instrument)
			
		else:
			instruments.append(None)

	for tr,xtrack in enumerate(xsong.Tracks.SequencerTrack):
		if str(xtrack.State) != "Active":
			continue

		tname = str(xtrack.Name)
		ncols = int(xtrack.NumberOfVisibleNoteColumns)
		xdevices = xtrack.FilterDevices.Devices
		xdevice = xdevices.SequencerTrackDevice
		if not xdevice:
			xdevice = xdevices.TrackMixerDevice
		volume = makeVolume(xdevice.Volume.Value)
		volume *= makePanning(xdevice.Panning.Value)
		while isactive(xdevices.SendDevice):
			if isactive(xdevices.AudioPluginDevice):
				raise InputException("Track '%s' uses both reverb and send" % tname);
			if str(xdevices.SendDevice.MuteSource) != "true":
				raise InputException("Track '%s' uses send without Mute Source" % tname);
			volume *= makeVolume(xdevices.SendDevice.SendAmount.Value)
			volume *= makePanning(xdevices.SendDevice.SendPan.Value)
			dest = int(float(xdevices.SendDevice.DestSendTrack.Value))
			xdevices = xsong.Tracks.SequencerSendTrack[dest].FilterDevices.Devices
			xdevice = xdevices.SequencerSendTrackDevice
			if not xdevice:
				xdevice = xdevices.SendTrackMixerDevice
			volume *= makeVolume(xdevice.Volume.Value)
			volume *= makePanning(xdevice.Panning.Value)
		volume *= makeVolume(xdevice.PostVolume.Value)
		volume *= makePanning(xdevice.PostPanning.Value)

		for column in range(1, ncols + 1):
			if str(xtrack.NoteColumnStates.NoteColumnState[column - 1]) != "Active":
				continue

			notes = extractTrackNotes(xsong, tr, column)

			track_instrs = []
			for note in notes:
				if not note.off:
					instr = instruments[note.instr]
					if instr is None:
						raise InputException("Track '%s' column %d pattern %d line %d: Undefined instrument (%d)" % (tname, column, note.pat, note.patline, note.instr));
					if note.instr not in track_instrs:
						track_instrs.append(note.instr)

			for instr in track_instrs:
				track = Track(tr, column, tname, notes, volume, instruments)
				if isactive(xdevices.AudioPluginDevice):
					reverb_tracks.append(track)
				else:
					non_reverb_tracks.append(track)
	
		reverb = pickupReverb(xdevices, reverb, tname, ticklength)

	for xtrack in xsong.Tracks.SequencerSendTrack:
		xdevices = xtrack.FilterDevices.Devices
		if xdevices.AudioPluginDevice:
			reverb = pickupReverb(xdevices, reverb, tname, ticklength)

	return (reverb_tracks + non_reverb_tracks), len(reverb_tracks), reverb, instruments

def makeMusic(xsong):
	xgsd = xsong.GlobalSongData
	if xgsd.PlaybackEngineVersion and int(xgsd.PlaybackEngineVersion) >= 4:
		lines_per_minute = float(xgsd.BeatsPerMin) * float(xgsd.LinesPerBeat)
		print "New timing format: %d ticks per minute" % lines_per_minute
	else:
		lines_per_minute = float(xgsd.BeatsPerMin) * 24.0 / float(xgsd.TicksPerLine)
		print "Old timing format: %d ticks per minute" % lines_per_minute
	ticklength = 60.0 / lines_per_minute
	print

	tracks,n_reverb_tracks,reverb,instruments = makeTracks(xsong, ticklength)

	xpositions = xsong.PatternSequence.PatternSequence.Pattern
	if not xpositions:
		xpositions = xsong.PatternSequence.SequenceEntries.SequenceEntry.Pattern
	xpatterns = xsong.PatternPool.Patterns.Pattern
	length = 0
	for xpos in xpositions:
		patn = int(xpos)
		xpat = xpatterns[patn]
		nlines = int(xpat.NumberOfLines)
		length += nlines

	xmstdev = xsong.Tracks.SequencerMasterTrack.FilterDevices.Devices.SequencerMasterTrackDevice
	if not xmstdev:
		xmstdev = xsong.Tracks.SequencerMasterTrack.FilterDevices.Devices.MasterTrackMixerDevice
	master_volume = makeVolume(xmstdev.Volume.Value)
	master_volume *= makePanning(xmstdev.Panning.Value)
	master_volume *= makeVolume(xmstdev.PostVolume.Value)
	master_volume *= makePanning(xmstdev.PostPanning.Value)

	return Music(tracks, instruments, length, ticklength, n_reverb_tracks, reverb, master_volume)


def printMusicStats(music, ansi):
	def form(s):
		f = ""
		for c in s:
			if c == 'T':
				f += "\033[33m%s\033[0m" if ansi else "%s"
			elif c == 'V':
				f += "\033[31m%02X\033[0m" if ansi else "%02X"
			elif c == 'L':
				f += "\033[36m%d\033[0m" if ansi else "%d"
			elif c == 'N':
				f += ":%d" if ansi else ":%d"
			elif c == 'H':
				f += "\033[32m%s\033[0m" if ansi else "%s"
			elif c == 'X':
				f += "\033[34mx\033[0m" if ansi else "x"
			elif c == 'I':
				f += "\033[31m(%d bits)\033[0m" if ansi else "(%d bits)"
			elif c == 'B':
				f += "\033[35m%.f\033[0m" if ansi else "%.f"
			elif c == 'D':
				f += "\033[35m%dm%02ds\033[0m" if ansi else "%dm%02ds"
			else:
				f += c
		return f

	print "Music length: %d ticks at %0.2f ticks per minute" % (music.length, 60.0 / music.ticklength)

	total_burden = 0
	ii = None
	for ti,tn in enumerate(music.track_order):
		if music.n_reverb_tracks > 0 and ti == 0:
			print
			print "Tracks with reverb:"
		if music.n_reverb_tracks > 0 and ti == music.n_reverb_tracks:
			print
			print "Tracks without reverb:"

		track = music.tracks[tn]
		if track.instr != ii:
			print
			ii = track.instr
			instr = music.instrument_map[ii]
			modes = instr.paramblock[0]
			fat = instr.paramblock[1]
			longest = float(instr.paramblock[16]) / SAMPLERATE
			burden = modes * fat * len(instr.tones) * longest
			total_burden += burden
			print form("H") % instr.title
			print " Burden:    " + form(" modes X fat X tones X longest = %d X %d X %d X %.3f = B") % (modes, fat, len(instr.tones), longest, burden)
			tones = ""
			for t in instr.tones:
				tones += form(" TN") % (notename(t), instr.tonecount[t])
			print " Tones:     " + tones
			velocities = ""
			for v in instr.velocities:
				velocities += form(" VN") % (v, instr.velocitycount[v])
			vbits = int(round(math.log(128 / instr.velocity_quantum, 2)))
			print " Velocities:" + velocities + form(" I") % vbits

		print form(" H") % track.title

		lengths = ""
		for l in sorted(track.note_lengths.keys()):
			lengths += form(" LN") % (l, track.note_lengths[l])
		print "  Lengths:  " + lengths

		tnotes = ""
		for t,v in track.tavs:
			num_notes = 0
			for n in [note for note in track.notes if not note.off and note.instr == track.instr]:
				if track.notemap[n] == (t,v):
					num_notes += 1
			tnotes += form(" T/VN") % (notename(t), v, num_notes)
		print "  Notes:    " + tnotes

	seconds = int(round(total_burden / 5000))
	print
	print "Total burden: " + form("B (approximately D on a fast %s)") % (total_burden, seconds / 60, seconds % 60, "CPU")


def writefile(filename, s):
	f = open(filename, "wb")
	f.write(s)
	f.close()
	print "Wrote file %s" % filename

ansi = False
files = []
for a in sys.argv[1:]:
	if a == "-ansi":
		ansi = True
	else:
		files.append(a)

if len(files) != 2:
	print "Usage: %s [-ansi] <input xrns file> <output asm file>" % sys.argv[0]
	sys.exit(1)

infile = files[0]
outfile = files[1]

x = XML.makeXML(zipfile.ZipFile(infile).read("Song.xml"))
try:
	music = makeMusic(x.RenoiseSong)
	print
	printMusicStats(music, ansi)
	print

	writefile(outfile, music.export())

	if len(sys.argv) > 4:
		deltas = music.makeDeltas(0.0, 1.0)
		syncfile = sys.argv[3]
		header = ""
		header += struct.pack('I', 1)
		header += struct.pack('I', music.length*4)
		header += struct.pack('I', len(music.tracks)*music.length*4)
		body = ""
		for t,tdeltas in enumerate(deltas):
			body += struct.pack("%df" % len(tdeltas), *tdeltas)
		data = header + body
		writefile(syncfile, data)

except InputException, e:
	print "Error in input song: %s" % e.message

