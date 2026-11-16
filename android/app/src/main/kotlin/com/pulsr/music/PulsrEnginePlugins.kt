package com.pulsr.music

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine

/**
 * Owns plugins whose lifetime follows the FlutterEngine, not the Activity.
 *
 * audio_service hands every Activity the same cached engine, and the Flutter
 * host calls configureFlutterEngine()/cleanUpFlutterEngine() on every attach
 * and detach. Registering a new plugin per attach duplicates channel handlers
 * and leaks listeners; running their cleanup per detach kills the DSP chain
 * (and stops the USB stream) while playback continues in the service.
 */
class PulsrEnginePlugins private constructor(
    private val engine: FlutterEngine,
    val audioEffects: AudioEffectsPlugin,
    val tagEditor: TagEditorPlugin,
    val visualizer: VisualizerPlugin,
    val ringtone: RingtonePlugin,
    val scrobbler: ScrobblerPlugin,
    val ytmExtractor: YtmExtractorPlugin,
    val ytDownload: YtDownloadPlugin,
    val waveform: WaveformPlugin,
    val proxy: ProxyPlugin,
    val hiResDac: HiResDacPlugin,
    val usbExclusive: UsbExclusivePlugin,
    val castDiscovery: CastDiscoveryPlugin,
    val castSession: CastSessionPlugin,
    val roomCorrection: RoomCorrectionPlugin,
    val tts: TtsPlugin,
    val usbErgonomics: UsbErgonomicsPlugin,
    val systemBehavior: SystemBehaviorPlugin,
    val smb: SmbPlugin,
) {
    private val cleanedUp = java.util.concurrent.atomic.AtomicBoolean(false)

    private val lifecycleListener = object : FlutterEngine.EngineLifecycleListener {
        override fun onPreEngineRestart() = Unit
        override fun onEngineWillDestroy() = cleanup()
    }

    fun cleanup() {
        if (!cleanedUp.compareAndSet(false, true)) return
        remove(engine)
        try {
            engine.removeEngineLifecycleListener(lifecycleListener)
        } catch (_: Exception) {}
        val steps: List<Pair<String, () -> Unit>> = listOf(
            "AudioEffects" to { audioEffects.cleanup() },
            "TagEditor" to { tagEditor.cleanup() },
            "Visualizer" to { visualizer.cleanup() },
            "Ringtone" to { ringtone.cleanup() },
            "Scrobbler" to { scrobbler.cleanup() },
            "YtmExtractor" to { ytmExtractor.cleanup() },
            "YtDownload" to { ytDownload.cleanup() },
            "Waveform" to { waveform.cleanup() },
            "Proxy" to { proxy.cleanup() },
            "HiResDac" to { hiResDac.dispose() },
            "UsbExclusive" to { usbExclusive.dispose() },
            "CastDiscovery" to { castDiscovery.dispose() },
            "CastSession" to { castSession.cleanup() },
            "RoomCorrection" to { roomCorrection.cleanup() },
            "Tts" to { tts.dispose() },
            "UsbErgonomics" to { usbErgonomics.dispose() },
            "SystemBehavior" to { systemBehavior.dispose() },
            "Smb" to { smb.cleanup() },
        )
        for ((name, step) in steps) {
            try {
                step()
            } catch (e: Exception) {
                Log.w(TAG, "Engine-scoped cleanup failed for $name: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "PulsrEnginePlugins"
        private val lock = Any()
        private val byEngine = java.util.IdentityHashMap<FlutterEngine, PulsrEnginePlugins>()

        @JvmStatic
        fun obtain(engine: FlutterEngine, context: Context): PulsrEnginePlugins {
            synchronized(lock) {
                byEngine[engine]?.let { return it }
                val appContext = context.applicationContext
                val messenger = engine.dartExecutor.binaryMessenger
                val cleanups = mutableListOf<Pair<String, () -> Unit>>()
                try {
                    val audioEffects = AudioEffectsPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("AudioEffects" to { p.cleanup() }) }
                    val tagEditor = TagEditorPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("TagEditor" to { p.cleanup() }) }
                    val visualizer = VisualizerPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("Visualizer" to { p.cleanup() }) }
                    val ringtone = RingtonePlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("Ringtone" to { p.cleanup() }) }
                    val scrobbler = ScrobblerPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("Scrobbler" to { p.cleanup() }) }
                    val ytmExtractor = YtmExtractorPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("YtmExtractor" to { p.cleanup() }) }
                    val ytDownload = YtDownloadPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("YtDownload" to { p.cleanup() }) }
                    val waveform = WaveformPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("Waveform" to { p.cleanup() }) }
                    val proxy = ProxyPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("Proxy" to { p.cleanup() }) }
                    val hiResDac = HiResDacPlugin(appContext, messenger)
                        .also { p -> cleanups.add("HiResDac" to { p.dispose() }) }
                    val usbExclusive = UsbExclusivePlugin(appContext, messenger)
                        .also { p -> cleanups.add("UsbExclusive" to { p.dispose() }) }
                    val castDiscovery = CastDiscoveryPlugin(appContext, messenger)
                        .also { p -> cleanups.add("CastDiscovery" to { p.dispose() }) }
                    val castSession = CastSessionPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("CastSession" to { p.cleanup() }) }
                    val roomCorrection = RoomCorrectionPlugin.registerWith(engine, appContext)
                        .also { p -> cleanups.add("RoomCorrection" to { p.cleanup() }) }
                    val tts = TtsPlugin.register(engine)
                        .also { p -> cleanups.add("Tts" to { p.dispose() }) }
                    val usbErgonomics = UsbErgonomicsPlugin.register(engine, appContext)
                        .also { p -> cleanups.add("UsbErgonomics" to { p.dispose() }) }
                    val systemBehavior = SystemBehaviorPlugin.register(engine, appContext)
                        .also { p -> cleanups.add("SystemBehavior" to { p.dispose() }) }
                    val smb = SmbPlugin.register(engine)
                        .also { p -> cleanups.add("Smb" to { p.cleanup() }) }
                    val plugins = PulsrEnginePlugins(
                        engine = engine,
                        audioEffects = audioEffects,
                        tagEditor = tagEditor,
                        visualizer = visualizer,
                        ringtone = ringtone,
                        scrobbler = scrobbler,
                        ytmExtractor = ytmExtractor,
                        ytDownload = ytDownload,
                        waveform = waveform,
                        proxy = proxy,
                        hiResDac = hiResDac,
                        usbExclusive = usbExclusive,
                        castDiscovery = castDiscovery,
                        castSession = castSession,
                        roomCorrection = roomCorrection,
                        tts = tts,
                        usbErgonomics = usbErgonomics,
                        systemBehavior = systemBehavior,
                        smb = smb,
                    )
                    byEngine[engine] = plugins
                    engine.addEngineLifecycleListener(plugins.lifecycleListener)
                    return plugins
                } catch (t: Throwable) {
                    byEngine.remove(engine)
                    for ((name, step) in cleanups.asReversed()) {
                        try {
                            step()
                        } catch (ce: Exception) {
                            Log.w(TAG, "Rollback cleanup failed for $name: ${ce.message}")
                        }
                    }
                    throw t
                }
            }
        }

        private fun remove(engine: FlutterEngine) {
            synchronized(lock) {
                byEngine.remove(engine)
            }
        }
    }
}
