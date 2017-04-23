// We want the DLL to be called OidosReverb
#![allow(non_snake_case)]

#[macro_use]
extern crate vst2;

use std::cmp::Ordering;
use std::mem::transmute;

use vst2::buffer::AudioBuffer;
use vst2::plugin::{Category, Info, Plugin};

const BUFSIZE: usize = 65536;
const NBUFS: usize = 200;
const NOISESIZE: usize = 64;

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


struct OidosReverbParameters {
	nbufs: usize,
	delaymin: usize,
	delaymax: usize,
	delayadd: usize,
	seed: usize,

	max_decay: f32,
	decay_mul: f32,

	filterlow: f32,
	filterhigh: f32,
	dampenlow: f32,
	dampenhigh: f32,

	volumes: [f32; 2]
}

fn p100(value: f32) -> usize {
	(value * 100.0 + 0.5).floor() as usize
}

impl OidosReverbParameters {
	fn make(values: &[f32], sample_rate: f32) -> OidosReverbParameters {
		let nbufs    = p100(values[10]) * 2;
		let delaymin = p100(values[2]) * 256;
		let delaymax = p100(values[3]) * 256;
		let delayadd = p100(values[4]) * 256;
		let seed     = p100(values[11]) * 2048;
		let mix      = values[0] * 10.0 / (nbufs as f32).sqrt();
		let decay    = (0.5 as f32).powf(1.0 / (values[5].max(0.01) * sample_rate));
		OidosReverbParameters {
			nbufs:      nbufs,
			delaymin:   delaymin,
			delaymax:   delaymax,
			delayadd:   delayadd,
			seed:       seed,

			max_decay:  decay.powi(delaymax as i32),
			decay_mul:  1.0 / decay,

			filterlow:  quantize(values[6].powi(2), values[16]).min(1.0),
			filterhigh: quantize(values[7].powi(2), values[17]).min(1.0),
			dampenlow:  quantize(values[8].powi(2), values[18]).min(1.0),
			dampenhigh: quantize(values[9].powi(2), values[19]).min(1.0),

			volumes: [
			            quantize(mix * (2.0 * (1.0 - values[1])).sqrt(), values[15]),
			            quantize(mix * (2.0 * values[1]        ).sqrt(), values[15])
			         ]
		}
	}
}

struct OidosReverbPlugin {
	random: OidosRandomData,
	sample_rate: f32,
	param: OidosReverbParameters,
	param_values: Vec<f32>,
	delay_buffers: Vec<Vec<f64>>,
	flstate: Vec<f64>,
	fhstate: Vec<f64>,
	dlstate: Vec<f64>,
	dhstate: Vec<f64>,
	buffer_index: usize
}

impl Default for OidosReverbPlugin {
	fn default() -> OidosReverbPlugin {
		let param_values = vec![
			0.1,  0.5,  0.07, 0.13, 0.0,
			0.5,  0.1,  0.6,  0.1,  0.7,
			0.32, 0.32, 0.0,  0.0,  0.0,
			0.0,  0.0,  0.0,  0.0,  0.0
		];
		let sample_rate = 44100.0;
		OidosReverbPlugin {
			random: OidosRandomData::default(),
			sample_rate: sample_rate,
			param: OidosReverbParameters::make(&param_values, sample_rate),
			param_values: param_values,
			delay_buffers: vec![vec![0f64; BUFSIZE]; NBUFS],
			flstate: vec![0f64; NBUFS],
			fhstate: vec![0f64; NBUFS],
			dlstate: vec![0f64; NBUFS],
			dhstate: vec![0f64; NBUFS],
			buffer_index: 0
		}
	}
}

impl Plugin for OidosReverbPlugin {
	fn get_info(&self) -> Info {
		Info {
			name: "OidosReverb".to_string(),
			vendor: "Loonies".to_string(),
			unique_id: 0x550D10,
			version: 2100,
			presets: 0,
			parameters: 20,
			inputs: 2,
			outputs: 2,
			category: Category::Effect,
			f64_precision: false,

			.. Info::default()
		}
	}

	fn set_sample_rate(&mut self, rate: f32) {
		self.sample_rate = rate;
	}

	fn get_parameter_name(&self, index: i32) -> String {
		[
			"mix", "pan", "delaymin", "delaymax", "delayadd",
			"halftime", "filterlow", "filterhigh", "dampenlow", "dampenhigh",
			"n", "seed", "-", "--", "---",
			"q_mixpan", "q_flow", "q_fhigh", "q_dlow", "q_dhigh"
		][index as usize].to_string()
	}

	fn get_parameter(&self, index: i32) -> f32 {
		self.param_values[index as usize]
	}

