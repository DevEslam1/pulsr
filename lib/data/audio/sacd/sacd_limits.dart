// lib/data/audio/sacd/sacd_limits.dart
//
// One shared memory contract for DSD audio, used by the SACD extractor and the
// in-memory DSD decoder.
//
// The decoder reads a whole DSF/DFF file into memory and then expands it (DoP
// framing is ~2x-2.7x, PCM decoding is ~3x). The extractor therefore must never
// write a file the decoder would refuse: a 512 MB DSF extracted happily and
// then rejected by a 300 MB decoder cap was a real, user-visible split brain.
//
// 150 MB is the largest single DSD file this build will load. A DSD64 stereo
// track reaches it after roughly seven minutes; longer tracks fail with an
// explicit message instead of an OOM kill.

/// Largest DSD file (DSF or DFF) the app will hold in memory, in bytes.
const int kMaxDsdFileBytes = 150 * 1024 * 1024;

/// Channel count the in-memory DSD decoder supports (mono/stereo only).
const int kMaxDsdDecodeChannels = 2;
