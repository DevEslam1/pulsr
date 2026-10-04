# Audio output sheet: routing and reporting

## Implemented

- Device taps route the app's ExoPlayer AudioTrack or native AAudio stream. They no longer attempt privileged global audio-policy routing or open Bluetooth settings as a fallback.
- While playback is running, Android verifies the requested device against the stream readback for up to four seconds. Refused requests restore the previous preference. Superseded requests cannot undo a newer selection.
- AAudio changes devices by reconstructing its stream on the renderer thread, preserving playback intent and rebasing position from the next PCM buffer. A rejected configuration attempts to restore the previous stream.
- Current-device checks use AudioTrack.getRoutedDevice or AAudioStream_getDeviceId. Connected devices, preferred devices and active devices are distinct.
- The displayed rate and PCM encoding/depth describe the app stream. AudioTrack values are read from Media3's owned AudioTrack; AAudio values are published from its negotiated stream. Unknown values remain unknown. Reflection failure also produces unknown values. The Media3 AudioTrack field is preserved in release shrinker rules.
- 44.1 kHz is no longer truncated to 44 kHz. Float PCM is identified separately from integer PCM.
- Manual sample-rate/depth conversion is disabled: the native sinc playback resampler is not wired into this playback path. Device capability lists alone do not make those controls functional.
- Bluetooth codec/rate/depth controls require both an active Bluetooth route and the privileged permission Android requires for writes. Readable codec capabilities do not imply writable controls. Refused requests are not displayed optimistically.
- Rate/depth preferences are persisted only after acceptance. Native rejected format requests roll back their requested values. Refreshes no longer resurrect stale selected targets.
- The sheet follows the current song. Missing source rates/depths/online bitrates remain unknown; container-size averages are labelled estimates. Source losslessness does not certify output bit perfection. Format names do not imply float output or hardware offload. Unmeasured platform conversion is not labelled as Pulsr sinc processing.
- A startup race found during verification was repaired in the vendored just_audio Dart layer: replacing a source must cancel the old source load without cancelling the shared native-player initialization. Otherwise the replacement and later volume calls inherited an interrupted platform future.

## Verification

- 44 focused Dart tests pass, including unknown capability reporting, refused format persistence, Phone requests never opening settings, source metadata, output update propagation, and source replacement during delayed native initialization.
- Static analysis of the eight changed audio/test entry points passes.
- Android debug `ytm` APK builds with production isolation verification passing.
- Five Java/JNI Android harnesses pass: exhaustive PCM16 values and AAudio JNI contracts; DSP bypass/gain transitions; AAudio lifecycle and actual Phone routing; float PCM24/PCM32 processing/retries; real PCM16 and float AudioTrack Phone routing, 44.1 kHz readback, preference clearing and released-stream reporting.
- Three cold starts reached PLAYING and passed progress/pause/resume checks: approximately 6.27 and 6.24 seconds on the repaired build, then 5.40 seconds after installing the final routing-generation APK on a restarted emulator.

## Limits

These are emulator measurements of the app streams, not physical DAC measurements. Bluetooth-to-Phone handoff, vendor routing policy, USB exclusive modes, reconnect behavior and downstream sample conversion need physical-device coverage. Android's accepted exclusive mixer configuration plus matching app PCM is not a hardware bit-for-bit certificate. The sheet explicitly keeps downstream hardware format unverified.

The normal sink readback currently depends on the pinned Media3 1.4.1 AudioTrack field. An upgrade must rerun the route/readback harness; unavailable readback must remain unknown.

API semantics: [AudioTrack](https://developer.android.com/reference/android/media/AudioTrack), [AudioRouting](https://developer.android.com/reference/android/media/AudioRouting), and [AAudio](https://developer.android.com/ndk/reference/group/audio).
