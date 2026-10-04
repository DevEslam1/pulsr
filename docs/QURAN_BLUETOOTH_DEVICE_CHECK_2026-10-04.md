# Quran mode Bluetooth check — 2026-10-04

Test device: Xiaomi Pad 6 (Android API 36, arm64). Headphones: realme Buds Air6 Pro. Installed the updated ytm debug APK without clearing app data.

## Findings and changes

- Found a native reverb transition bug: clearing the active-stage bit skipped the reverb processor entirely, even while its envelope needed to fade. This affected normal effect disable and CPU-governor bypass. The engine now drives the envelope from the effective stage mask and processes the remaining fade until it finishes. This removes an abrupt reverb-to-dry transition that can cause a pop; it does not establish that this was the user's only noise source.
- Found incorrect Bluetooth diagnostics: merely having a SCO device available was reported as an active voice route. The check now requires the measured routed device ID to match that SCO device.
- Made the native bridge harness choose libc++ for the physical device ABI. The playback harness skips permission grants when already granted and chooses the audio permission appropriate to the Android API.

## Verification

- All five Java/JNI/native bridge smoke checks passed on arm64: PCM16 conversion, bypass/gain behavior, AAudio lifecycle, float/PCM24/PCM32 conversion and partial writes, and real AudioTrack Phone-route readback.
- Native bypass regression passed on the physical device, including new assertions that both manual disable and governor disable retain the reverb fade, finish it, and become bit-transparent afterward.
- Native single-tap reverb timing passed: zero mismatches, maximum error 4.76837e-7. Native reverb FFT/unity checks passed.
- Four Quran persistence/profile tests passed. Debug APK build succeeded and the updated APK was installed.
- Invoked actual PlayerCubit mode/style controls through the debug VM service. All six styles ran over the measured realme Bluetooth route at 44,100 Hz, PCM16. Restored the mode/style after the sweep and paused playback.
- Bluetooth codec details were initially inaccessible without Bluetooth permission; the corrected diagnostic reported permission_required. Once permission became available, the app could read codec details. App-stream format and Bluetooth codec format are separate values.

## Remaining limits

Several style transitions triggered temporary CPU-governor bypass of reverb, multiband compression, or saturation in the debug build. This remains a performance limitation and can change the sound. Short controlled tests are not a sustained-load or thermal certification.

No listening confirmation or electrical recording of the headphone output was available. The user's particular crackle/hiss cannot be declared fully resolved from route telemetry or logs alone. The test source was a low-level WAV tone, not the original recitation that exhibited noise. A listening comparison using that original recording remains necessary.

## Follow-up: intermittent on/off pop and USB earphones

The user clarified that the noise happens intermittently during mode toggles. Added a separate 40ms PCM gain envelope around complete Quran profile edits. The audio handler waits for the actual render-thread gain to reach silence, applies the changes, waits for the serial native preparation queue, and releases the envelope. It composes with the existing sleep/crossfade envelope rather than replacing it. Profile edits are serialized and restore the gain in a finally block.

Physical arm64 and emulator Java/JNI tests verified repeated mute/unmute at 44.1 and 48k, stereo equality, bounded adjacent-sample changes, exact silence/unity endpoints, and preservation of the separate 0.5 sleep/crossfade gain. Thirty focused Dart tests passed. Native bit-perfect bypass remains bitwise unchanged.

The user connected USB earphones using wireless ADB to keep USB-C free. Android API 36 identified the earphones as GVAUDIO GVAUDIO / GVAUDIO (USB DAC). The active app stream reported 44.1k PCM16; the device capability list reported 48k. Android advertised no exclusive bit-perfect mixer configuration. This does not certify the electrical output rate or all capabilities of the hardware.

Fixed the misleading mapping of usb_not_supported to an Android-14 requirement. Native reports now distinguish the real minimum-version check from no_supported_mixer_attributes. The live SettingsCubit enable attempt was rejected with the correct message: "This USB DAC does not advertise an exclusive mixer configuration." The toggle remained off.

## Follow-up: exclusive AAudio rejection broke playback

