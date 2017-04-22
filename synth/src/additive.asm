
; Windows?
%ifidn __OUTPUT_FORMAT__, win32
%define WINDOWS (1)
%elifidn __OUTPUT_FORMAT__, win64
%define WINDOWS (1)
%else
%define WINDOWS (0)
%endif

; Name mangling
%if __BITS__ == 32 && WINDOWS
%define NAME(n) _%+n
%else
%define NAME(n) n
%endif

; Registers and stack layout
%if __BITS__ == 32
%define r(n) e%+n
%define PSIZE 4
%define STACK_OFFSET (4*4 + 4)
%else
%define r(n) r%+n
%define PSIZE 8
%define STACK_OFFSET (4*8 + 2*16 + 8)
default rel
%endif


; Export functions
global NAME(supports_avx)
global NAME(additive_core_sse2)
global NAME(additive_core_avx)


; Constants
section .rdata align=16
c_zero:		dq	0.0, 0.0, 0.0, 0.0
c_one:		dq	1.0, 1.0, 1.0, 1.0


section .text
NAME(supports_avx):
	push			r(bx)

	mov				eax, 1
	cpuid

	mov				r(ax), r(cx)
	shr				r(ax), 28
	and				r(ax), 1

	pop				r(bx)
	ret


section .text
NAME(additive_core_sse2):
	; Disable denormals
	push			r(ax)
	stmxcsr			[r(sp)]
	or				dword [r(sp)], 0x8040
	ldmxcsr			[r(sp)]
	pop				r(ax)

%if __BITS__ == 64
	; Save register arguments to stack
	mov				[rsp + 8], rcx
	mov				[rsp + 16], rdx
	mov				[rsp + 24], r8
	mov				[rsp + 32], r9

	; Save callee-save registers
	sub				rsp, 2*16
	movupd			[rsp + 0*16], xmm6
	movupd			[rsp + 1*16], xmm7
%endif
	push			r(bx)
	push			r(bp)
	push			r(si)
	push			r(di)

	; Initialize
	xorpd			xmm0, xmm0
	movsd			xmm6, [r(sp) + STACK_OFFSET + 6*PSIZE + 0*8]
	unpcklpd		xmm6, xmm6
	movsd			xmm7, [r(sp) + STACK_OFFSET + 6*PSIZE + 1*8]
	unpcklpd		xmm7, xmm7

	; Pointers
	mov				r(ax), [r(sp) + STACK_OFFSET + 0*PSIZE]	; state_re
	mov				r(dx), [r(sp) + STACK_OFFSET + 1*PSIZE]	; state_im
	mov				r(bx), [r(sp) + STACK_OFFSET + 2*PSIZE]	; step_re
	mov				r(bp), [r(sp) + STACK_OFFSET + 3*PSIZE]	; step_im
	mov				r(si), [r(sp) + STACK_OFFSET + 4*PSIZE]	; filter_low
	mov				r(di), [r(sp) + STACK_OFFSET + 5*PSIZE]	; filter_high

	; Count
	mov				r(cx), [r(sp) + STACK_OFFSET + 6*PSIZE + 2*8]

.loop:
	; Update oscillator
	movupd			xmm2, [r(ax)]
	movupd			xmm3, [r(dx)]
	movapd			xmm4, xmm2
	movapd			xmm5, xmm3
	movupd			xmm1, [r(bx)]
	mulpd			xmm2, xmm1
	mulpd			xmm3, xmm1
	movupd			xmm1, [r(bp)]
	mulpd			xmm4, xmm1
	mulpd			xmm5, xmm1
	subpd			xmm2, xmm5
	addpd			xmm3, xmm4
	movupd			[r(ax)], xmm2
	movupd			[r(dx)], xmm3

	; Update filter
	movupd			xmm4, [r(si)]
	movupd			xmm5, [r(di)]
	movapd			xmm3, xmm4
	minpd			xmm3, xmm5
	addpd			xmm4, xmm6
	addpd			xmm5, xmm7
	movupd			[r(si)], xmm4
	movupd			[r(di)], xmm5
	maxpd			xmm3, [c_zero]
	minpd			xmm3, [c_one]

	; Accumulate filtered oscillator
	mulpd			xmm2, xmm3
	addpd			xmm0, xmm2

	; Advance pointers
	add				r(ax), 16
	add				r(dx), 16
	add				r(bx), 16
	add				r(bp), 16
	add				r(si), 16
	add				r(di), 16

	sub				r(cx), 2
	ja				.loop

	; Final summation
	movapd			xmm1, xmm0
	unpckhpd		xmm1, xmm1
	addsd			xmm0, xmm1

	; Restore callee-save registers
	pop			r(di)
	pop			r(si)
	pop			r(bp)
	pop			r(bx)
