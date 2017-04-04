
%if __BITS__ == 32
%define NAME _additive_core
%define r(n) e%+n
%define PSIZE 4
%define STACK_OFFSET (4*4 + 4)
%else
%define NAME additive_core
%define r(n) r%+n
%define PSIZE 8
%define STACK_OFFSET (4*8 + 2*16 + 8)
%endif

global NAME

section sec text align=1
NAME:
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
	mov				eax, 1
	vcvtsi2sd		xmm1, eax
	vbroadcastsd	ymm1, xmm1
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
	add				r(cx), 3
	shr				r(cx), 2

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
	vxorpd			ymm4, ymm4
	vminpd			ymm3, ymm3, ymm1
	vmaxpd			ymm3, ymm3, ymm4

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

	loop			.loop

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

