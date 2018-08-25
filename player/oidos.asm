; Oidos by Blueberry - https://github.com/askeksa/Oidos

; Offset applied by Oidos_GetPosition to compensate for graphics latency.
; Measured in samples (44100ths of a second).
; The default value of 2048 (corresponding to about 46 milliseconds) is
; appropriate for typical display latencies for high-framerate effects.
%define OIDOS_TIMER_OFFSET 2048

; Set to 0 if you don't care about Oidos_GenerateMusic preserving registers
%define OIDOS_SAVE_REGISTERS 1

%include "music.asm"


;; ********** Definitions **********

global _Oidos_GenerateMusic
global _Oidos_StartMusic
global _Oidos_GetPosition

global _Oidos_MusicBuffer
global _Oidos_TicksPerSecond
global _Oidos_MusicLength
global _Oidos_WavFileHeader


extern __imp__waveOutOpen@24
extern __imp__waveOutPrepareHeader@12
extern __imp__waveOutWrite@12
extern __imp__waveOutGetPosition@12


extern _Oidos_RandomData

%define SAMPLE_RATE 44100
%define BASE_FREQ 0.00232970791933 ; 440/((2^(1/12))^(9+12*4))/44100*(2*3.14159265358979)


;; ********** Public variables **********

section tps rdata align=4
_Oidos_TicksPerSecond:
	dd TICKS_PER_SECOND

section muslen rdata align=4
_Oidos_MusicLength:
	dd MUSIC_LENGTH

section MusBuf bss align=4
_Oidos_MusicBuffer:
.align24
	resw	TOTAL_SAMPLES*2

section WavFile rdata align=4
_Oidos_WavFileHeader:
	db	"RIFF"
	dd	36+TOTAL_SAMPLES*4
	db	"WAVE"
	db	"fmt "
	dd	16
	dw	1,2
	dd	SAMPLE_RATE
	dd	SAMPLE_RATE*4
	dw	4,16
	db	"data"
	dd	TOTAL_SAMPLES*4


;; ********** System structures **********

section	WaveForm rdata align=1
_WaveFormat:
	dw	1,2
	dd	SAMPLE_RATE
	dd	SAMPLE_RATE*4
	dw	4,16,0

section WaveHdr data align=4
_WaveHdr:
	dd	_Oidos_MusicBuffer
	dd	(TOTAL_SAMPLES*4)
	dd	0,0,0,0,0,0

section wavehand bss align=4
_WaveOutHandle:
.align16
	resd 1

section WaveTime data align=4
_WaveTime:
	dd	4,0,0,0,0,0,0,0


;; ********** Internal buffers **********

section freqarr bss align=16
PartialArray:
.align16:
	resq	10000*3*2

section sampbuf bss align=16
SampleBuffer:
.align24:
	reso	MAX_TOTAL_INSTRUMENT_SAMPLES

section mixbuf bss align=16
MixingBuffer:
.align24:
	reso	TOTAL_SAMPLES

%if NUM_TRACKS_WITH_REVERB > 0
section revbuf bss align=16
ReverbBuffer:
.align24:
	reso	TOTAL_SAMPLES

section delbuf bss align=8
DelayBuffer:
.align16:
	resq	25600
%endif

;; ********** Internal structures **********

struc params
	p_modes:		resd	1
	p_fat:			resd	1
	p_seed:			resd	1
	p_overtones:	resd	1
	p_decaydiff:	resd	1
	p_decaylow:		resd	1
	p_harmonicity:	resd	1
	p_sharpness:	resd	1
	p_width:		resd	1
	p_filterlow:	resd	1
	p_filterhigh:	resd	1
	p_fslopelow:	resd	1
	p_fslopehigh:	resd	1
	p_fsweeplow:	resd	1
	p_fsweephigh:	resd	1
	p_gain:			resd	1
	p_maxsamples:	resd	1
	p_release:		resd	1
	p_attack:		resd	1
	p_volume:		resd	1
%ifdef USES_PANNING
	p_panning:		resd	1
%endif


;; ********** Internal constants and tables **********

section base data align=16
baseptr:

c_oneone:		dq		1.0,1.0
c_twelve:		dd		12
c_randscale:	dd		0x30000000	; 2^-31
c_ampmax:		dd		32767.0
c_basefreq:		dd		BASE_FREQ