%if __BITS__ == 64
	movupd			xmm6, [rsp + 0*16]
	movupd			xmm7, [rsp + 1*16]
	add				rsp, 2*16
%else

	; Return result on FP stack
	sub				esp, 8
	movsd			[esp], xmm0
	fld				qword [esp]
	add				esp, 8
%endif

	ret


section .text
NAME(additive_core_avx):
	; Disable denormals
	push			r(ax)
	vstmxcsr		[r(sp)]
	or				dword [r(sp)], 0x8040
	vldmxcsr		[r(sp)]
	pop				r(ax)

%if __BITS__ == 64
	; Save register arguments to stack
	mov				[rsp + 8], rcx
	mov				[rsp + 16], rdx
	mov				[rsp + 24], r8
	mov				[rsp + 32], r9

	; Save callee-save registers
	sub				rsp, 2*16
	vmovupd			[rsp + 0*16], xmm6
	vmovupd			[rsp + 1*16], xmm7
%endif
	push			r(bx)
	push			r(bp)
	push			r(si)
	push			r(di)

	; Initialize
	vxorpd			ymm0, ymm0
	vbroadcastsd	ymm6, [r(sp) + STACK_OFFSET + 6*PSIZE + 0*8]
	vbroadcastsd	ymm7, [r(sp) + STACK_OFFSET + 6*PSIZE + 1*8]

	; Pointers
	mov				r(ax), [r(sp) + STACK_OFFSET + 0*PSIZE]	; state_re
	mov				r(dx), [r(sp) + STACK_OFFSET + 1*PSIZE]	; state_im
	mov				r(bx), [r(sp) + STACK_OFFSET + 2*PSIZE]	; step_re
	mov				r(bp), [r(sp) + STACK_OFFSET + 3*PSIZE]	; step_im
	mov				r(si), [r(sp) + STACK_OFFSET + 4*PSIZE]	; filter_low
	mov				r(di), [r(sp) + STACK_OFFSET + 5*PSIZE]	; filter_high

	; Count
	mov				r(cx), [r(sp) + STACK_OFFSET + 6*PSIZE + 2*8]

.loop:
	; Update oscillator
	vmovupd			ymm2, [r(ax)]
	vmovupd			ymm3, [r(dx)]
	vmulpd			ymm4, ymm2, [r(bx)]
	vmulpd			ymm5, ymm2, [r(bp)]
	vmulpd			ymm2, ymm3, [r(bp)]
	vmulpd			ymm3, ymm3, [r(bx)]
	vsubpd			ymm2, ymm4, ymm2
	vaddpd			ymm3, ymm3, ymm5
	vmovupd			[r(ax)], ymm2
	vmovupd			[r(dx)], ymm3

	; Update filter
	vmovupd			ymm4, [r(si)]
	vmovupd			ymm5, [r(di)]
	vminpd			ymm3, ymm4, ymm5
	vaddpd			ymm4, ymm4, ymm6
	vaddpd			ymm5, ymm5, ymm7
	vmovupd			[r(si)], ymm4
	vmovupd			[r(di)], ymm5
	vmaxpd			ymm3, ymm3, [c_zero]
	vminpd			ymm3, ymm3, [c_one]

	; Accumulate filtered oscillator
	vmulpd			ymm2, ymm2, ymm3
	vaddpd			ymm0, ymm0, ymm2

	; Advance pointers
	add				r(ax), 32
	add				r(dx), 32
	add				r(bx), 32
	add				r(bp), 32
	add				r(si), 32
	add				r(di), 32

	sub				r(cx), 4
	ja				.loop

	; Final summation
	vextractf128	xmm1, ymm0, 1
	vaddpd			xmm0, xmm0, xmm1
	vhaddpd			xmm0, xmm0, xmm0

	; Restore callee-save registers
	pop			r(di)
	pop			r(si)
	pop			r(bp)
	pop			r(bx)
%if __BITS__ == 64
	vmovupd			xmm6, [rsp + 0*16]
	vmovupd			xmm7, [rsp + 1*16]
	add				rsp, 2*16
%else

	; Return result on FP stack
	sub				esp, 8
	vmovsd			[esp], xmm0
	fld				qword [esp]
	add				esp, 8
%endif

	ret

