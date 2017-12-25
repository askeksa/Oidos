
use std::collections::{HashMap, VecDeque};
use std::marker::PhantomData;
use std::sync::RwLock;

use vst2::api::{Events, Supported};
use vst2::buffer::AudioBuffer;
use vst2::event::{Event, MidiEvent};
use vst2::host::Host;
use vst2::plugin::{CanDo, Category, HostCallback, Info, Plugin};

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

pub struct TimedMidiCommand {
	time: usize,
	command: MidiCommand,
}

struct Note {
	time: usize,
	dead_time: usize,
	max_dead_time: Option<usize>,
	tone: u8,
	velocity: u8,
	attack: f32,
	release: f32,

	release_time: Option<usize>
}

impl Note {
	fn new(tone: u8, velocity: u8, attack: f32, release: f32, max_dead_time: Option<usize>) -> Note {
		Note {
			time: 0,
			dead_time: 0,
			max_dead_time: max_dead_time,
			tone: tone,
			velocity: velocity,
			attack: attack,
			release: release,

			release_time: None
		}
	}

	fn produce_sample<G: SoundGenerator>(&mut self, cache: &mut Vec<SoundCache<G>>, param: &G::Parameters, global: &G::Global) -> Sample {
		let wave = cache[self.tone as usize].get_sample(self.time, param, global);
		let amp = self.attack_amp().min(self.release_amp()) * (self.velocity as f32 / 127.0);
		let sample = wave * amp;
		self.time += 1;

		if sample.left.abs() < 0.001 && sample.right.abs() < 0.001 {
			self.dead_time += 1;
		} else {
			self.dead_time = 0;
		}

		sample
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

	fn is_released(&self) -> bool {
		self.release_time.is_some()
	}

	fn is_alive(&self) -> bool {
		if let Some(max_dead_time) = self.max_dead_time {
			if self.dead_time > max_dead_time {
				return false;
			}
		}
		self.release_amp() > 0.0
	}
}


pub trait SynthInfo {
	fn get_info() -> Info;
}

pub struct SynthPlugin<G: SoundGenerator, S: SynthInfo> {
	host: Option<HostCallback>,

	sample_rate: f32,
	time: usize,
	notes: Vec<Note>,
	events: VecDeque<TimedMidiCommand>,
	cache: RwLock<Vec<SoundCache<G>>>,

	sound_params: G::Parameters,
	param_names: Vec<&'static str>,
	param_values: Vec<f32>,
	param_map: RwLock<HashMap<&'static str, f32>>,

	global: G::Global,

	phantom: PhantomData<S>
}

fn make_param_map(param_names: &[&'static str], param_values: &[f32]) -> HashMap<&'static str, f32> {
	let mut param_map = HashMap::new();
	for (s, v) in param_names.iter().zip(param_values) {
		param_map.insert(*s, *v);
	}
	param_map
}

impl<G: SoundGenerator, S: SynthInfo> Default for SynthPlugin<G, S> {
	fn default() -> Self {
		let param_names = G::Parameters::names().to_vec();
		let param_values: Vec<f32> = param_names.iter().map(|s| G::Parameters::default_value(s)).collect();
		let param_map = make_param_map(&param_names, &param_values);

		let cache = (0..128).map(|tone| SoundCache::new(tone)).collect();

		let sample_rate = 44100.0;

		SynthPlugin {
			host: None,

			sample_rate: sample_rate,
			time: 0,
			notes: Vec::new(),
			events: VecDeque::new(),
			cache: RwLock::new(cache),

			sound_params: G::Parameters::build(&param_map, sample_rate),
			param_names: param_names,
			param_values: param_values,
			param_map: RwLock::new(param_map),

			global: G::Global::default(),

			phantom: PhantomData
		}
	}
}

impl<G: SoundGenerator, S: SynthInfo> Plugin for SynthPlugin<G, S> {
	fn new(host: HostCallback) -> SynthPlugin<G, S> {
		SynthPlugin {
			host: Some(host),

			.. SynthPlugin::default()
		}
	}

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
			_                       => Supported::No
		}
	}

	fn process_events(&mut self, events: &Events) {
		for e in events.events() {
			match e {
				Event::Midi(MidiEvent { delta_frames, ref data, .. }) => {
					self.events.push_back(TimedMidiCommand {
						time: self.time + (delta_frames as usize),
						command: MidiCommand::fromData(data)
					});
				}
				_ => {}
			}
		}
	}

	fn process(&mut self, buffer: &mut AudioBuffer<f32>) {
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
		let param_map: &HashMap<&'static str, f32> = &self.param_map.read().unwrap();
		self.sound_params.display(self.param_names[index as usize], param_map).0
	}

	fn get_parameter_label(&self, index: i32) -> String {
		let param_map: &HashMap<&'static str, f32> = &self.param_map.read().unwrap();
		self.sound_params.display(self.param_names[index as usize], param_map).1
	}

	fn get_parameter(&self, index: i32) -> f32 {
		self.param_values[index as usize]
	}

	fn set_parameter(&mut self, index: i32, value: f32) {
		self.param_values[index as usize] = value;

		if let Some(ref mut host) = self.host {
			for name in G::Parameters::influence(self.param_names[index as usize]) {
				if let Some(p) = self.param_names.iter().position(|n| *n == name) {
					self.param_values[p] = infinitesimal_change(self.param_values[p]).min(1.0);
					host.automate(p as i32, self.param_values[p]);
				}
			}
		}

		self.build_sound_params();
	}
}

impl<G: SoundGenerator, S: SynthInfo> SynthPlugin<G, S> {
	fn handle_event(&mut self, event: TimedMidiCommand) {
		let param_map: &HashMap<&'static str, f32> = &self.param_map.read().unwrap();
		match event.command {
			MidiCommand::NoteOn { key, velocity, .. } => {
				let attack = G::Parameters::attack(param_map, self.sample_rate);
				let release = G::Parameters::release(param_map, self.sample_rate);
				let note = Note::new(key, velocity, attack, release, Some(self.sample_rate as usize));
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
		let cache: &mut Vec<SoundCache<G>> = &mut self.cache.write().unwrap();
		let mut sample: Sample = Sample::from(0.0);
		for i in (0..self.notes.len()).rev() {
			if self.notes[i].is_alive() {
				sample += self.notes[i].produce_sample(cache, &self.sound_params, &self.global);
			} else {
				self.notes.remove(i);
			}
		}
		sample
	}

	fn build_sound_params(&mut self) {
		let param_map: &mut HashMap<&'static str, f32> = &mut self.param_map.write().unwrap();
		*param_map = make_param_map(&self.param_names, &self.param_values);
		let new_sound_params = G::Parameters::build(param_map, self.sample_rate);
		if new_sound_params != self.sound_params {
			let cache: &mut Vec<SoundCache<G>> = &mut self.cache.write().unwrap();
			self.sound_params = new_sound_params;
			for c in cache {
				c.invalidate();
			}
		}
	}
}

fn infinitesimal_change(value: f32) -> f32 {
	let mut bits = value.to_bits();
	bits += 1;
	f32::from_bits(bits)
}
