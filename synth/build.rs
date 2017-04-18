extern crate nasm_rs;

fn main() {
	#[cfg(not(target_env = "msvc"))]
	nasm_rs::compile_library("libadditive.a", &["src/additive.asm"]);

	#[cfg(target_env = "msvc")]
	nasm_rs::compile_library("additive.lib", &["src/additive.asm"]);

	println!("cargo:rustc-link-lib=static=additive");
}
