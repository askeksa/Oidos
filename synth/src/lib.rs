// We want the DLL to be called Oidos
#![allow(non_snake_case)]

#[macro_use]
extern crate vst2;

mod cache;
mod generate;
mod oidos_generate;
mod synth;

use vst2::plugin::Info;
#[cfg(test)] use vst2::buffer::AudioBuffer;
#[cfg(test)] use vst2::event::Event;
#[cfg(test)] use vst2::plugin::Plugin;

use synth::{SynthInfo, SynthPlugin};
use oidos_generate::{OidosSoundGenerator};


struct OidosSynthInfo;

impl SynthInfo for OidosSynthInfo {
	fn get_info() -> Info {
		Info {
			name: "Oidos".to_string(),
			vendor: "Loonies".to_string(),
			unique_id: 0x50D10,
			version: 2000,

			.. Info::default()
		}
	}
}

type OidosPlugin = SynthPlugin<OidosSoundGenerator, OidosSynthInfo>;

plugin_main!(OidosPlugin);


#[test]
fn test_oidos_plugin() {
	let mut plugin = OidosPlugin::default();
	plugin.set_sample_rate(44100.0);
	plugin.get_info();

	let event = Event::Midi {
		data: [0x90, 45, 127],
		delta_frames: 100,
		live: true,
		note_length: None,
		note_offset: None,
		detune: 0,
		note_off_velocity: 0
	};
	plugin.process_events(vec![event]);

	let mut left = [0f32; 300];
	let mut right = [0f32; 300];
	let buffer = AudioBuffer::new(vec![], vec![&mut left, &mut right]);
	plugin.process(buffer);
}
