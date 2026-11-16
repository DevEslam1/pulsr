package com.pulsr.music

import android.app.Service
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Native half of the system-behaviour pack.
 *
 * Exposes the music stream volume, and answers whether a notification sound can
 * be heard right now, so the Dart side can honour the volume-rocker and
 * "pause for notification sounds" settings. Task removal is Android-only: the
 * platform delivers [Service.onTaskRemoved] to the service itself, never to a
 * plugin, so [installTaskRemovalHook] records the service and the service's
 * own callback forwards to [handleTaskRemoved], which stops the service when
 * the user asked for that.
 *
 * Channel: `com.pulsr.music/system_behavior`.
 */
class SystemBehaviorPlugin private constructor(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null

    private val audioManager: AudioManager? by lazy {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (manager == null) {
            Log.w(TAG, "AudioManager unavailable; volume methods report -1")
        }
        manager
    }

    companion object {
        /** Platform channel name shared with the Dart client. */
        const val CHANNEL_NAME = "com.pulsr.music/system_behavior"

        private const val TAG = "PulsrSystemBehavior"
        private const val FULL_PERCENT = 100.0

        private val lock = Any()

        /** Whether the swiped-away task stops the service. */
        @Volatile
        private var stopWhenTaskRemoved: Boolean = true

        /** Service whose task removal is being watched, if any. */
        private var hookedService: WeakReference<Service>? = null

        /**
         * Registers the channel on [engine].
         *
         * Call once per engine, from the same place the other Pulsr plugins are
         * registered. Returns the plugin so the owner can [dispose] it.
         */
        fun register(engine: FlutterEngine, context: Context): SystemBehaviorPlugin {
            val plugin = SystemBehaviorPlugin(context.applicationContext)
            val methodChannel =
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = methodChannel
            methodChannel.setMethodCallHandler(plugin)
            return plugin
        }

        /**
         * Arms task-removal handling for [service].
         *
         * Android only delivers `onTaskRemoved` to the service, so this records
         * the service and logs the hook; the service must call
         * [handleTaskRemoved] from its own `onTaskRemoved` for the stop to
         * happen. Calling it again replaces the previous service.
         */
        fun installTaskRemovalHook(service: Service) {
            synchronized(lock) { hookedService = WeakReference(service) }
            Log.w(
                TAG,
                "Task-removal hook installed for ${service.javaClass.simpleName}; " +
                    "stopWhenTaskRemoved=$stopWhenTaskRemoved",
            )
        }

        /** Sets whether a removed task should stop the service. */
        fun setStopWhenTaskRemoved(enabled: Boolean) {
            stopWhenTaskRemoved = enabled
            Log.w(TAG, "stopWhenTaskRemoved=$enabled")
        }

        /** Whether a removed task currently stops the service. */
        fun isStopWhenTaskRemovedEnabled(): Boolean = stopWhenTaskRemoved

        /**
         * Call from the hooked service's `onTaskRemoved`.
         *
         * Stops the service with [Service.stopSelf] when the user enabled
         * "stop when swiped away"; otherwise the service keeps running and
         * only the Dart side pauses. Returns whether the service was stopped.
         */
        fun handleTaskRemoved(service: Service): Boolean {
            val hooked = synchronized(lock) { hookedService?.get() }
            if (hooked == null) {
                Log.w(TAG, "Task removal for an un-hooked service; installTaskRemovalHook was not called")
            } else if (hooked !== service) {
                Log.w(TAG, "Task removal for a service that is not the hooked one")
            }
            if (!stopWhenTaskRemoved) {
                Log.w(
                    TAG,
                    "Task removed for ${service.javaClass.simpleName}; stop disabled, keeping service",
                )
                return false
            }
            Log.w(TAG, "Task removed for ${service.javaClass.simpleName}; stopping service")
            service.stopSelf()
            return true
        }

        /** Releases the recorded service, e.g. when the engine is destroyed. */
        fun clearTaskRemovalHook() {
            synchronized(lock) { hookedService = null }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStreamVolume" -> result.success(currentStreamVolume())
            "getMaxVolume" -> result.success(maxStreamVolume())
            "getVolumeSteps" -> {
                val max = maxStreamVolume()
                result.success(if (max < 0) 0 else max + 1)
            }
            "setStreamVolume" -> {
                val percent = call.argument<Int>("percent")
                if (percent == null) {
                    result.error("bad_args", "setStreamVolume needs an int percent", null)
                    return
                }
                result.success(setStreamVolume(percent.coerceIn(0, 100)))
            }
            "isNotificationSoundActive" -> result.success(isNotificationSoundActive())
            "setStopWhenTaskRemoved" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                setStopWhenTaskRemoved(enabled)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun currentStreamVolume(): Int {
        val manager = audioManager ?: return -1
        return try {
            manager.getStreamVolume(AudioManager.STREAM_MUSIC)
        } catch (e: Exception) {
            Log.w(TAG, "getStreamVolume failed", e)
            -1
        }
    }

    private fun maxStreamVolume(): Int {
        val manager = audioManager ?: return -1
        return try {
            manager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        } catch (e: Exception) {
            Log.w(TAG, "getStreamMaxVolume failed", e)
            -1
        }
    }

    private fun setStreamVolume(percent: Int): Boolean {
        val manager = audioManager ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && manager.isVolumeFixed) {
                Log.w(TAG, "Music volume is fixed on this device; setStreamVolume ignored")
                return false
            }
            val max = manager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            if (max <= 0) {
                Log.w(TAG, "Invalid max music volume $max; setStreamVolume ignored")
                return false
            }
            val index = Math.round(percent / FULL_PERCENT * max).toInt().coerceIn(0, max)
            manager.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "setStreamVolume denied by the system", e)
            false
        } catch (e: Exception) {
            Log.w(TAG, "setStreamVolume failed", e)
            false
        }
    }

    /**
     * Whether a notification sound can currently be heard.
     *
     * True when the ringer is not silent, the notification stream is not
     * muted, and its level is above zero. Used to decide whether a system
     * alert is really audible before pausing music for it.
     */
    private fun isNotificationSoundActive(): Boolean {
        val manager = audioManager ?: return false
        return try {
            if (manager.ringerMode == AudioManager.RINGER_MODE_SILENT) {
                return false
            }
            val max = manager.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION)
            if (max <= 0) return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                manager.isStreamMute(AudioManager.STREAM_NOTIFICATION)
            ) {
                return false
            }
            manager.getStreamVolume(AudioManager.STREAM_NOTIFICATION) > 0
        } catch (e: Exception) {
            Log.w(TAG, "isNotificationSoundActive failed", e)
            false
        }
    }

    /** Detaches the channel handler and forgets the hooked service. */
    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        clearTaskRemovalHook()
    }
}
