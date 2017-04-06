
#![allow(dead_code)]

use std::{f32, f64};
use std::mem::transmute;
use std::ops::{Index};
#[cfg(test)] use std::collections::HashMap;

use generate::{SoundGenerator, SoundParameters};


const TOTAL_SEMITONES: f32 = 120f32;
const NOISESIZE: usize = 64;

const NAMES: &'static [&'static str] = &[
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
	"fsweeplow",
	"filterhigh",
	"fslopehigh",
	"fsweephigh",
	"gain",
	"attack",
	"release",
	"-",
	"q_decaydiff",
	"q_decaylow",
	"q_harmonicity",
	"q_sharpness",
	"q_width",
	"q_f_low",
	"q_fs_low",
	"q_fsw_low",
	"q_f_high",
	"q_fs_high",
	"q_fsw_high",
	"q_gain",
	"q_attack",
	"q_release"
];


pub struct OidosRandomData {
	data: Vec<u32>
}

impl Default for OidosRandomData {
	fn default() -> OidosRandomData {
		let mut data = Vec::with_capacity(NOISESIZE*NOISESIZE*NOISESIZE);
		let mut randomstate: [u32; 4] = [ 0x6F15AAF2, 0x4E89D208, 0x9548B49A, 0x9C4FD335 ];
		for _ in 0..NOISESIZE*NOISESIZE*NOISESIZE {
			let mut r = 0u32;
			for s in 0..3 {
				let mut rs = randomstate[s];
				rs = rs.rotate_right(rs).wrapping_add(randomstate[s+1]);
				randomstate[s] = rs;
				r = r ^ rs;
			}
			data.push(r);
		}

		OidosRandomData {
			data : data
		}
	}
}

#[test]
fn test_random_data() {
	let random = OidosRandomData::default();
	assert_eq!(random.data.len(), NOISESIZE*NOISESIZE*NOISESIZE);
	assert_eq!(*random.data.first().unwrap(), 0xCAADAA7B);
	assert_eq!(*random.data.last().unwrap(),  0xB08A4BA7);
}


fn quantize(value: f32, level: f32) -> f32 {
	let bit = 1 << ((level * 31.0).floor() as i32);
	let mask = !bit + 1;
	let add = bit >> 1;
	let mut bits = unsafe { transmute::<f32, u32>(value) };
	bits = (bits + add) & mask;
	if bits == 0x80000000 {
		bits = 0x00000000;
	}
	unsafe { transmute::<u32, f32>(bits) }
}

#[derive(Clone, PartialEq)]
pub struct OidosSoundParameters {
	modes: u8,
	fat: u8,
	seed: u8,
	overtones: u8,

	decaylow: f32,
	decaydiff: f32,
	harmonicity: f32,
	sharpness: f32,
	width: f32,

	f_low: f32,
	f_slopelow: f32,
	f_sweeplow: f32,
	f_high: f32,
	f_slopehigh: f32,
	f_sweephigh: f32,

	gain: f32,

	base_freq: f32
}

