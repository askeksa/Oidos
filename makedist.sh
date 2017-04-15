#!/bin/bash

DIST=dist/Oidos
rm -rf dist/Oidos

# Build synth
cd synth
cargo build --release
cargo build --release --target=i686-pc-windows-msvc
cd ..

# Build reverb
cd reverb
cargo build --release
cargo build --release --target=i686-pc-windows-msvc
cd ..

# Compile converter to exe
cd convert
/c/Python27/python ./py2exe_setup.py
cd ..

# copy VSTs
mkdir -p $DIST/vst/Windows32
cp synth/target/i686-pc-windows-msvc/release/Oidos.dll $DIST/vst/Windows32/
cp reverb/target/i686-pc-windows-msvc/release/OidosReverb.dll $DIST/vst/Windows32/

mkdir -p $DIST/vst/Windows64
cp synth/target/release/Oidos.dll $DIST/vst/Windows64/
cp reverb/target/release/OidosReverb.dll $DIST/vst/Windows64/

# Copy converter
mkdir -p $DIST/convert
cp convert/OidosConvert.py $DIST/convert/
cp convert/XML.py $DIST/convert/
cp convert/dist/OidosConvert.exe $DIST/convert/

# Copy player source
mkdir -p $DIST/player
cp player/oidos.asm $DIST/player/
cp player/oidos.h $DIST/player/
cp player/oidos.inc $DIST/player/
cp player/play.asm $DIST/player/
cp player/random.asm $DIST/player/

# Copy examples
cp -R examples $DIST/

# Copy easy_exe
mkdir -p $DIST/easy_exe
cp easy_exe/build.bat $DIST/easy_exe/
cp easy_exe/*.txt $DIST/easy_exe/
cp examples/Songs/Punqtured-4k-Fntstc.xrns $DIST/easy_exe/music.xrns
mkdir -p $DIST/easy_exe/temp
cp -R easy_exe/tools $DIST/easy_exe/

# Copy readme and license
cp README.md $DIST/
cp LICENSE.md $DIST/
