; Block of random data used by Oidos.
; Can also be useful as a 3D noise texture.

global _Oidos_FillRandomData
global _Oidos_RandomData
global ?ID3D11Texture2D_ID@@3U_GUID@@A

%define NOISESIZE 64

	section guid data align=4

; If you are using D3D11, you can re-use this GUID.
?ID3D11Texture2D_ID@@3U_GUID@@A:
	db 0xF2,0xAA,0x15,0x6F, 0x08,0xD2,0x89,0x4E, 0x9A,0xB4,0x48,0x95, 0x35,0xD3,0x4F,0x9C

	section randdata bss align=4

_Oidos_RandomData:
.align16
	resd	NOISESIZE*NOISESIZE*NOISESIZE

	section fillrand text align=1

_Oidos_FillRandomData:
	mov			eax, _Oidos_RandomData
.loop:
	mov			edx, ?ID3D11Texture2D_ID@@3U_GUID@@A

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
	cmp			eax, _Oidos_RandomData+NOISESIZE*NOISESIZE*NOISESIZE*4
	jb			.loop
	ret
