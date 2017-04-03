
use std::ops::{Index, IndexMut};

use generate::{Sample, SoundGenerator};


const BLOCK_SHIFT: usize = 12;
const BLOCK_SIZE: usize = 1 << BLOCK_SHIFT;
const BLOCK_MASK: usize = BLOCK_SIZE - 1;

struct BlockVec<T> {
	v: Vec<Vec<T>>
}

impl<T> Index<usize> for BlockVec<T> {
	type Output = T;

	fn index(&self, index: usize) -> &T {
		&self.v[index >> BLOCK_SHIFT][index & BLOCK_MASK]
	}
}

impl<T: Default + Clone> IndexMut<usize> for BlockVec<T> {
	fn index_mut(&mut self, index: usize) -> &mut T {
		let block = index >> BLOCK_SHIFT;
		if self.v.len() <= block {
			self.v.resize(block + 1, Vec::new());
		}
		if self.v[block].is_empty() {
			self.v[block].resize(BLOCK_SIZE, T::default());
		}
		&mut self.v[block][index & BLOCK_MASK]
	}
}

impl<T> BlockVec<T> {
	pub fn new() -> BlockVec<T> {
		BlockVec {
			v: Vec::new()
		}
	}

	pub fn clear(&mut self) {
		self.v.clear();
	}
}


struct CachedGenerator<G: SoundGenerator> {
	generator: G,
	start_time: usize,
	end_time: usize
}

pub struct SoundCache<G: SoundGenerator> {
	generators: Vec<CachedGenerator<G>>,
	tone: u8,
	sound: BlockVec<G::Output>
}

impl<G: SoundGenerator> SoundCache<G> {
	pub fn new(tone: u8) -> SoundCache<G> {
		SoundCache {
			generators: Vec::new(),
			tone: tone,
			sound: BlockVec::new()
		}
	}

	pub fn invalidate(&mut self) {
		self.generators.clear();
		self.sound.clear();
	}

	pub fn get_sample(&mut self, time: usize, param: &G::Parameters, global: &G::Global) -> Sample {
		// Find generator
		let mut gi: usize = 0;
		while gi < self.generators.len() && self.generators[gi].end_time < time {
			gi += 1;
		}
		if gi == self.generators.len() || time < self.generators[gi].start_time {
			self.generators.insert(gi, CachedGenerator {
				generator: G::new(param, self.tone, time, global),
				start_time: time,
				end_time: time
			});
		}

		// Generate next sample, if needed
		if self.generators[gi].end_time == time {
			self.sound[time] = self.generators[gi].generator.produce_sample();
			self.generators[gi].end_time += 1;
			if self.generators.len() > gi + 1 && self.generators[gi + 1].start_time == self.generators[gi].end_time {
				// Merge generators
				self.generators[gi + 1].start_time = self.generators[gi].start_time;
				self.generators.remove(gi);
			}
		}

		// Return cached value
		self.sound[time].into()
	}
}

