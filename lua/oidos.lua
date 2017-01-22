-- MetaSynth module for Oidos synth

local ffi = require("ffi")
local bit = require("bit")
local event_type = ffi.typeof("struct { int delta; unsigned char midi[3]; } *")
local buffer_type = ffi.typeof("float **")

function printf(...)
	print(string.format(...))
	io.flush()
end

function process(num_events, events, num_samples, inputs, outputs, program)
	events = ffi.cast(event_type, events)
	outputs = ffi.cast(buffer_type, outputs)
	program = programs[program]
	if program then
		local event_index = 0
		local pos = 0
		while event_index < num_events do
			if pos < events[event_index].delta then
				render(inputs, outputs, pos, events[event_index].delta)
				pos = events[event_index].delta
			end
			handle_event(events[event_index], program)
			event_index = event_index + 1
		end
		if pos < num_samples then
			render(inputs, outputs, pos, num_samples)
		end
	end
end

persistent.notes = {}
persistent.notes = persistent.notes or {}
notes = persistent.notes

function handle_event(event, program)
	--printf("  %02x %02x %02x", event.midi[0], event.midi[1], event.midi[2])
	local cmd = bit.rshift(event.midi[0], 4)
	local channel = bit.band(event.midi[0], 15)
	local tone = event.midi[1]
	local velocity = event.midi[2]
	if cmd == 9 then
		-- note on
		if program.new then
			note = program.new(channel, tone, velocity)
			note.program = program
			note.channel = channel
			note.tone = tone
			note._time = 0
			note._timestep = 1 / samplerate
			note._released = false
			table.insert(notes, note)
		end
	elseif cmd == 8 then
		-- note off
		for i,note in ipairs(notes) do
			if not note._released and note.channel == channel and note.tone == tone then
				note:off(note._time, velocity)
				note._released = true
			end
		end
	end
end

function render(inputs, outputs, start, stop)
	for i,note in ipairs(notes) do
		for i = start,stop-1 do
			left, right = note:render(note._time)
			outputs[0][i] = outputs[0][i] + left
			outputs[1][i] = outputs[1][i] + right
			note._time = note._time + note._timestep
		end
	end
	for i = 1, #notes do
		while notes[i] and not notes[i]:alive(notes[i]._time) do
			table.remove(notes, i)
		end
	end
end


ffi.cdef[[
	typedef struct {
		double re, im;
	} complex_t;

	complex_t complex_array_mul(int n, complex_t *dest, const complex_t *src1, const complex_t *src2,
		complex_t *filter, double f1add, double f2add);
]]

complex_meta = {}

function complex_meta.__add(a,b)
	return complex(a.re + b.re, a.im + b.im)
end

function complex_meta.__sub(a,b)
	return complex(a.re - b.re, a.im - b.im)
end

function complex_meta.__mul(a,b)
	return complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
end

if not persistent.complex_t then
	persistent.complex_t = ffi.metatype("complex_t", complex_meta)
	persistent.complex_array_t = ffi.typeof("complex_t [?]")
end
complex_t = persistent.complex_t
complex_array_t = persistent.complex_array_t

function complex(x,y)
	c = ffi.new(complex_t)
	c.re = x
	c.im = y
	return c
end


if not persistent.randomdata then
	persistent.randomdata = {}
	local randomstate = { 0x6F15AAF2, 0x4E89D208, 0x9548B49A, 0x9C4FD335 }
	for i = 0,65535 do
		local r = 0
		for s = 1,3 do
			local rs = randomstate[s]
			rs = bit.ror(rs, rs) + randomstate[s+1]
			randomstate[s] = rs
			r = bit.bxor(r, rs)
		end
		persistent.randomdata[i] = r
	end
end
randomdata = persistent.randomdata

OCTAVES = 10
LOWEST_OCTAVE = -4

TOTAL_SEMITONES = OCTAVES*12
SEMITONE_RATIO = math.pow(2, 1/12)
BASE_FREQ = 440/(math.pow(math.pow(2, 1.0/12), 9-12*LOWEST_OCTAVE))/44100*(2*3.14159265358979)

