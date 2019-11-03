#ifndef _OIDOS_H_
#define _OIDOS_H_

struct sample {
	short left,right;
};

#ifdef __cplusplus
extern "C" {
#endif
	// Fill the block of random data used by Oidos.
	// Must be called before Oidos_GenerateMusic.
	void Oidos_FillRandomData();

	// Generate the whole music into the music buffer. When this function
	// returns, Oidos_MusicBuffer will be filled with sound data,
	// and Oidos_StartMusic can be called.
	void Oidos_GenerateMusic();

	// On Linux, there are too many sound APIs to choose from,
	// so we leave it to the user to implement playback and timer.
#ifdef _WIN32
	// Play the music
	void Oidos_StartMusic();

	// Returns how much of the music has currently been played.
	// Use this function as the timer for the visuals in your intro.
	// Returned value is measured in music ticks (pattern rows).
	float Oidos_GetPosition();
#endif

	// Buffer containing the music.
	extern struct sample Oidos_MusicBuffer[];

	// The tick rate of the music.
	extern const float Oidos_TicksPerSecond;

	// The length of the music in ticks.
	extern const unsigned int Oidos_MusicLength;

	// Wav file header to use if you want to write the music to disk.
	// Write these 44 bytes followed by Oidos_MusicBuffer with a
	// length of Oidos_WavFileHeader[10].
	extern unsigned int Oidos_WavFileHeader[11];

	// Block of random data used by Oidos.
	// Can also be useful as a 3D noise texture.
	#define NOISESIZE 64
	extern unsigned Oidos_RandomData[NOISESIZE * NOISESIZE * NOISESIZE];
#ifdef __cplusplus
};
#endif

// If you are using D3D11, you can re-use this GUID.
#ifdef GUID_DEFINED
extern GUID ID3D11Texture2D_ID;
#endif

#endif
