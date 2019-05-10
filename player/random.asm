; Block of random data used by Oidos.
; Can also be useful as a 3D noise texture.

%include "platform.inc"

global PUBLIC_FN(Oidos_FillRandomData)
global PUBLIC_FN(Oidos_RandomData)
global ID3D11Texture2D_ID

%define NOISESIZE 64

SECT_DATA(d3dtex) align=4

; If you are using D3D11, you can re-use this GUID.
; It's used as a rng seed, so this can't simply be thrown out on Linux -pcy
ID3D11Texture2D_ID:
	db 0xF2,0xAA,0x15,0x6F, 0x08,0xD2,0x89,0x4E, 0x9A,0xB4,0x48,0x95, 0x35,0xD3,0x4F,0x9C

SECT_BSS(randomdat) align=4

PUBLIC_FN(Oidos_RandomData):
	resd	NOISESIZE*NOISESIZE*NOISESIZE

SECT_TEXT(fillrandom) align=1

PUBLIC_FN(Oidos_FillRandomData):
	mov			eax, PUBLIC_FN(Oidos_RandomData)
.loop:
	mov			edx, ID3D11Texture2D_ID

	mov			ecx, [edx]
	ror			ecx, cl
	add			ecx, [edx+4]
	mov			[edx], ecx
	xor			[eax], ecx

	add			edx, byte 4

	mov			ecx, [edx]
	ror			ecx, cl
	add			ecx, [edx+4]
	mov			[edx], ecx
	xor			[eax], ecx

	add			edx, byte 4

	mov			ecx, [edx]
	ror			ecx, cl
	add			ecx, [edx+4]
	mov			[edx], ecx
	xor			[eax], ecx

	add			eax, byte 4
	cmp			eax, PUBLIC_FN(Oidos_RandomData)+NOISESIZE*NOISESIZE*NOISESIZE*4
	jb			.loop
	ret
