package com.pulsr.music

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Collections
import java.util.WeakHashMap

/**
 * Native half of the system-behaviour pack.
 *
 * The app's task-removal policy is real: Android delivers a task ending as the
 * root activity being finished, so the plugin watches the Activity lifecycle
 * (`Application.ActivityLifecycleCallbacks`) and, when the last activity of the
 * task is finishing for real (not a configuration change) and
 * `stopWhenTaskRemoved` is enabled, asks the Dart runtime over the same method
 * channel to stop playback. The runtime executes it through the audio handler,
 * so the audio service and the media notification shut down through the normal
 * path. The old `installTaskRemovalHook`/`handleTaskRemoved(Service)` pair was
 * never called and has been removed.
 *
 * The former stream-volume helpers were also removed: no Dart caller used
 * them, so they were dead platform code. Volume changes go through the audio
 * handler and the system's own volume keys.
 *
 * Channel: `com.pulsr.music/system_behavior`.
 */
class SystemBehaviorPlugin internal constructor(
    private val application: Application?,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler, Application.ActivityLifecycleCallbacks {

    /** Live activities tracked weakly; task removal finishes the last one. */
    private val liveActivities: MutableSet<Activity> =
        Collections.synchronizedSet(Collections.newSetFromMap(WeakHashMap<Activity, Boolean>()))

    companion object {
        /** Platform channel name shared with the Dart client. */
        const val CHANNEL_NAME = "com.pulsr.music/system_behavior"

        /** Method the native side calls when the task is removed. */
        const val METHOD_TASK_REMOVED = "taskRemoved"

        private const val TAG = "PulsrSystemBehavior"
        private const val METHOD_SET_TASK_POLICY = "setStopWhenTaskRemoved"

        /** Whether the swiped-away task stops playback. Matches the Dart default. */
        @Volatile
        private var stopWhenTaskRemoved: Boolean = false

        /**
         * Registers the channel on [engine] and arms the activity watcher.
         *
         * Call once per engine, from the same place the other Pulsr plugins are
         * registered. Returns the plugin so the owner can [dispose] it.
         */
        fun register(engine: FlutterEngine, context: Context): SystemBehaviorPlugin {
            val appContext = context.applicationContext ?: context
            val application = appContext as? Application
            if (application == null) {
                Log.w(TAG, "Application context unavailable; task removal stays unobserved")
            }
            val methodChannel =
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            val plugin = SystemBehaviorPlugin(application, methodChannel)
            methodChannel.setMethodCallHandler(plugin)
            application?.registerActivityLifecycleCallbacks(plugin)
            return plugin
        }

        /** Sets whether a removed task should stop playback. */
        fun setStopWhenTaskRemoved(enabled: Boolean) {
            stopWhenTaskRemoved = enabled
            Log.w(TAG, "stopWhenTaskRemoved=$enabled")
        }

        /** Whether a removed task currently stops playback. */
        fun isStopWhenTaskRemovedEnabled(): Boolean = stopWhenTaskRemoved
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_SET_TASK_POLICY -> {
                setStopWhenTaskRemoved(call.argument<Boolean>("enabled") ?: false)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // ---- Activity lifecycle: the real task-removal signal ----

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        liveActivities.add(activity)
    }

    override fun onActivityStarted(activity: Activity) {
        liveActivities.add(activity)
    }

    override fun onActivityResumed(activity: Activity) {
        liveActivities.add(activity)
    }

    override fun onActivityPaused(activity: Activity) = Unit

    override fun onActivityStopped(activity: Activity) = Unit

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    override fun onActivityDestroyed(activity: Activity) {
        val remaining = synchronized(liveActivities) {
            liveActivities.remove(activity)
            liveActivities.size
        }
        if (!activity.isFinishing) return
        if (activity.isChangingConfigurations) return
        if (!activity.isTaskRoot) return
        if (remaining > 0) return
        if (!stopWhenTaskRemoved) {
            Log.w(TAG, "Task removed; stop disabled, leaving playback to the handler")
            return
        }
        Log.w(TAG, "Task removed; asking Dart to stop playback")
        notifyTaskRemoved()
    }

    /** Asks the Dart runtime to run the stop action. Safe when it is absent. */
    private fun notifyTaskRemoved() {
        try {
            channel.invokeMethod(METHOD_TASK_REMOVED, null)
        } catch (e: Exception) {
            Log.w(TAG, "Announcing task removal to Dart failed: ${e.message}")
        }
    }

    /** Detaches the channel handler and the activity watcher. */
    fun dispose() {
        liveActivities.clear()
        try {
            application?.unregisterActivityLifecycleCallbacks(this)
        } catch (e: Exception) {
            Log.w(TAG, "Unregistering the activity watcher failed: ${e.message}")
        }
        try {
            channel.setMethodCallHandler(null)
        } catch (e: Exception) {
            Log.w(TAG, "Detaching the system-behaviour channel failed: ${e.message}")
        }
    }
}
