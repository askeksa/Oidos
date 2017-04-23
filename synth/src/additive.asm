
; Windows?
%ifidn __OUTPUT_FORMAT__, win32
%define WINDOWS (1)
%elifidn __OUTPUT_FORMAT__, win64
%define WINDOWS (1)
%else
%define WINDOWS (0)
%endif

; Registers
%if __BITS__ == 32
%define r(n) e%+n
%else
%define r(n) r%+n
default rel
%endif


; Export functions
global supports_avx
global _supports_avx
global additive_core_sse2
global _additive_core_sse2
global additive_core_avx
global _additive_core_avx


; Constants
section .rodata align=32
c_zero:		dq	0.0, 0.0, 0.0, 0.0
c_one:		dq	1.0, 1.0, 1.0, 1.0


; Register assignment
%define STATE_RE r(di)
%define STATE_IM r(si)
%define STEP_RE r(dx)
%define STEP_IM r(cx)
%define FILTER_LOW r(ax)
%define FILTER_HIGH r(bx)
%define COUNT r(bp)

; Argument to ENTRY and EXIT macros to specify encoding
%define LEGACY(i) i
%define VEX(i) v%+i

%macro ENTRY 1
	; Save general purpose registers
	push			r(bx)
	push			r(bp)
	push			r(si)
	push			r(di)

	; Get arguments
%if __BITS__ == 32
	mov				STATE_RE,    [esp + 5*4 + 0*4]
	mov				STATE_IM,    [esp + 5*4 + 1*4]
	mov				STEP_RE,     [esp + 5*4 + 2*4]
	mov				STEP_IM,     [esp + 5*4 + 3*4]
	mov				FILTER_LOW,  [esp + 5*4 + 4*4]
	mov				FILTER_HIGH, [esp + 5*4 + 5*4]

	%1(movsd)		xmm0,        [esp + 5*4 + 6*4 + 0*8]
	%1(movsd)		xmm1,        [esp + 5*4 + 6*4 + 1*8]

	mov				COUNT,       [esp + 5*4 + 6*4 + 2*8 + 0*4]
%elif WINDOWS
	mov				STATE_RE,    rcx
	mov				STATE_IM,    rdx
	mov				STEP_RE,     r8
	mov				STEP_IM,     r9
	mov				FILTER_LOW,  [rsp + 5*8 + 32 + 0*8]
	mov				FILTER_HIGH, [rsp + 5*8 + 32 + 1*8]

	%1(movsd)		xmm0,        [rsp + 5*8 + 32 + 2*8 + 0*8]
	%1(movsd)		xmm1,        [rsp + 5*8 + 32 + 2*8 + 1*8]

	mov				COUNT,       [rsp + 5*8 + 32 + 2*8 + 2*8 + 0*8]
%else
	mov				FILTER_LOW,  r8
	mov				FILTER_HIGH, r9

	mov				COUNT,       [rsp + 5*8 + 0*8]
%endif

%if WINDOWS && __BITS__ == 64
	; Save float registers
	sub				rsp, 2*16
	%1(movupd)		[rsp + 0*16], xmm6
	%1(movupd)		[rsp + 1*16], xmm7
%endif

	; Disable denormals
	sub				r(sp), 4
	%1(stmxcsr)		[r(sp)]
	or				dword [r(sp)], 0x8040
	%1(ldmxcsr)		[r(sp)]
	add				r(sp), 4
%endmacro

%macro EXIT 1
%if WINDOWS && __BITS__ == 64
	; Restore float registers
	%1(movupd)		xmm6, [rsp + 0*16]
	%1(movupd)		xmm7, [rsp + 1*16]
	add				rsp, 2*16
%endif

%if __BITS__ == 32
	; Return result on FP stack
	sub				esp, 8
	%1(movsd)		[esp], xmm0
	fld				qword [esp]
	add				esp, 8
%endif

	; Restore general purpose registers
	pop			r(di)
	pop			r(si)
	pop			r(bp)
	pop			r(bx)
%endmacro


; Supports AVX?
section .text
supports_avx:
_supports_avx:
	push			r(bx)

	mov				eax, 1
	cpuid

	mov				r(ax), r(cx)
	shr				r(ax), 28
	and				r(ax), 1

	pop				r(bx)
	ret


