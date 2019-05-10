#!/bin/sh

../convert/oidosconvert.py music.xrns music.asm && \
    nasm -felf32 -I ../player/ ../player/oidos.asm -o oidos.o && \
    nasm -felf32 -I ../player/ ../player/random.asm -o random.o && \
    cc -m32 ../player/play.c -o play.o && \
    cc -m32 -o dump_wav oidos.o random.o play.o && \
    rm -fv oidos.o random.o play.o music.asm