function quantize(value, level)
	local mask = bit.lshift(-1, math.floor(level * 31))
	local add = bit.rshift(-mask, 1)
	local f = ffi.new("float[1]")
	local i = ffi.new("int[1]")
	f[0] = value;
	ffi.copy(i, f, 4)
	i[0] = bit.band(i[0] + add, mask)
	ffi.copy(f, i, 4)
	return f[0]
end

function init_arrays(tone, t)
	local random_index
	function getrandom()
		local r = randomdata[random_index]
		random_index = random_index + 1
		r = r * (1 / 2147483648)
		--printf("%f", r)
		return r
	end

	local modes = math.max(1, math.floor(0.5 + params.modes * 100))
	local fat = math.max(1, math.floor(0.5 + params.fat * 100))
	local seed = math.floor(0.5 + params.seed * 100)
	local overtones = math.floor(0.5 + params.overtones * 100)

	local decaydiff = (params.decayhigh - params.decaylow)
	local decaylow = params.decaylow
	local harmonicity = params.harmonicity * 2 - 1
	local sharpness = params.sharpness * 5 - 4
	local width = 100 * math.pow(params.width, 5)
	local low = (params.filterlow * 2 - 1) * TOTAL_SEMITONES
	local slopelow = math.pow((1 - params.fslopelow), 3)
	local high = (params.filterhigh * 2 - 1) * TOTAL_SEMITONES
	local slopehigh = math.pow((1 - params.fslopehigh), 3)
	local fsweep = math.pow(params.fsweep - 0.5, 3) * 100 * TOTAL_SEMITONES / samplerate

	decaydiff = quantize(decaydiff, params.q_decaydiff)
	decaylow = quantize(decaylow, params.q_decaylow)
	harmonicity = quantize(harmonicity, params.q_harmonicity)
	sharpness = quantize(sharpness, params.q_sharpness)
	width = quantize(width, params.q_width)
	low = quantize(low, params.q_f_low)
	slopelow = quantize(slopelow, params.q_fs_low)
	high = quantize(high, params.q_f_high)
	slopehigh = quantize(slopehigh, params.q_fs_high)
	fsweep = quantize(fsweep, params.q_fsweep)

	local maxdecay = math.max(decaylow, decaylow + decaydiff)

	local n_partials = modes * fat
	local n_partials_in_array = bit.band(n_partials + 1, -2)

	low = low + tone
	high = high + tone
	local fadd1 = -fsweep * slopelow
	local fadd2 = fsweep * slopehigh

	local state = ffi.new(complex_array_t, n_partials_in_array)
	local step = ffi.new(complex_array_t, n_partials_in_array)
	local filter = ffi.new(complex_array_t, n_partials_in_array)

	local i = 0
	for m = 0,modes-1 do
		random_index = m * 256 + seed

		local subtone = math.abs(getrandom())
		local reltone = subtone * overtones
		local decay = decaylow + subtone * decaydiff
		local ampmul = math.pow(decay, 1 / 4096)

		local relfreq = math.pow(SEMITONE_RATIO, reltone)
		local relfreq_ot = math.floor(0.5 + relfreq)
		relfreq = relfreq + (relfreq_ot - relfreq) * harmonicity
		reltone = math.log(relfreq) / math.log(SEMITONE_RATIO)
		local mtone = tone + reltone
		mamp = getrandom() * math.pow(SEMITONE_RATIO, reltone * sharpness)

		for p = 0,fat-1 do
			local ptone = mtone + getrandom() * width

			local phase = BASE_FREQ * math.pow(SEMITONE_RATIO, ptone)
			step[i] = complex(ampmul * math.cos(phase), ampmul * math.sin(phase))

			local amp = mamp
			local angle = getrandom() * math.pi
			amp = amp * math.pow(ampmul, t)
			angle = angle + phase * t
			state[i] = complex(amp * math.cos(angle), amp * math.sin(angle))

			local f1 = 1 - (low - ptone) * slopelow + fadd1 * t
			local f2 = 1 - (ptone - high) * slopehigh + fadd2 * t
			filter[i] = complex(f1, f2)

			i = i + 1
		end
	end

	while i < n_partials_in_array do
		step[i] = complex(0,0)
		state[i] = complex(0,0)
		filter[i] = complex(0,0)
		i = i + 1
	end

	return n_partials, state, step, filter, fadd1, fadd2, maxdecay