%if NUM_TRACKS_WITH_REVERB > 0
ReverbMaxDecay:
	dd	REVERB_MAX_DECAY
ReverbDecayMul:
	dd	REVERB_DECAY_MUL
ReverbParams:
	dd	REVERB_FILTER_HIGH, REVERB_FILTER_LOW, REVERB_DAMPEN_HIGH, REVERB_DAMPEN_LOW, REVERB_VOLUME_LEFT
%endif

ParamsPtr:		dd	_InstrumentParams
TonesPtr:		dd	_InstrumentTones
TovelPtr:		dd	_TrackData
LengthPtr:		dd	_NoteLengths
NotePtr:		dd	_NoteSamples
MixingPtr:		dd	0

%if NUM_TRACKS_WITH_REVERB > 0
ReverbState:
	dq	0.0,0.0,0.0,0.0
%endif

section offset rdata align=4
c_timeoffset:
	dd OIDOS_TIMER_OFFSET*4

section tempo rdata align=4
c_ticklength:
	dd SAMPLES_PER_TICK*4


;; ********** Register definitions **********

%define RANDOM ebx
%define PARAMS edx
%define ARRAY esi
%define SAMPLE edi
%define TONE esi
%define LENGTH esi
%define NOTE esi
%define MIXING edi
%define TOVEL ebx
%define SAMPLESRC esi

%define BASE ebp - baseptr


;; ********** Helper functions **********

%macro TONE2FREQ 0
	fidiv			dword [BASE + c_twelve]
	fld1
	fld				st1
	fprem
	f2xm1
	faddp			st1
	fscale
	fstp			st1
%endmacro

%macro FREQ2TONE 0
	fild			dword [BASE + c_twelve]
	fxch			st1
	fyl2x
%endmacro

%macro GETRANDOM 0
	fild			dword [RANDOM]
	add				RANDOM, byte 4
	fmul			dword [BASE + c_randscale]
%endmacro


;; ********** Instrument calculation **********

section makeinst text align=1
MakeInstrument:
	mov				PARAMS, [BASE + ParamsPtr]

	; tone

	mov				ARRAY, PartialArray
	mov				eax, [PARAMS]		; modes
.modeloop:
	push			PARAMS

	mov				RANDOM, [PARAMS]
	add				PARAMS, byte 4

	mov				ecx, [PARAMS]		; fat
	add				PARAMS, byte 4

	sub				RANDOM, eax
	shl				RANDOM, 8
	add				RANDOM, [PARAMS]	; seed
	add				PARAMS, byte 4
	shl				RANDOM, 2
	add				RANDOM, _Oidos_RandomData

	GETRANDOM							; subtone
	fabs
	fld				st0
	fimul			dword [PARAMS]		; overtones
	add				PARAMS, byte 4

	fxch			st1
	fmul			dword [PARAMS]		; decayhigh - decaylow
	add				PARAMS, byte 4
	fadd			dword [PARAMS]		; decaylow
	add				PARAMS, byte 4
%rep 12
	fsqrt
%endrep
	; ampmul, reltone, tone

	fxch			st1
	TONE2FREQ
	fld				st0
	frndint
	fsub			st1
	fmul			dword [PARAMS]		; harmonicity
	add				PARAMS, byte 4
	faddp			st1
	FREQ2TONE
	; reltone2, ampmul, tone

	fld				st0
	fmul			dword [PARAMS]		; sharpness
	add				PARAMS, byte 4
	TONE2FREQ
	GETRANDOM
	fmulp			st1
	; mamp, reltone2, ampmul, tone

