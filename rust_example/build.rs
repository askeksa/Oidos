extern crate nasm_rs;

fn main() {
	let mut build = nasm_rs::Build::new();
	build.file("../player/oidos.asm");
	build.file("../player/random.asm");
	build.include("../player");

	#[cfg(not(target_env = "msvc"))]
	build.compile("liboidos.a");

	#[cfg(target_env = "msvc")]
	build.compile("oidos.lib");

	println!("cargo:rustc-link-lib=static=oidos");
	println!("cargo:rustc-link-lib=dylib=winmm");
}