; SSE2 core
section .text
additive_core_sse2:
_additive_core_sse2:
	ENTRY LEGACY

	; Initialize
	movsd			xmm6, xmm0
	unpcklpd		xmm6, xmm6
	movsd			xmm7, xmm1
	unpcklpd		xmm7, xmm7
	xorpd			xmm0, xmm0

.loop:
	; Update oscillator
	movupd			xmm2, [STATE_RE]
	movupd			xmm3, [STATE_IM]
	movapd			xmm4, xmm2
	movapd			xmm5, xmm3
	movupd			xmm1, [STEP_RE]
	mulpd			xmm2, xmm1
	mulpd			xmm3, xmm1
	movupd			xmm1, [STEP_IM]
	mulpd			xmm4, xmm1
	mulpd			xmm5, xmm1
	subpd			xmm2, xmm5
	addpd			xmm3, xmm4
	movupd			[STATE_RE], xmm2
	movupd			[STATE_IM], xmm3

	; Update filter
	movupd			xmm4, [FILTER_LOW]
	movupd			xmm5, [FILTER_HIGH]
	movapd			xmm3, xmm4
	minpd			xmm3, xmm5
	addpd			xmm4, xmm6
	addpd			xmm5, xmm7
	movupd			[FILTER_LOW], xmm4
	movupd			[FILTER_HIGH], xmm5
	maxpd			xmm3, [c_zero]
	minpd			xmm3, [c_one]

	; Accumulate filtered oscillator
	mulpd			xmm2, xmm3
	addpd			xmm0, xmm2

	; Advance pointers
	add				STATE_RE, 16
	add				STATE_IM, 16
	add				STEP_RE, 16
	add				STEP_IM, 16
	add				FILTER_LOW, 16
	add				FILTER_HIGH, 16

	sub				COUNT, 2
	ja				.loop

	; Final summation
	movapd			xmm1, xmm0
	unpckhpd		xmm1, xmm1
	addsd			xmm0, xmm1

	EXIT LEGACY
	ret


; AVX core
section .text
additive_core_avx:
_additive_core_avx:
	ENTRY VEX

	; Initialize
	vunpcklpd		xmm6, xmm0, xmm0
	vinsertf128		ymm6, ymm6, xmm6, 1
	vunpcklpd		xmm7, xmm1, xmm1
	vinsertf128		ymm7, ymm7, xmm7, 1
	vxorpd			ymm0, ymm0

.loop:
	; Update oscillator
	vmovupd			ymm2, [STATE_RE]
	vmovupd			ymm3, [STATE_IM]
	vmulpd			ymm4, ymm2, [STEP_RE]
	vmulpd			ymm5, ymm2, [STEP_IM]
	vmulpd			ymm2, ymm3, [STEP_IM]
	vmulpd			ymm3, ymm3, [STEP_RE]
	vsubpd			ymm2, ymm4, ymm2
	vaddpd			ymm3, ymm3, ymm5
	vmovupd			[STATE_RE], ymm2
	vmovupd			[STATE_IM], ymm3

	; Update filter
	vmovupd			ymm4, [FILTER_LOW]
	vmovupd			ymm5, [FILTER_HIGH]
	vminpd			ymm3, ymm4, ymm5
	vaddpd			ymm4, ymm4, ymm6
	vaddpd			ymm5, ymm5, ymm7
	vmovupd			[FILTER_LOW], ymm4
	vmovupd			[FILTER_HIGH], ymm5
	vmaxpd			ymm3, ymm3, [c_zero]
	vminpd			ymm3, ymm3, [c_one]

	; Accumulate filtered oscillator
	vmulpd			ymm2, ymm2, ymm3
	vaddpd			ymm0, ymm0, ymm2

	; Advance pointers
	add				STATE_RE, 32
	add				STATE_IM, 32
	add				STEP_RE, 32
	add				STEP_IM, 32
	add				FILTER_LOW, 32
	add				FILTER_HIGH, 32

	sub				COUNT, 4
	ja				.loop

	; Final summation
	vextractf128	xmm1, ymm0, 1
	vaddpd			xmm0, xmm0, xmm1
	vhaddpd			xmm0, xmm0, xmm0

	EXIT VEX
	vzeroupper
	ret

