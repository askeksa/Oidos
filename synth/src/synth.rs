
use std::collections::{HashMap, VecDeque};
use std::marker::PhantomData;

use vst2::api::Supported;
use vst2::buffer::AudioBuffer;
use vst2::event::Event;
use vst2::plugin::{CanDo, Category, Info, Plugin};

use cache::SoundCache;
use generate::{Sample, SoundGenerator, SoundParameters};


#[allow(dead_code)]
pub enum MidiCommand {
	NoteOn      { channel: u8, key: u8, velocity: u8 },
	NoteOff     { channel: u8, key: u8, velocity: u8 },
	AllNotesOff { channel: u8,          velocity: u8 },
	AllSoundOff { channel: u8,          velocity: u8 },
	Unknown
}

impl MidiCommand {
	fn fromData(data: &[u8; 3]) -> MidiCommand {
		match data[0] & 0xF0 {
			0x80 => MidiCommand::NoteOff { channel: data[0] & 0x0F, key: data[1], velocity: data[2] },
			0x90 => MidiCommand::NoteOn  { channel: data[0] & 0x0F, key: data[1], velocity: data[2] },
			0xB0 => match data[1] {
				120 => MidiCommand::AllSoundOff { channel: data[0] & 0x0F, velocity: data[2] },
				123 => MidiCommand::AllNotesOff { channel: data[0] & 0x0F, velocity: data[2] },
				_   => MidiCommand::Unknown
			},
			_    => MidiCommand::Unknown
		}
	}
}

pub struct MidiEvent {
	time: usize,
	command: MidiCommand,
}

struct Note {
	time: usize,
	tone: u8,
	velocity: u8,
	attack: f32,
	release: f32,

	release_time: Option<usize>
}

impl Note {
	fn new(tone: u8, velocity: u8, attack: f32, release: f32) -> Note {
		Note {
			time: 0,
			tone: tone,
			velocity: velocity,
			attack: attack,
			release: release,

			release_time: None
		}
	}

	fn produce_sample<G: SoundGenerator>(&mut self, cache: &mut Vec<SoundCache<G>>, param: &G::Parameters, global: &G::Global) -> Sample {
		let sample = cache[self.tone as usize].get_sample(self.time, param, global);
		self.time += 1;

		let amp = self.attack_amp().min(self.release_amp()) * (self.velocity as f32 / 127.0);
		sample * amp
	}

	fn attack_amp(&self) -> f32 {
		(self.time as f32 * self.attack).min(1.0)
	}

	fn release_amp(&self) -> f32 {
		match self.release_time {
			None => 1.0,
			Some(t) => (1.0 - (self.time - t) as f32 * self.release).max(0.0)
		}
	}

	fn release(&mut self, _velocity: u8) {
		self.release_time = Some(self.time);
	}

	fn is_released(&mut self) -> bool {
		self.release_time.is_some()
	}

	fn is_alive(&mut self) -> bool {
		self.release_amp() > 0.0
	}
}


pub trait SynthInfo {
	fn get_info() -> Info;
}

pub struct SynthPlugin<G: SoundGenerator, S: SynthInfo> {
	sample_rate: f32,
	time: usize,
	notes: Vec<Note>,
	events: VecDeque<MidiEvent>,
	cache: Vec<SoundCache<G>>,

	sound_params: G::Parameters,
	param_names: Vec<&'static str>,
	param_values: Vec<f32>,
	param_map: HashMap<&'static str, f32>,

	global: G::Global,

	phantom: PhantomData<S>
}

impl<G: SoundGenerator, S: SynthInfo> Default for SynthPlugin<G, S> {
	fn default() -> Self {
		let param_names = G::Parameters::names().to_vec();
		let mut param_values = Vec::with_capacity(param_names.len());
		let mut param_map = HashMap::new();
		for s in &param_names {
			let value = G::Parameters::default_value(s);
			param_values.push(value);
			param_map.insert(*s, value);
		}

		let sample_rate = 44100.0;

		SynthPlugin {
			sample_rate: sample_rate,
			time: 0,
			notes: Vec::new(),
			events: VecDeque::new(),
			cache: (0..128).map(|tone| SoundCache::new(tone)).collect(),

			sound_params: G::Parameters::build(&param_map, sample_rate),
			param_names: param_names,
			param_values: param_values,
			param_map: param_map,

			global: G::Global::default(),

			phantom: PhantomData
		}
	}
}

