// We want the DLL to be called OidosReverb
#![allow(non_snake_case)]

#[macro_use]
extern crate vst2;

use vst2::buffer::AudioBuffer;
use vst2::plugin::{Category, Info, Plugin};

const BUFSIZE: usize = 65536;
const NBUFS: usize = 100;
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
		let nbufs    = p100(values[10]);
		let delaymin = p100(values[2]) * 256;
		let delaymax = p100(values[3]) * 256;
		let delayadd = p100(values[4]) * 256;
		let seed     = p100(values[11]) * 2048;
		let mix      = values[0] * 10.0 / (nbufs as f32).sqrt();
		let decay    = (0.5 as f32).powf(1.0 / (values[5] * sample_rate));
		OidosReverbParameters {
			nbufs:      nbufs,
			delaymin:   delaymin,
			delaymax:   delaymax,
			delayadd:   delayadd,
			seed:       seed,

			max_decay:  decay.powi(delaymax as i32),
			decay_mul:  1.0 / decay,

			filterlow:  values[6].powi(2),
			filterhigh: values[7].powi(2),
			dampenlow:  values[8].powi(2),
			dampenhigh: values[9].powi(2),

			volumes: [
			            mix * (2.0 * (1.0 - values[1])).sqrt(),
			            mix * (2.0 * values[1]).sqrt()
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
			0.1, 0.5, 0.05, 0.10, 0.0,
			0.5, 0.2, 0.8, 0.2, 0.8,
			0.5, 0.0, 0.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 0.0, 0.0
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
			version: 2000,
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
