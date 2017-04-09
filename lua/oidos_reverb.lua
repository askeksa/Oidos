-- MetaEffect module for Oidos reverb

local ffi = require("ffi")
local bit = require("bit")
local event_type = ffi.typeof("struct { int delta; unsigned char midi[3]; } *")
local buffer_type = ffi.typeof("float **")

function printf(...)
	print(string.format(...))
	io.flush()
end


BUFSIZE = 65536
NBUFS = 200
MAXDELAY = 25600


index = 0

buffer = {}
flstate = {}
fhstate = {}
dlstate = {}
dhstate = {}
for b = 0, NBUFS-1 do
	buffer[b] = {}
	for i = 0, BUFSIZE-1 do
		buffer[b][i] = 0
	end
	flstate[b] = 0
	fhstate[b] = 0
	dlstate[b] = 0
	dhstate[b] = 0
end

if not persistent.randomdata then
	persistent.randomdata = {}
	local randomstate = { 0x6F15AAF2, 0x4E89D208, 0x9548B49A, 0x9C4FD335 }
	for i = 0,262143 do
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

function filter(state_array, index, value, strength)
	local delta = (value - state_array[index]) * strength
	state_array[index] = state_array[index] + delta
	return state_array[index]
end

function process(num_events, events, num_samples, inputs, outputs, program)
	inputs = ffi.cast(buffer_type, inputs)
	outputs = ffi.cast(buffer_type, outputs)

	if program ~= "reverb" then
		return
	end

	-- Temp buffer for reverb
	temp = {}
	temp[0] = {}
	temp[1] = {}
	for i = 0, num_samples-1 do
		temp[0][i] = 0
		temp[1][i] = 0
	end

	-- Get parameter values
	local delaymin   = math.floor(params.delaymin * math.floor(MAXDELAY / 256) + 0.5) * 256
	local delaymax   = math.floor(params.delaymax * math.floor(MAXDELAY / 256) + 0.5) * 256
	local delayadd   = math.floor(params.delayadd * math.floor(MAXDELAY / 256) + 0.5) * 256
	local filterlow  = math.min(1, quantize(math.pow(params.filterlow,  2), params.q_flow))
	local filterhigh = math.min(1, quantize(math.pow(params.filterhigh, 2), params.q_fhigh))
	local dampenlow  = math.min(1, quantize(math.pow(params.dampenlow,  2), params.q_dlow))
	local dampenhigh = math.min(1, quantize(math.pow(params.dampenhigh, 2), params.q_dhigh))
	local nbufs      = math.floor(params.n * (NBUFS / 2) + 0.5) * 2
	local seed       = math.floor(params.seed * 100 + 0.5) * 2048
	local mix        = params.mix * 10 / math.sqrt(nbufs)

	-- Left and right volume factors
	local volumes = {}
	volumes[0] = quantize(mix * math.sqrt(2 * (1 - params.pan)), params.q_mixpan)
	volumes[1] = quantize(mix * math.sqrt(2 * params.pan),       params.q_mixpan)

	local b = 0
	for delay = delaymax, delaymin+1, -1 do
		-- Random value as unsigned integer
		local random = randomdata[seed + delay]
		if random < 0 then
			random = random + 0x100000000
		end

		-- Is there an echo with this delay?
		if math.floor(random * (delay - delaymin) / 0x100000000) < nbufs - b then
			-- Alternate between left and right side
			local c = bit.band(b, 1)
			-- Echo feedback factor to match the given half-time
			local feedback = math.pow(0.5, delay / (params.halftime * samplerate))

			for i = 0, num_samples-1 do
				-- Extract delayed signal
				local out_index = bit.band(index + i - delay - delayadd, BUFSIZE-1)
				local out = buffer[b][out_index]
				temp[c][i] = temp[c][i] + out * volumes[c]

				-- Filter input
				local input = inputs[c][i]
				local f_input = filter(flstate, b, input, filterhigh) - filter(fhstate, b, input, filterlow)

				-- Filter echo
				local echo_index = bit.band(index + i - delay, BUFSIZE-1)
				local echo = buffer[b][echo_index]
				local f_echo = filter(dlstate, b, echo, dampenhigh) - filter(dhstate, b, echo, dampenlow)

				-- Sum input with attenuated echo
				local in_index = bit.band(index + i, BUFSIZE-1)
				buffer[b][in_index] = f_echo * feedback + f_input
			end

			-- Next delay buffer
			b = b + 1
			assert(b <= nbufs)
		end
	end
	index = index + num_samples

	-- Add reverb to input sound
	for i = 0, num_samples-1 do
		outputs[0][i] = inputs[0][i] + temp[0][i]
		outputs[1][i] = inputs[1][i] + temp[1][i]
	end
end


programs = {
	reverb = {
		paramnames = {
			"mix",
			"pan",
			"delaymin",
			"delaymax",
			"delayadd",
			"halftime",
			"filterlow",
			"filterhigh",
			"dampenlow",
			"dampenhigh",
			"n",
			"seed",
			"-",
			"--",
			"---",
			"q_mixpan",
			"q_flow",
			"q_fhigh",
			"q_dlow",
			"q_dhigh"
		}
	}
}

printf("Effect Lua code loaded at %s", os.date("%Y-%m-%d %X"))