impl<G: SoundGenerator, S: SynthInfo> Plugin for SynthPlugin<G, S> {
	fn get_info(&self) -> Info {
		Info {
			presets: 0,
			parameters: self.param_names.len() as i32,
			inputs: 0,
			outputs: 2,
			category: Category::Synth,
			f64_precision: false,

			.. S::get_info()
		}
	}

	fn can_do(&self, can_do: CanDo) -> Supported {
		match can_do {
			CanDo::ReceiveMidiEvent => Supported::Yes,
			CanDo::Offline          => Supported::Yes,
			_                       => Supported::No
		}
	}

	fn process_events(&mut self, events: Vec<Event>) {
		for e in events.iter() {
			match *e {
				Event::Midi { delta_frames, ref data, .. } => {
					self.events.push_back(MidiEvent {
						time: self.time + (delta_frames as usize),
						command: MidiCommand::fromData(data)
					});
				}
				_ => {}
			}
		}
	}

	fn process(&mut self, buffer: AudioBuffer<f32>) {
		let mut outputs = buffer.split().1;
		for i in 0..outputs[0].len() {
			while !self.events.is_empty() && self.events.front().unwrap().time == self.time {
				let event = self.events.pop_front().unwrap();
				self.handle_event(event);
			}
			let sample = self.produce_sample();
			outputs[0][i] = sample.left;
			outputs[1][i] = sample.right;
			self.time += 1;
		}
	}

	fn set_sample_rate(&mut self, rate: f32) {
		self.sample_rate = rate;
		self.build_sound_params();
	}

	fn get_parameter_name(&self, index: i32) -> String {
		self.param_names[index as usize].to_string()
	}

	fn get_parameter_text(&self, index: i32) -> String {
		self.sound_params.display(self.param_names[index as usize], &self.param_map).0
	}

	fn get_parameter_label(&self, index: i32) -> String {
		self.sound_params.display(self.param_names[index as usize], &self.param_map).1
	}

	fn get_parameter(&self, index: i32) -> f32 {
		self.param_values[index as usize]
	}

	fn set_parameter(&mut self, index: i32, value: f32) {
		let old_value = self.param_values[index as usize];
		self.param_values[index as usize] = value;

		let name = self.param_names[index as usize];
		self.param_map.insert(name, value);

		if value != old_value {
			self.build_sound_params();
		}
	}
}

impl<G: SoundGenerator, S: SynthInfo> SynthPlugin<G, S> {
	fn handle_event(&mut self, event: MidiEvent) {
		match event.command {
			MidiCommand::NoteOn { key, velocity, .. } => {
				let attack = G::Parameters::attack(&self.param_map, self.sample_rate);
				let release = G::Parameters::release(&self.param_map, self.sample_rate);
				let note = Note::new(key, velocity, attack, release);
				self.notes.push(note);
			},
			MidiCommand::NoteOff { key, velocity, .. } => {
				for note in &mut self.notes {
					if note.tone == key && !note.is_released() {
						note.release(velocity);
						break;
					}
				}
			},
			MidiCommand::AllNotesOff { velocity, .. } => {
				for note in &mut self.notes {
					if !note.is_released() {
						note.release(velocity);
					}
				}
			},
			MidiCommand::AllSoundOff { .. } => {
				self.notes.clear();
			},
			MidiCommand::Unknown => {}
		}
	}

	fn produce_sample(&mut self) -> Sample {
		let mut sample: Sample = Sample::from(0.0);
		for i in (0..self.notes.len()).rev() {
			if self.notes[i].is_alive() {
				sample += self.notes[i].produce_sample(&mut self.cache, &self.sound_params, &self.global);
			} else {
				self.notes.remove(i);
			}
		}
		sample
	}

	fn build_sound_params(&mut self) {
		let new_sound_params = G::Parameters::build(&self.param_map, self.sample_rate);
		if new_sound_params != self.sound_params {
			self.sound_params = new_sound_params;
			for mut c in &mut self.cache {
				c.invalidate();
			}
		}
	}

}