end

function update_params(par)
	diff = false
	for k,v in pairs(params) do
		if par[k] ~= v then
			par[k] = v
			diff = true
		end
	end
	return diff
end

cache = {
	par = {}
}

programs = {
	Oidos = {
		paramnames = {
			"seed",
			"modes",
			"fat",
			"width",
			"overtones",
			"sharpness",
			"harmonicity",
			"decaylow",
			"decayhigh",
			"filterlow",
			"fslopelow",
			"filterhigh",
			"fslopehigh",
			"fsweep",
			"gain",
			"attack",
			"release",
			"stereo",
			"-",
			"--",
			"q_decaydiff",
			"q_decaylow",
			"q_harmonicity",
			"q_sharpness",
			"q_width",
			"q_f_low",
			"q_fs_low",
			"q_f_high",
			"q_fs_high",
			"q_fsweep",
			"q_gain",
			"q_attack",
			"q_release"
		},
		new = function(channel, tone, velocity)
			local attack = 2
			if params.attack ~= 0 then
				attack = 1 / (params.attack * params.attack) / samplerate
			end
			local release = 2
			if params.release ~= 0 then
				release = 1 / params.release / samplerate
			end

			attack = quantize(attack, params.q_attack)
			release = quantize(release, params.q_release)

			note = {
				tone = tone,
				velocity = velocity,
				attack = attack,
				release = release,
				releasetime = 999,
				has_state = false,
				is_alive = true,
				t = 0
			}

			function note.off(note, time, velocity)
				note.releasetime = time
			end
			function note.alive(note, time)
				return note.is_alive
			end
			function note.render(note, time)
				local gain = math.pow(4096, params.gain - 0.25)

				gain = quantize(gain, params.q_gain)

				function softclip(v)
					return v * math.sqrt(gain / (1 + (gain - 1) * v * v))
				end

				if update_params(cache.par) then
					cache.notes = {}
				end

				local buffer = cache.notes[note.tone]
				if not buffer then
					buffer = {}
					cache.notes[note.tone] = buffer
					note.has_state = false
					buffer.length = 0
				end

				local left, right
				local ai = bit.rshift(note.t, 10)
				local a = bit.band(note.t, 1023)
				local array = buffer[ai]
				if note.t < buffer.length then
					left = array[a].re
					right = array[a].im
				else
					if not note.has_state then
						local maxdecay
						note.n_partials, note.state, note.step, note.filter, note.fadd1, note.fadd2, maxdecay = init_arrays(note.tone, note.t)
						buffer.rdecaylength = (math.log(maxdecay) / math.log(0.01)) / 4096 * samplerate
						local stereo = params.stereo * (2*math.pi)
						note.leftfac = complex(1 / math.sqrt(note.n_partials), 0)
						note.rightfac = complex(math.cos(stereo) / math.sqrt(note.n_partials), math.sin(stereo) / math.sqrt(note.n_partials))
						note.has_state = true
					end

					local n_partials_in_array = bit.band(note.n_partials + 1, -2)
					local sum = ffi.C.complex_array_mul(n_partials_in_array, note.state, note.state, note.step, note.filter, note.fadd1, note.fadd2)
					left = softclip((sum * note.leftfac).re)
					right = softclip((sum * note.rightfac).re)

					if note.t == buffer.length then
						if not array then
							array = ffi.new(complex_array_t, 1024)
							buffer[ai] = array
						end
						array[a] = complex(left, right)
						buffer.length = buffer.length + 1
					end
				end

				local amp = math.max(0, math.min(1, math.min(time * samplerate * note.attack, 1 - (time - note.releasetime) * samplerate * note.release)))
				left = left * amp * note.velocity / 127
				right = right * amp * note.velocity / 127

				note.t = note.t + 1

				if (time - note.releasetime) * samplerate * note.release > 1 or 1 / time < buffer.rdecaylength then
					note.is_alive = false
				end

				return left, right
			end

			return note
		end
	}
}

printf("MetaSynth Lua code loaded at %s", os.date("%Y-%m-%d %X"))
