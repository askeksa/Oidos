
use std::io::{stdout, Write};
use std::thread::sleep;
use std::time::Duration;

#[link(name = "oidos")]
extern "C" {
	fn Oidos_FillRandomData();
	fn Oidos_GenerateMusic();
	fn Oidos_StartMusic();
	fn Oidos_GetPosition() -> f32;
	static Oidos_TicksPerSecond: f32;
	static Oidos_MusicLength: u32;
}

fn main() {
    println!("Calculating music...");
	unsafe {
		Oidos_FillRandomData();
		Oidos_GenerateMusic();
		Oidos_StartMusic();
	}
    println!();
	let length = unsafe { Oidos_MusicLength as f32 / Oidos_TicksPerSecond } as u32;
	loop {
		let time = unsafe { Oidos_GetPosition() / Oidos_TicksPerSecond };
		let seconds = time.floor() as u32;
		if seconds > length { break; }
		print!("\rPlaying {}:{:02} / {}:{:02}",
			seconds / 60, seconds % 60, length / 60, length % 60);
		stdout().flush().ok();
		sleep(Duration::from_millis(100));
	}
    println!();
}
