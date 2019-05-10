/* Dump an Oidos song to stdout. */

#include <unistd.h>

#include "oidos.h"

int main() {
	Oidos_FillRandomData();
	Oidos_GenerateMusic();

#ifndef NO_WAV_HEADER
	write(STDOUT_FILENO, Oidos_WavFileHeader, sizeof(Oidos_WavFileHeader));
#endif
	write(STDOUT_FILENO, Oidos_MusicBuffer, Oidos_WavFileHeader[10]);
}
