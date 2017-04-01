
use std::ops::Index;

use generate::{Sample, SoundGenerator};


const BLOCK_SHIFT: usize = 16;
const BLOCK_SIZE: usize = 1 << BLOCK_SHIFT;
const BLOCK_MASK: usize = BLOCK_SIZE - 1;

struct BlockVec<T> {
	size: usize,
	v: Vec<Vec<T>>
}

impl<T> Index<usize> for BlockVec<T> {
	type Output = T;

	fn index(&self, index: usize) -> &T {
		&self.v[index >> BLOCK_SHIFT][index & BLOCK_MASK]
	}
}

impl<T> BlockVec<T> {
	pub fn new() -> BlockVec<T> {
		BlockVec {
			size: 0,
			v: Vec::new()
		}
	}

	pub fn push(&mut self, value: T) {
		let i1: usize = self.size >> BLOCK_SHIFT;
		if i1 == self.v.len() {
			self.v.push(Vec::with_capacity(BLOCK_SIZE));
		}
		assert!(self.v[i1].len() == (self.size & BLOCK_MASK));
		self.v[i1].push(value);
		self.size += 1
	}

	pub fn len(&self) -> usize {
		self.size
	}

	pub fn clear(&mut self) {
		self.v.clear();
		self.size = 0;
	}
}


pub struct SoundCache<G: SoundGenerator> {
	generator: Option<Box<G>>,
	tone: u8,
	start_time: usize,
	sound: BlockVec<G::Output>
}

impl<G: SoundGenerator> SoundCache<G> {
	pub fn new(tone: u8) -> SoundCache<G> {
		SoundCache {
			generator: None,
			tone: tone,
			start_time: 0,
			sound: BlockVec::new()
		}
	}

	pub fn invalidate(&mut self) {
		self.generator = None;
		self.sound.clear();
	}

	pub fn get_sample(&mut self, time: usize, param: &G::Parameters, global: &G::Global) -> Sample {
		let end_time = self.start_time + self.sound.len();

		if self.generator.is_some() && time >= self.start_time && time < end_time {
			// Cached
			return self.sound[time - self.start_time].into();
		}

		if self.generator.is_none() || time != end_time {
			// Re-initialize generator
			self.generator = Some(Box::new(G::new(param, self.tone, time, global)));
			self.start_time = time;
			self.sound.clear();
		}

		// Next in sequence
		let sample = self.generator.as_mut().unwrap().produce_sample();
		self.sound.push(sample);
		sample.into()
	}
}