impl SoundParameters for OidosSoundParameters {
	fn names() -> &'static [&'static str] {
		&NAMES
	}

	fn default_value(name: &str) -> f32 {
		if name.starts_with("q_") {
			return 0.0;
		}

		match name {
			"harmonicity" | "decaylow" | "decayhigh" => 1.0,
			"filterhigh" => 0.8,
			"fsweeplow" | "fsweephigh" => 0.5,
			_ => 0.2
		}
	}

	fn display<P: Index<&'static str, Output = f32>>(&self, name: &'static str, p: &P) -> (String, String) {
		(format!("{}", p[name]), format!("")) // TODO
	}

	fn build<P: Index<&'static str, Output = f32>>(p: &P, sample_rate: f32) -> OidosSoundParameters {
		let mut params = OidosSoundParameters {
			modes:       (p["modes"]     * 100.0 + 0.5).floor().max(1.0) as u8,
			fat:         (p["fat"]       * 100.0 + 0.5).floor().max(1.0) as u8,
			seed:        (p["seed"]      * 100.0 + 0.5).floor() as u8,
			overtones:   (p["overtones"] * 100.0 + 0.5).floor() as u8,

			decaylow:    p["decaylow"],
			decaydiff:   p["decayhigh"] - p["decaylow"],
			harmonicity: p["harmonicity"] * 2.0 - 1.0,
			sharpness:   p["sharpness"] * 5.0 - 4.0,
			width:       p["width"].powi(5) * 100.0,

			f_low:       (p["filterlow"] * 2.0 - 1.0)    * TOTAL_SEMITONES,
			f_slopelow:  (1.0 - p["fslopelow"]).powi(3),
			f_sweeplow:  (p["fsweeplow"] - 0.5).powi(3)  * TOTAL_SEMITONES * 100.0 / sample_rate,
			f_high:      (p["filterhigh"] * 2.0 - 1.0)   * TOTAL_SEMITONES,
			f_slopehigh: (1.0 - p["fslopehigh"]).powi(3),
			f_sweephigh: (p["fsweephigh"] - 0.5).powi(3) * TOTAL_SEMITONES * 100.0 / sample_rate,

			gain:        4096f32.powf(p["gain"] - 0.25),

			base_freq:   440.0 * 2f32.powf(-57.0 / 12.0) / sample_rate * 2.0 * f32::consts::PI
		};

		params.decaylow = quantize(params.decaylow, p["q_decaylow"]);
		params.decaydiff = quantize(params.decaydiff, p["q_decaydiff"]);
		params.harmonicity = quantize(params.harmonicity, p["q_harmonicity"]);
		params.sharpness = quantize(params.sharpness, p["q_sharpness"]);
		params.width = quantize(params.width, p["q_width"]);

		params.f_low = quantize(params.f_low, p["q_f_low"]);
		params.f_slopelow = quantize(params.f_slopelow, p["q_fs_low"]);
		params.f_sweeplow = quantize(params.f_sweeplow, p["q_fsw_low"]);
		params.f_high = quantize(params.f_high, p["q_f_high"]);
		params.f_slopehigh = quantize(params.f_slopehigh, p["q_fs_high"]);
		params.f_sweephigh = quantize(params.f_sweephigh, p["q_fsw_high"]);

		params.gain = quantize(params.gain, p["q_gain"]);

		params
	}

	fn attack<P: Index<&'static str, Output = f32>>(p: &P, sample_rate: f32) -> f32 {
		let attack = p["attack"];
		quantize(if attack == 0.0 {
			2.0
		} else {
			1.0 / (attack * attack * sample_rate)
		}, p["q_attack"])
	}

	fn release<P: Index<&'static str, Output = f32>>(p: &P, sample_rate: f32) -> f32 {
		let release = p["release"];
		quantize(if release == 0.0 {
			2.0
		} else {
			1.0 / (release * sample_rate)
		}, p["q_release"])
	}

}

#[test]
fn test_oidos_sound_parameters() {
	let names = OidosSoundParameters::names();
	let mut map = HashMap::new();
	for name in names {
		map.insert(*name, OidosSoundParameters::default_value(name));
	}
	let param = OidosSoundParameters::build(&map, 44100.0);
	assert_eq!(param.base_freq, 0.00232970791933f32);
}


pub struct OidosSoundGenerator {
	n_partials:  usize,

	state_re:    Vec<f64>,
	state_im:    Vec<f64>,
	step_re:     Vec<f64>,
	step_im:     Vec<f64>,
	filter_low:  Vec<f64>,
	filter_high: Vec<f64>,

	f_add_low:   f64,
	f_add_high:  f64,

	gain:        f64
}

impl SoundGenerator for OidosSoundGenerator {
	type Parameters = OidosSoundParameters;
	type Output = f32;
	type Global = OidosRandomData;

