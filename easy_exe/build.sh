#!/bin/sh

rm -f temp/*
rm -f dump_wav

../convert/OidosConvert.py -ansi music.xrns temp/music.asm

cp ../player/dump_wav.c temp/
cp ../player/oidos.asm temp/
cp ../player/oidos.h temp/
cp ../player/platform.inc temp/
cp ../player/random.asm temp/

cd temp
nasm -felf32 oidos.asm -o oidos.o
nasm -felf32 random.asm -o random.o
cc -m32 -c dump_wav.c -o dump_wav.o
cc -m32 oidos.o random.o dump_wav.o -o ../dump_wav
cd ..
