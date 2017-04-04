extern crate nasm_rs;

fn main() {
	nasm_rs::compile_library("additive.lib", &["src/additive.asm"]);
	println!("cargo:rustc-link-lib=static=additive");
}