	fn new(param: &OidosSoundParameters, tone: u8, time: usize, random: &OidosRandomData) -> OidosSoundGenerator {
		let n_partials = param.modes as usize * param.fat as usize;
		let n_partials_in_array = (n_partials + 3) & !3;
		let mut gen = OidosSoundGenerator {
			n_partials:   n_partials,

			state_re:     Vec::with_capacity(n_partials_in_array),
			state_im:     Vec::with_capacity(n_partials_in_array),
			step_re:      Vec::with_capacity(n_partials_in_array),
			step_im:      Vec::with_capacity(n_partials_in_array),
			filter_low:   Vec::with_capacity(n_partials_in_array),
			filter_high:  Vec::with_capacity(n_partials_in_array),

			f_add_low:    (-param.f_sweeplow * param.f_slopelow) as f64,
			f_add_high:   (param.f_sweephigh * param.f_slopehigh) as f64,

			gain:         param.gain as f64
		};

		let f_lowlimit = param.f_low as f64 + tone as f64;
		let f_highlimit = param.f_high as f64 + tone as f64;

		for m in 0..param.modes as usize {
			let mut random_index = m * 256 + param.seed as usize;
			let mut getrandom = || {
				let r = random.data[random_index];
				random_index += 1;
				r as i32 as f64 / 0x80000000u32 as f64
			};

			let subtone = getrandom().abs();
			let reltone = subtone * param.overtones as f64;
			let decay = param.decaylow as f64 + subtone * param.decaydiff as f64;
			let ampmul = decay.powf(1.0 / 4096.0);

			let relfreq = 2f64.powf(reltone / 12.0);
			let relfreq_ot = (relfreq + 0.5).floor();
			let relfreq_h = relfreq + (relfreq_ot - relfreq) * param.harmonicity as f64;
			let reltone = relfreq_h.log2() * 12.0;
			let mtone = tone as f64 + reltone;
			let mamp = getrandom() * 2f64.powf(reltone * param.sharpness as f64 / 12.0);

			for _ in 0..param.fat as usize {
				let ptone = mtone + getrandom() * param.width as f64;
				let phase = param.base_freq as f64 * 2f64.powf(ptone / 12.0);
				gen.step_re.push(ampmul * phase.cos());
				gen.step_im.push(ampmul * phase.sin());

				let angle = getrandom() * f64::consts::PI + phase * time as f64;
				let amp = mamp * ampmul.powi(time as i32);
				gen.state_re.push(amp * angle.cos());
				gen.state_im.push(amp * angle.sin());

				let f_startlow = 1.0 - (f_lowlimit - ptone) * param.f_slopelow as f64;
				let f_starthigh = 1.0 - (ptone - f_highlimit) * param.f_slopehigh as f64;
				gen.filter_low.push(f_startlow + gen.f_add_low * time as f64);
				gen.filter_high.push(f_starthigh + gen.f_add_high * time as f64);
			}
		}

		for _ in n_partials..n_partials_in_array {
			gen.state_re.push(0.0);
			gen.state_im.push(0.0);
			gen.step_re.push(0.0);
			gen.step_im.push(0.0);
			gen.filter_low.push(0.0);
			gen.filter_high.push(0.0);
		}

		gen
	}

	fn produce_sample(&mut self) -> f32 {
		let s = unsafe {
			additive_core(self.state_re.as_mut_ptr(), self.state_im.as_mut_ptr(),
		                  self.step_re.as_ptr(), self.step_im.as_ptr(),
		                  self.filter_low.as_mut_ptr(), self.filter_high.as_mut_ptr(),
		                  self.f_add_low, self.f_add_high, self.n_partials)
		};
		(s * (self.gain / (self.n_partials as f64 + (self.gain - 1.0) * s * s)).sqrt()) as f32
	}
}

extern "cdecl" {
	fn additive_core(state_re: *mut f64, state_im: *mut f64, step_re: *const f64, step_im: *const f64,
	                 filter_low: *mut f64, filter_high: *mut f64, f_add_low: f64, f_add_high: f64, n: usize) -> f64;
}
