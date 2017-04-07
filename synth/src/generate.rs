
use std::ops::{Add, AddAssign, Index, Mul, MulAssign};

#[derive(Clone, Copy)]
pub struct Sample {
	pub left: f32,
	pub right: f32
}

impl Add<Sample> for Sample {
	type Output = Sample;

	fn add(self, other: Sample) -> Sample {
		Sample {
			left: self.left + other.left,
			right: self.right + other.right
		}
	}
}

impl AddAssign<Sample> for Sample {
	fn add_assign(&mut self, other: Sample) {
		self.left += other.left;
		self.right += other.right;
	}
}

impl Mul<f32> for Sample {
	type Output = Sample;

	fn mul(self, scale: f32) -> Sample {
		Sample {
			left: self.left * scale,
			right: self.right * scale
		}
	}
}

impl MulAssign<f32> for Sample {
	fn mul_assign(&mut self, scale: f32) {
		self.left *= scale;
		self.right *= scale;
	}
}

impl From<f32> for Sample {
	fn from(s: f32) -> Sample {
		Sample {
			left: s,
			right: s
		}
	}
}

pub trait SoundParameters {
	fn names() -> &'static [&'static str];
	fn default_value(name: &str) -> f32;
	fn influence(name: &'static str) -> Vec<&'static str>;
	fn display<P: Index<&'static str, Output = f32>>(&self, name: &'static str, p: &P, sample_rate: f32) -> (String, String);
	fn build<P: Index<&'static str, Output = f32>>(p: &P, sample_rate: f32) -> Self;
	fn attack<P: Index<&'static str, Output = f32>>(p: &P, sample_rate: f32) -> f32;
	fn release<P: Index<&'static str, Output = f32>>(p: &P, sample_rate: f32) -> f32;
}

pub trait SoundGenerator {
	type Parameters: PartialEq + SoundParameters;
	type Output: Default + Copy + Into<Sample>;
	type Global: Default;

	fn new(param: &Self::Parameters, tone: u8, time: usize, global: &Self::Global) -> Self;
	fn produce_sample(&mut self) -> Self::Output;
}
