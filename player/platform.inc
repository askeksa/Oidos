
%ifidn __OUTPUT_FORMAT__, win32
%define WIN32
%define PUBLIC_SYM(n) _ %+ n
%define SECTION_BSS(n)   section n bss
%define SECTION_DATA(n)  section n data
%define SECTION_RDATA(n) section n rdata
%define SECTION_TEXT(n)  section n code
%else
%define PUBLIC_SYM(n) n
%define SECTION_BSS(n)   section    .bss.oidos. %+ n   nobits alloc noexec   write
%define SECTION_DATA(n)  section   .data.oidos. %+ n progbits alloc noexec   write
%define SECTION_RDATA(n) section .rodata.oidos. %+ n progbits alloc noexec nowrite
%define SECTION_TEXT(n)  section   .text.oidos. %+ n progbits alloc   exec nowrite
%endif

