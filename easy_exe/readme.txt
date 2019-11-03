
This setup is for easily building an executable version of a piece of music
created using Oidos.

For Windows, proceed as follows:

1. Place your music here, named music.xrns.
2. Edit the music.txt file to contain the text you would like the executable
   to print at startup.
3. Edit the wav_filename.txt file to contain the filename (without trailing
   newline!) to which the wav writer executable shall write the music.
4. Optionally modify the Crinkler options in crinkler_options.txt
   (read the Crinkler manual for details).
5. Run build.bat to get two executables: music.exe, which plays the music,
   and music_wav.exe, which writes the music in WAV format to the file
   specified in wav_filename.txt, and then plays it.

If no executables appear, the script encountered an error along the way.
Consult the output window text for details.

For Linux:

1. Place your music here, named music.xrns.
2. Run build.sh to get an executable named dump_wav, which writes the music
   in WAV format to stdout.

Enjoy!
