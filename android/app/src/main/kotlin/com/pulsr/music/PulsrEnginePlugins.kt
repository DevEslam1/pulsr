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
) {
    private val cleanedUp = java.util.concurrent.atomic.AtomicBoolean(false)

    private val lifecycleListener = object : FlutterEngine.EngineLifecycleListener {
        override fun onPreEngineRestart() = Unit
        override fun onEngineWillDestroy() = cleanup()
    }

    fun cleanup() {
        if (!cleanedUp.compareAndSet(false, true)) return
        remove(engine)
        // The listener is intentionally left registered: cleanup only runs
        // from onEngineWillDestroy, and mutating the listener set while the
        // engine is iterating it can throw.
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
                val plugins = PulsrEnginePlugins(
                    engine = engine,
                    audioEffects = AudioEffectsPlugin.registerWith(engine, appContext),
                    tagEditor = TagEditorPlugin.registerWith(engine, appContext),
                    visualizer = VisualizerPlugin.registerWith(engine, appContext),
                    ringtone = RingtonePlugin.registerWith(engine, appContext),
                    scrobbler = ScrobblerPlugin.registerWith(engine, appContext),
                    ytmExtractor = YtmExtractorPlugin.registerWith(engine, appContext),
                    ytDownload = YtDownloadPlugin.registerWith(engine, appContext),
                    waveform = WaveformPlugin.registerWith(engine, appContext),
                    proxy = ProxyPlugin.registerWith(engine, appContext),
                    hiResDac = HiResDacPlugin(appContext, messenger),
                    usbExclusive = UsbExclusivePlugin(appContext, messenger),
                    castDiscovery = CastDiscoveryPlugin(appContext, messenger),
                    castSession = CastSessionPlugin.registerWith(engine, appContext),
                    roomCorrection = RoomCorrectionPlugin.registerWith(engine, appContext),
                )
                byEngine[engine] = plugins
                engine.addEngineLifecycleListener(plugins.lifecycleListener)
                return plugins
            }
        }

        private fun remove(engine: FlutterEngine) {
            synchronized(lock) {
                byEngine.remove(engine)
            }
        }
    }
}
