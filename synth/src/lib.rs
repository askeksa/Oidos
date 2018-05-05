// We want the DLL to be called Oidos
#![allow(non_snake_case)]

#[macro_use]
extern crate vst;
extern crate rand;

mod cache;
mod generate;
mod oidos_generate;
mod synth;

#[cfg(test)] use rand::{thread_rng, Rng};

use vst::plugin::Info;
#[cfg(test)] use vst::buffer::AudioBuffer;
#[cfg(test)] use vst::event::Event;
#[cfg(test)] use vst::plugin::Plugin;

use synth::{SynthInfo, SynthPlugin};
use oidos_generate::{OidosSoundGenerator};


struct OidosSynthInfo;

impl SynthInfo for OidosSynthInfo {
	fn get_info() -> Info {
		Info {
			name: "Oidos".to_string(),
			vendor: "Loonies".to_string(),
			unique_id: 0x50D10,
			version: 2100,

			.. Info::default()
		}
	}
}

type OidosPlugin = SynthPlugin<OidosSoundGenerator, OidosSynthInfo>;

plugin_main!(OidosPlugin);


#[test]
fn test_oidos_plugin() {
	let mut plugin = OidosPlugin::default();
	plugin.set_sample_rate(500.0);
	let nump = plugin.get_info().parameters;

	let mut r = thread_rng();
	for _it in 0..100 {
		for _p in 0..r.gen_range(0, 2) {
			plugin.set_parameter(r.gen_range(0, nump), r.gen_range(0f32, 1f32));
		}

		let block_size: usize = r.gen_range(100, 200);
		let mut events = Vec::new();
		for _e in 0..r.gen_range(0, 3) {
			let on = r.gen_weighted_bool(3);
			let event = Event::Midi {
				data: [if on { 0x90u8 } else { 0x80u8 }, r.gen_range(60, 65), 127],
				delta_frames: r.gen_range(0, block_size as i32),
				live: true,
				note_length: None,
				note_offset: None,
				detune: 0,
				note_off_velocity: 0
			};
			events.push(event);
		}
		events.sort_by_key(|e| {
			if let Event::Midi { delta_frames, ..} = *e {
				delta_frames
			} else {
				0
			}});
		plugin.process_events(events);

		let mut left = vec![0f32; block_size];
		let mut right = vec![0f32; block_size];
		let buffer = AudioBuffer::new(vec![], vec![&mut left, &mut right]);
		plugin.process(buffer);
	}
}
