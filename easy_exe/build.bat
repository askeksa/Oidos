del /q temp\*
del music.exe
del music_wav.exe

..\convert\OidosConvert.exe music.xrns temp\music.asm

copy ..\player\oidos.asm temp
copy ..\player\oidos.inc temp
copy ..\player\platform.inc temp
copy ..\player\play.asm temp
copy ..\player\random.asm temp
copy music.txt temp
copy wav_filename.txt temp

cd temp
..\tools\nasmw -f win32 oidos.asm -o oidos.obj
..\tools\nasmw -f win32 random.asm -o random.obj
..\tools\nasmw -f win32 play.asm -o play.obj
..\tools\nasmw -f win32 -dWRITE_WAV play.asm -o play_wav.obj
cd ..

tools\crinkler20\crinkler temp\oidos.obj temp\random.obj temp\play.obj /OUT:music.exe /ENTRY:main tools\kernel32.lib tools\user32.lib tools\winmm.lib tools\msvcrt_old.lib @crinkler_options.txt
tools\crinkler20\crinkler temp\oidos.obj temp\random.obj temp\play_wav.obj /OUT:music_wav.exe /ENTRY:main tools\kernel32.lib tools\user32.lib tools\winmm.lib tools\msvcrt_old.lib @crinkler_options.txt

pause
