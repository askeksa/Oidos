
%ifdef LINUX
%define PUBLIC_FN(n) n
%else
%define PUBLIC_FN(n) _ %+ n
%endif

%ifdef WIN32
%define ID3D11Texture2D_ID ?ID3D11Texture2D_ID@@3U_GUID@@A
%endif

%ifdef LINUX
%define SECT_BSS(n)   section    .bss.oidos. %+ n   nobits alloc noexec   write
%define SECT_DATA(n)  section   .data.oidos. %+ n progbits alloc noexec   write
%define SECT_RDATA(n) section .rodata.oidos. %+ n progbits alloc noexec nowrite
%define SECT_TEXT(n)  section   .text.oidos. %+ n progbits alloc   exec nowrite
%else
%define SECT_BSS(n)   section .oidos. %+ n bss
%define SECT_DATA(n)  section .oidos. %+ n data
%define SECT_RDATA(n) section .oidos. %+ n rdata
%define SECT_TEXT(n)  section .oidos. %+ n code
%endif