.partialloop:
	push			PARAMS

	GETRANDOM
	fmul			dword [PARAMS]		; width
	add				PARAMS, byte 4
	fadd			st0, st2
	; ptone-tone, mamp, reltone2, ampmul, tone

	; Step value
	fld				st0
	fadd			st0, st5
	TONE2FREQ
	fmul			dword [BASE + c_basefreq]
	fsincos
	fmul			st0, st5
	fstp			qword [ARRAY]
	add				ARRAY, byte 8
	fmul			st0, st4
	fstp			qword [ARRAY]
	add				ARRAY, byte 8

	; State value
	fldpi
	GETRANDOM
	fmulp			st1
	fsincos
	fmul			st0, st3
	fstp			qword [ARRAY]
	add				ARRAY, byte 8
	fmul			st0, st2
	fstp			qword [ARRAY]
	add				ARRAY, byte 8

	; Filter value
	fld				st0
	fsub			dword [PARAMS]		; filterlow
	add				PARAMS, byte 8
	fmul			dword [PARAMS]		; fslopelow
	fld1
	faddp			st1
	fstp			qword [ARRAY]
	add				ARRAY, byte 8

	sub				PARAMS, byte 4

	fsub			dword [PARAMS]		; filterhigh
	add				PARAMS, byte 8
	fmul			dword [PARAMS]		; fslopehigh
	fld1
	faddp			st1
	fstp			qword [ARRAY]
	add				ARRAY, byte 8

	pop				PARAMS
	loop			.partialloop

	fstp			st0
	fstp			st0
	fstp			st0

	pop				PARAMS
	dec				eax
	jne				.modeloop

	fstp			st0


	; Gain helper values
	mov				RANDOM, [PARAMS]	; modes
	add				PARAMS, byte 4
	imul			RANDOM, [PARAMS]	; fat
	add				PARAMS, byte p_fslopelow-p_fat
	cvtsi2sd		xmm5, RANDOM

	cvtps2pd		xmm7, [PARAMS]		; fslopelow, fslopehigh
	add				PARAMS, byte 8

	cvtps2pd		xmm4, [PARAMS]		; fsweeplow, fsweephigh
	add				PARAMS, byte 8

	cvtss2sd		xmm6, [PARAMS]		; gain
	add				PARAMS, byte 4

	mulpd			xmm7, xmm4

	mov				eax, [PARAMS]		; maxsamples

.sample:
	xorpd			xmm4, xmm4

	mov				ARRAY, PartialArray
	mov				ecx, RANDOM			; npartials
.decay:
	movapd			xmm0, [ARRAY]		; [y1, x1]
	add				ARRAY, byte 16
	movapd			xmm1, [ARRAY]		; [y2, x2]
	pshufd			xmm3, xmm1, 0xEE	; [y2, y2]
	pshufd			xmm2, xmm1, 0x44	; [x2, x2]
	pshufd			xmm1, xmm0, 0x4E	; [x1, y1]
	mulpd			xmm0, xmm2			; [y1*x2, x1*x2]
	mulpd			xmm1, xmm3			; [x1*y2, y1*y2]
	addsubpd		xmm0, xmm1			; [y1*x2+x1*y2, x1*x2-y1*y2]

	movapd			[ARRAY], xmm0
	add				ARRAY, byte 16

	movapd			xmm1, [ARRAY]
	pshufd			xmm3, xmm1, 0xEE
	pshufd			xmm2, xmm1, 0x44
	minpd			xmm2, xmm3
	xorpd			xmm3, xmm3
	maxpd			xmm2, xmm3
	minpd			xmm2, [BASE + c_oneone]

	mulpd			xmm0, xmm2
	addpd			xmm4, xmm0

	addpd			xmm1, xmm7
	movapd			[ARRAY], xmm1
	add				ARRAY, byte 16
	loop			.decay

	; Gain
	movsd			xmm1, xmm6
	subsd			xmm1, [BASE + c_oneone]
	mulsd			xmm1, xmm4
	mulsd			xmm1, xmm4
	addsd			xmm1, xmm5
	divsd			xmm1, xmm6
	sqrtsd			xmm1, xmm1
	divsd			xmm4, xmm1

	unpcklpd		xmm4, xmm4
	movapd			[SAMPLE], xmm4
	add				SAMPLE, byte 16

	dec				eax
	jne				.sample

	ret


;; ********** Track mixing **********

	section makechan text align=1
MakeChannel:
	mov				SAMPLE, SampleBuffer
	push			byte 0
.tonesloop:
	mov				TONE, [BASE + TonesPtr]
	lodsb
	mov				[BASE + TonesPtr], TONE
	movsx			eax, al
	add				[esp], eax
	js				.tonesdone
	fild			dword [esp]
	call			MakeInstrument
	jmp				.tonesloop
.tonesdone:
	pop				eax

.column:
	mov				dword [BASE + MixingPtr], MixingBuffer

	; Delta decode tones
	mov				TOVEL, [BASE + TovelPtr]
	xor				eax, eax
.toveldelta:
	mov				cl, [TOVEL+eax+1]
	add				eax, byte 2
	add				[TOVEL+eax+1], cl
	jns				.toveldelta
	add				eax, byte 2
	add				[BASE + TovelPtr], eax