The physical tablet had AAudio Direct/exclusive enabled. AAudio returned a shared stream, so the native strict contract correctly refused it. Media3 raised AudioSink.ConfigurationException and playback stopped. The preference setter previously checked only Android/library availability and accepted the setting before any real stream opened.

The setter now opens and closes a real stream probe before accepting a new AAudio preference. A refusal propagates to SettingsCubit, which leaves the preference off. If a subsequent song/device causes an AudioSink configuration, initialization or write error, the player disables its AAudio sink and rebuilds with AudioTrack, preserving playlist, position and play intent. This recovery does not establish bit-perfect output.

With normal USB playback running, a direct native setBitPerfectMode(true) request returned false with no_supported_mixer_attributes on Android API 36. SettingsCubit also kept the bit-perfect toggle false and displayed the USB mixer capability message. Cold-start playback, progress (5,939ms), pause and resume passed before the final reinstall. The Android version is sufficient; this OS/device route does not expose the required exclusive mixer configuration. Enabling true bit-perfect on this combination would require a separately implemented direct USB audio driver, not bypassing this capability check.

All six Quran styles were exercised with actual USB playback after the transition barrier dispatch fix. Every measured sample reported GVAUDIO (USB DAC), 44.1k PCM16. No profile/transition/MissingPlugin failure was present in the process log. The debug CPU governor still temporarily bypassed stages (reverb/saturation). Audible noise remains unverified.

The first AAudio rejection test exposed an unnecessary player rebuild despite an unchanged effective output. The final setter only rebuilds for effective output changes or accepted active AAudio configuration changes, so rejecting an unavailable exclusive stream leaves normal playback intact. Thirty focused Dart tests passed again, and the final debug APK built successfully.

Final APK installed on the physical tablet without clearing data. Final cold-start USB playback/progress (5,837ms), pause and resume passed. Requesting exclusive AAudio left the toggle false and retained a measured GVAUDIO USB 44.1k PCM16 stream immediately after rejection. The native bit-perfect request remained rejected with no_supported_mixer_attributes; the UI displayed the correct USB capability reason. Playback was paused after testing.

## Vocal warmth check — 2026-10-04

The warmth slider displayed saturationMix even when the selected Quran profile disabled saturation (Murattal, Memorization and Study). That could display 30% with no warmth processing. At 0%, the old callback still enabled saturation. The control now displays 0% when disabled and uses a Quran-specific setter: positive values enable saturation with the selected style's drive/tilt; zero disables it. The UI commits only after the native setter accepts the update, preserves the last accepted value on failure, and reports the error. Non-finite edits and edits outside Quran mode are ignored. Changes use the existing profile fade and apply once on slider release to avoid flooding playback with fade cycles during a drag.

Seven Quran controller tests passed, including new dry-profile activation, zero-disable, clamping, rejection and invalid-input cases. Static analysis passed. The standalone physical arm64 Java/JNI/production native engine harness measured mix 0/0.3/0.6 at Quran drive values 0.15/0.18/0.20/0.22 at both 44.1k and 48k. Every tested profile drive changed PCM, increasing mix increased the measured contribution, samples remained finite/bounded, and matched stereo input remained matched. The mix-0.6 relative PCM difference from delay-matched mix-0 output was approximately 4.38–4.50% for the generated 400/1200Hz test signal. This is a signal measurement, not a subjective listening score or a promise that all recordings sound noticeably different.

Installed the warmth fix on the physical tablet and passed cold-start playback/progress (6,046ms), pause and resume. An isolated live app test then invoked the actual PlayerCubit setQuranWarmth control through repeated 0/0.6/0/0.6 changes during playback. UI and native DSP reports agreed: mix 0 disabled saturation; mix 0.6 enabled it at the selected Mujawwad drive 0.22. No bit-perfect bypass or saturation CPU degradation was reported, playback remained active, and the USB route remained GVAUDIO at 44.1k PCM16. Original Quran settings were restored and playback paused. Listening with the user's original recitation remains necessary to judge subjective warmth strength.
