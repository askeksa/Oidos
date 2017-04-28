
# Oidos release history

- 2017-04-28: **2.1.0**
  - Fixed some float constants in [`oidos.asm`](player/oidos.asm) so it
    assembles in an old `nasm`.
  - *SSE2* version of the additive core, so the synth works on CPUs without
    *AVX* support.
  - Changed library type to `cdylib` to avoid including unused **Rust** code.
  - VSTs available for **Windows**, **Linux** and **MacOS**.
  - **Windows** VSTs no longer depend on MSVC runtime DLLs.
  - Enhancements to converter text output, with colors if your terminal
    supports *ANSI escape codes*.

- 2017-04-10: **2.0.0**
  - First public release