.notesloop:
	mov				MIXING, [BASE + MixingPtr]

	; Read note length
	xor				eax, eax
	mov				LENGTH, [BASE + LengthPtr]
	cmp				[LENGTH], al
	jge				.short
	lodsb
	not				al
	shl				eax, 8
.short:
	lodsb
	mov				[BASE + LengthPtr], LENGTH

	; Scale by tick duration
	imul			eax, SAMPLES_PER_TICK
	cvtsi2sd		xmm2, eax			; For release
	push			eax					; For termination test
	shl				eax, 4
	add				[BASE + MixingPtr], eax	; Position of next note

	; Read note index
	mov				NOTE, [BASE + NotePtr]
	lodsb
	mov				[BASE + NotePtr], NOTE
	movsx			eax, al
	dec				eax
	js near			.nextnote			; OFF

	; Note volume
	movzx			SAMPLESRC, byte [TOVEL+eax*2+2]
	cvtsi2sd		xmm0, SAMPLESRC

	; Get sample length
	mov				PARAMS, [BASE + ParamsPtr]
	add				PARAMS, byte p_maxsamples
	mov				ecx, [PARAMS]
	add				PARAMS, byte 4

	; Attack/release add
	cvtps2pd		xmm7, [PARAMS]		; release, attack
	add				PARAMS, byte 8

	; Instrument volume
	cvtss2sd		xmm5, [PARAMS]		; volume
	add				PARAMS, byte 4
	mulsd			xmm5, xmm0
	unpcklpd		xmm5, xmm5

%ifdef USES_PANNING
	; Instrument panning
	cvtss2sd		xmm4, [PARAMS]		; panning
	add				PARAMS, byte 4
	unpcklpd		xmm4, xmm4
	movapd			xmm1, [BASE + c_oneone]
	addsubpd		xmm1, xmm4
	mulpd			xmm5, xmm1
%endif

	; Find sample
	movzx			SAMPLESRC, byte [TOVEL+eax*2+1]
	imul			SAMPLESRC, ecx
	shl				SAMPLESRC, 4
	add				SAMPLESRC, SampleBuffer

	; Attack/release state
	mov				al, [TOVEL]
	test			eax, eax
	je				.until_next
	imul			eax, SAMPLES_PER_TICK
	cvtsi2sd		xmm2, eax			; Fixed note length
.until_next:
	mulsd			xmm2, xmm7
	movsd			xmm1, [BASE + c_oneone]
	subsd			xmm1, xmm2

	; XMM1 = Attack/release state
	; XMM5 = Volume
	; XMM7 = Attack/release add

.mixingloop:
	movapd			xmm0, [SAMPLESRC]
	add				SAMPLESRC, byte 16
	movapd			xmm4, [MIXING]

	mulpd			xmm0, xmm5			; Volume

	pshufd			xmm3, xmm1, 0xEE
	pshufd			xmm2, xmm1, 0x44
	minpd			xmm2, xmm3
	xorpd			xmm3, xmm3
	maxpd			xmm2, xmm3
	minpd			xmm2, [BASE + c_oneone]

	mulpd			xmm0, xmm2			; Attack and release
	addpd			xmm4, xmm0

	addpd			xmm1, xmm7

	movapd			[MIXING], xmm4
	add				MIXING, byte 16
	loop			.mixingloop

.nextnote:
	pop				eax
	dec				eax
	jns near		.notesloop

.notesdone:
	; More columns for instrument?
	mov				TONE, [BASE + TonesPtr]
	dec				byte [TONE-1]
	js				.column

	mov				[BASE + ParamsPtr], PARAMS
	ret


;; ********** Main **********

section synth text align=1
_Oidos_GenerateMusic:
%if OIDOS_SAVE_REGISTERS
	pusha
%endif
	fninit

	mov				ebp, baseptr

%if NUM_TRACKS_WITH_REVERB > 0
	push			byte NUM_TRACKS_WITH_REVERB
.loop1:
	call			MakeChannel
	dec				dword [esp]
	jne				.loop1
	pop				ebx

	fld				dword [BASE + ReverbMaxDecay]
	mov				esi, REVERB_NUM_DELAYS
	mov				ecx, REVERB_MAX_DELAY
.delayloop:
	; Is this delay length included?
	mov				eax, ecx
%if REVERB_MIN_DELAY != 0
	sub				eax, REVERB_MIN_DELAY
