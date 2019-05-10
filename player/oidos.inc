; See oidos.h for documentation.

%include "platform.inc"

; Functions
extern PUBLIC_FN(Oidos_FillRandomData)
extern PUBLIC_FN(Oidos_GenerateMusic)
extern PUBLIC_FN(Oidos_StartMusic)
extern PUBLIC_FN(Oidos_GetPosition)

; Variables
extern PUBLIC_FN(Oidos_MusicBuffer)
extern PUBLIC_FN(Oidos_TicksPerSecond)
extern PUBLIC_FN(Oidos_MusicLength)
extern PUBLIC_FN(Oidos_WavFileHeader)
extern PUBLIC_FN(Oidos_RandomData)

; GUID
extern ID3D11Texture2D_ID

; vim: set ft=asm