	fn set_parameter(&mut self, index: i32, value: f32) {
		self.param_values[index as usize] = value;
		self.param = OidosReverbParameters::make(&self.param_values, self.sample_rate);
	}

	fn get_parameter_text(&self, index: i32) -> String {
		let pantext = |pan: f32| -> String {
			match pan.partial_cmp(&0.5) {
				Some(Ordering::Equal)   => format!("Center"),
				Some(Ordering::Less)    => format!("{:.0} L", (0.5 - pan) * 100.0),
				Some(Ordering::Greater) => format!("{:.0} R", (pan - 0.5) * 100.0),
				None                    => format!("?")
			}
		};

		let p = &self.param;
		match index {
			0/* mix */        => format!("{:.1}", self.param_values[0] * 10.0),
			1/* pan */        => pantext(self.param_values[1]),
			2/* delaymin */   => format!("{:.0}", 1000.0 * (p.delaymin as f32 / self.sample_rate)),
			3/* delaymax */   => format!("{:.0}", 1000.0 * (p.delaymax as f32 / self.sample_rate)),
			4/* delayadd */   => format!("{:.0}", 1000.0 * (p.delayadd as f32 / self.sample_rate)),
			5/* halftime */   => format!("{:.2}", self.param_values[5]),
			6/* filterlow */  => format!("{:.4}", self.param_values[6].powi(2)),
			7/* filterhigh */ => format!("{:.4}", self.param_values[7].powi(2)),
			8/* dampenlow */  => format!("{:.4}", self.param_values[8].powi(2)),
			9/* dampenhigh */ => format!("{:.4}", self.param_values[9].powi(2)),
			10/* n */         => format!("{}", p.nbufs),
			11/* seed */      => format!("{}", p.seed / 2048),

			15/* q_mixpan */  => {
				let mix = ((p.volumes[0].powi(2) + p.volumes[1].powi(2)) / 2.0 * p.nbufs as f32).sqrt();
				let pan = 1.0 / ((p.volumes[0] / p.volumes[1]).powi(2) + 1.0);
				format!("{:.1} {}", mix, pantext(pan))
			},
			16/* q_flow */    => format!("{:.4}", p.filterlow),
			17/* q_fhigh */   => format!("{:.4}", p.filterhigh),
			18/* q_dlow */    => format!("{:.4}", p.dampenlow),
			19/* q_dhigh */   => format!("{:.4}", p.dampenhigh),

			_ => format!("-")
		}
	}

	fn get_parameter_label(&self, index: i32) -> String {
		match index {
			2 | 3 | 4 => "ms",
			5 => "s",
			_ => ""
		}.to_string()
	}

	fn process(&mut self, buffer: AudioBuffer<f32>) {
		let (inputs, mut outputs) = buffer.split();
		let size = inputs[0].len();

		for i in 0..size {
			for c in 0..2 {
				outputs[c][i] = inputs[c][i];
			}
		}

		let p = &self.param;
		let mut b: usize = 0;
		let mut feedback = p.max_decay as f64;
		for delay in (p.delaymin+1..p.delaymax+1).rev() {
			let random = self.random.data[p.seed + delay];
			// Is there an echo with this delay?
			if (random as u64 * (delay - p.delaymin) as u64) >> 32 < (p.nbufs - b) as u64 {
				let c = b & 1;
				for i in 0..size {
					// Extract delayed signal
					let out_index = (self.buffer_index + i - delay - p.delayadd) & (BUFSIZE - 1);
					let out = self.delay_buffers[b][out_index];
					outputs[c][i] += out as f32 * p.volumes[c];

					// Filter input
					let input = inputs[c][i] as f64;
					let f_input = filter(&mut self.flstate[b], input, p.filterhigh) - filter(&mut self.fhstate[b], input, p.filterlow);

					// Filter echo
					let echo_index = (self.buffer_index + i - delay) & (BUFSIZE - 1);
					let echo = self.delay_buffers[b][echo_index];
					let f_echo = filter(&mut self.dlstate[b], echo, p.dampenhigh) - filter(&mut self.dhstate[b], echo, p.dampenlow);

					// Sum input with attenuated echo
					let in_index = (self.buffer_index + i) & (BUFSIZE - 1);
					self.delay_buffers[b][in_index] = f_echo * feedback + f_input;
				}

				b += 1;
			}

			feedback *= p.decay_mul as f64;
		}

		self.buffer_index += size;
	}
}

fn filter(state: &mut f64, value: f64, strength: f32) -> f64 {
	let filtered = *state + (value - *state) * strength as f64;
	*state = filtered;
	filtered
}

plugin_main!(OidosReverbPlugin);