%endif
	mul				dword [_Oidos_RandomData + REVERB_RANDOMSEED*4 + ecx*4]
	cmp				edx, esi
	jae short		.skip

.feedbackloop:
	; Index into delay buffer
	xor				edx, edx
	mov				eax, ebx
	shr				eax, 1
	div				ecx
	lea				eax, [DelayBuffer + edx*8]

	lea				PARAMS, [BASE + ReverbParams]
	lea				edi, [BASE + ReverbState]

	; Filter input
	fld				qword [MixingBuffer + ebx*8]
	call			ReverbFilter

	; Filter echo
	fld				qword [eax]			; delayed value
	call			ReverbFilter

	; Extract delayed signal
	fld				qword [eax]			; delayed value
	fmul			dword [PARAMS]		; volume
	fadd			qword [ReverbBuffer + REVERB_ADD_DELAY*16 + ebx*8]
	fstp			qword [ReverbBuffer + REVERB_ADD_DELAY*16 + ebx*8]

	; Attenuate echo and add to input
	fmul			st0, st2			; feedback factor
	faddp			st1
	fstp			qword [eax]

	add				ebx, byte 2
	cmp				ebx, TOTAL_SAMPLES*2
	jb				.feedbackloop

%if REVERB_VOLUME_LEFT != REVERB_VOLUME_RIGHT
	; Alternate between left and right volume
	xor				dword [PARAMS], REVERB_VOLUME_LEFT ^ REVERB_VOLUME_RIGHT
%endif

	; Switch side
	and				ebx, byte 1
	xor				ebx, byte 1

	dec				esi
.skip:
	fmul			dword [BASE + ReverbDecayMul]
	loop			.delayloop
	fstp			st0
%endif

%if NUM_TRACKS_WITHOUT_REVERB > 0
	push			byte NUM_TRACKS_WITHOUT_REVERB
.loop2:
	call			MakeChannel
	dec				dword [esp]
	jne				.loop2
	pop				ebx
%endif

	; Clamp and convert to shorts
	fld				dword [BASE + c_ampmax]
.sloop:
	fld				qword [MixingBuffer + ebx*8]
%if NUM_TRACKS_WITH_REVERB > 0
	fadd			qword [ReverbBuffer + ebx*8]
%endif
	fcomi			st0, st1
	fcmovnb			st0, st1
	fchs
	fcomi			st0, st1
	fcmovnb			st0, st1
	fchs

	fistp			word [_Oidos_MusicBuffer + ebx*2]

	add				ebx, byte 1
	cmp				ebx, TOTAL_SAMPLES*2
	jb				.sloop
	fstp			st0

%if OIDOS_SAVE_REGISTERS
	popa
%endif
	ret

section rfilter text align=1
ReverbFilter:
%macro FILTER 0
	; Basic low-pass filter
	fsub			qword [edi]			; filter state
	fmul			dword [PARAMS]		; filter parameter
	add				PARAMS, byte 4
	fadd			qword [edi]

	; Avoid denormals
	fld1
	fadd			st1, st0
	fsubp			st1, st0

	fst				qword [edi]
	add				edi, byte 8
%endmacro

	; Difference between two low-pass filters
	fld				st0
	FILTER
	fxch			st1
	FILTER
	fsubp			st1
	ret


;; ********** Play **********

section startsnd text align=1
_Oidos_StartMusic:
	; Start music
	push	byte 0
	push	byte 0
	push	byte 0
	push	_WaveFormat
	push	byte -1
	push	_WaveOutHandle
	call	[__imp__waveOutOpen@24]

	push	byte 32					; sizeof(WAVEHDR)
	push	_WaveHdr
	push	dword [_WaveOutHandle]					; waveOutHandle
	call	[__imp__waveOutPrepareHeader@12]

	push	byte 32					; sizeof(WAVEHDR)
	push	_WaveHdr
	push	dword [_WaveOutHandle]
	call	[__imp__waveOutWrite@12]
	ret

section getpos text align=1
_Oidos_GetPosition:
	push	byte 32					; sizeof(MMTIME)
	push	_WaveTime
	push	dword [_WaveOutHandle]
	call	[__imp__waveOutGetPosition@12]

	fild	dword [_WaveTime+4]
%if OIDOS_TIMER_OFFSET>0
	fiadd	dword [c_timeoffset]
%endif
	fidiv	dword [c_ticklength]
	ret
