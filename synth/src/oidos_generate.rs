
#![allow(dead_code)]

use std::{f32, f64};
use std::ops::{Index};
#[cfg(test)] use std::collections::HashMap;

use generate::{SoundGenerator, SoundParameters};


const TOTAL_SEMITONES: f32 = 120 as f32;
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
	"release"
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
		OidosSoundParameters {
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

			gain:        (4096 as f32).powf(p["gain"] - 0.25),

			base_freq:   440.0 * 2f32.powf(-57.0 / 12.0) / sample_rate * 2.0 * f32::consts::PI
		}
	}

	fn attack<P: Index<&'static str, Output = f32>>(p: &P, sample_rate: f32) -> f32 {
		let a = p["attack"];
		if a == 0.0 {
			2.0
		} else {
			1.0 / (a * a * sample_rate)
		}
	}

	fn release<P: Index<&'static str, Output = f32>>(p: &P, sample_rate: f32) -> f32 {
		let r = p["release"];
		if r == 0.0 {
			2.0
		} else {
			1.0 / (r * sample_rate)
		}
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
		let mut gen = OidosSoundGenerator {
			n_partials:   n_partials,

			state_re:     Vec::with_capacity(n_partials),
			state_im:     Vec::with_capacity(n_partials),
			step_re:      Vec::with_capacity(n_partials),
			step_im:      Vec::with_capacity(n_partials),
			filter_low:   Vec::with_capacity(n_partials),
			filter_high:  Vec::with_capacity(n_partials),

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

		gen
	}

	fn produce_sample(&mut self) -> f32 {
		let s = self.oscillator_step();
		self.softclip(s) as f32
	}
}

impl OidosSoundGenerator {
	fn oscillator_step(&mut self) -> f64 {
		let mut s: f64 = 0.0;
		for i in 0..self.n_partials {
			let state_re = self.state_re[i];
			let state_im = self.state_im[i];
			let step_re = self.step_re[i];
			let step_im = self.step_im[i];
			let newstate_re = state_re * step_re - state_im * step_im;
			let newstate_im = state_re * step_im + state_im * step_re;
			self.state_re[i] = newstate_re;
			self.state_im[i] = newstate_im;

			let f_low = self.filter_low[i];
			let f_high = self.filter_high[i];
			self.filter_low[i] = f_low + self.f_add_low;
			self.filter_high[i] = f_high + self.f_add_high;
			let f = f_low.min(f_high).min(1.0).max(0.0);
			s += newstate_re * f;
		}

		s
	}

	fn softclip(&self, v: f64) -> f64 {
		v * (self.gain / (1.0 + (self.gain - 1.0) * v * v)).sqrt()
	}
}

