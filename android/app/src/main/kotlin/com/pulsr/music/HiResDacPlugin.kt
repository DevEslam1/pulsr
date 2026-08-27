package com.pulsr.music

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class HiResDacPlugin(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "HiResDacPlugin"
        private const val METHOD_CHANNEL = "com.pulsr.music/hires_dac"
        private const val EVENT_CHANNEL = "com.pulsr.music/hires_dac_events"
    }

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null

    private var bitPerfectRequested: Boolean = false
    private var selectedDeviceId: Int? = null
    private var targetSampleRate: Int = 0
    private var targetBitDepth: Int = 0
    private var audioDeviceCallback: AudioDeviceCallback? = null
    private var usbReceiver: BroadcastReceiver? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        registerAudioDeviceCallbacks()
    }

    private fun registerAudioDeviceCallbacks() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioManager != null) {
            audioDeviceCallback = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                    notifyDeviceChange()
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                    notifyDeviceChange()
                }
            }
            audioManager.registerAudioDeviceCallback(audioDeviceCallback, null)
        }

        usbReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                        if (bitPerfectRequested) {
                            bitPerfectRequested = false
                            try { applyBitPerfectMode(false) } catch (_: Exception) {}
                        }
                        notifyDeviceChange()
                    }
                    UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                        notifyDeviceChange()
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(usbReceiver, filter)
            }
        } catch (_: Exception) {
            try {
                context.registerReceiver(usbReceiver, filter)
            } catch (_: Exception) {}
        }
    }

    private fun notifyDeviceChange() {
        val info = getAudioOutputDetails()
        eventSink?.success(info)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAudioOutputInfo" -> {
                result.success(getAudioOutputDetails())
            }
            "isBitPerfectSupported" -> {
                result.success(isBitPerfectSupportedOnPlatform())
            }
            "setBitPerfectMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                bitPerfectRequested = enabled
                val success = applyBitPerfectMode(enabled)
                notifyDeviceChange()
                result.success(success)
            }
            "setOutputDevice" -> {
                val deviceId = call.argument<Int>("deviceId")
                selectedDeviceId = deviceId
                var success = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && audioManager != null && deviceId != null) {
                    val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    val targetDev = devices.firstOrNull { it.id == deviceId }
                    if (targetDev != null) {
                        try {
                            success = audioManager.setCommunicationDevice(targetDev)
                        } catch (_: Exception) {}
                    }
                }
                notifyDeviceChange()
                result.success(success)
            }
            "clearOutputDevice" -> {
                selectedDeviceId = null
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && audioManager != null) {
                    try {
                        audioManager.clearCommunicationDevice()
                    } catch (_: Exception) {}
                }
                notifyDeviceChange()
                result.success(true)
            }
            "setTargetOutputFormat" -> {
                val sRate = call.argument<Int>("sampleRate") ?: 0
                val bDepth = call.argument<Int>("bitDepth") ?: 0
                targetSampleRate = sRate
                targetBitDepth = bDepth
                notifyDeviceChange()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        notifyDeviceChange()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioManager != null && audioDeviceCallback != null) {
            audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
        }
        if (usbReceiver != null) {
            try {
                context.unregisterReceiver(usbReceiver)
            } catch (_: Exception) {}
        }
    }

    private fun isBitPerfectSupportedOnPlatform(): Boolean {
        return Build.VERSION.SDK_INT >= 34 // Android 14 (API 34) introduced bit-perfect mixer attributes
    }

    private fun applyBitPerfectMode(enabled: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < 34 || audioManager == null) {
            return false
        }
        return try {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val usbDevice = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET }
                ?: return false

            val getSupportedMethod = AudioManager::class.java.getMethod("getSupportedAudioMixerAttributes", AudioDeviceInfo::class.java)
            val supportedAttributes = getSupportedMethod.invoke(audioManager, usbDevice) as? List<*> ?: emptyList<Any>()
            if (supportedAttributes.isEmpty()) return false

            if (enabled) {
                var selectedAttr: Any? = null
                for (attr in supportedAttributes) {
                    if (attr != null) {
                        try {
                            val mixerBehaviorMethod = attr.javaClass.getMethod("getMixerBehavior")
                            val behavior = mixerBehaviorMethod.invoke(attr) as? Int
                            if (behavior == 1) { // MIXER_BEHAVIOR_BIT_PERFECT = 1
                                selectedAttr = attr
                                break
                            }
                        } catch (_: Exception) {}
                    }
                }
                if (selectedAttr == null) {
                    selectedAttr = supportedAttributes.first()
                }

                val mixerAttrClass = Class.forName("android.media.AudioMixerAttributes")
                val setMethod = AudioManager::class.java.getMethod("setAudioMixerAttributes", AudioDeviceInfo::class.java, mixerAttrClass)
                (setMethod.invoke(audioManager, usbDevice, selectedAttr) as? Boolean) ?: false
            } else {
                val clearMethod = AudioManager::class.java.getMethod("clearAudioMixerAttributes", AudioDeviceInfo::class.java)
                (clearMethod.invoke(audioManager, usbDevice) as? Boolean) ?: false
            }
        } catch (e: NoSuchMethodException) {
            Log.w(TAG, "Bit-perfect API not available on this device: ${e.message}")
            false
        } catch (e: ClassNotFoundException) {
            Log.w(TAG, "AudioMixerAttributes class not found: ${e.message}")
            false
        } catch (e: Throwable) {
            Log.w(TAG, "Bit-perfect mode failed: ${e.message}")
            false
        }
    }

    private fun getAudioOutputDetails(): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || audioManager == null) {
            result["deviceName"] = "Default Audio Output"
            result["isUsbDac"] = false
            result["sampleRate"] = 44100
            result["bitDepth"] = 16
            result["isBitPerfectActive"] = false
            result["isBitPerfectSupported"] = false
            result["supportedSampleRates"] = listOf(44100, 48000)
            return result
        }

        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val usbDevice = devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        }

        val activeDevice = usbDevice ?: devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        } ?: devices.firstOrNull()

        val isUsb = (usbDevice != null)
        val deviceName = when {
            usbDevice != null -> {
                val name = usbDevice.productName.toString()
                if (name.isNotBlank()) "$name (USB DAC)" else "USB Audio DAC"
            }
            activeDevice != null -> {
                val typeName = getDeviceTypeName(activeDevice.type)
                val name = activeDevice.productName.toString()
                if (name.isNotBlank() && name != typeName) "$name ($typeName)" else typeName
            }
            else -> "Default Audio Output"
        }

        val sampleRates = activeDevice?.sampleRates?.toList()?.filter { it > 0 } ?: listOf(44100, 48000)
        val maxSampleRate = sampleRates.maxOrNull() ?: 48000

        var bitDepth = 16
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && activeDevice != null) {
            for (encoding in activeDevice.encodings) {
                when (encoding) {
                    AudioFormat.ENCODING_PCM_FLOAT -> bitDepth = maxOf(bitDepth, 32)
                    AudioFormat.ENCODING_PCM_24BIT_PACKED -> bitDepth = maxOf(bitDepth, 24)
                    AudioFormat.ENCODING_PCM_32BIT -> bitDepth = maxOf(bitDepth, 32)
                }
            }
        }

        var isBitPerfectActive = false
        if (Build.VERSION.SDK_INT >= 34 && isUsb && usbDevice != null) {
            try {
                val getAttrMethod = AudioManager::class.java.getMethod("getAudioMixerAttributes", AudioDeviceInfo::class.java)
                val currentAttr = getAttrMethod.invoke(audioManager, usbDevice)
                if (currentAttr != null) {
                    val mixerBehaviorMethod = currentAttr.javaClass.getMethod("getMixerBehavior")
                    val behavior = mixerBehaviorMethod.invoke(currentAttr) as? Int
                    if (behavior == 1) { // MIXER_BEHAVIOR_BIT_PERFECT = 1
                        isBitPerfectActive = true
                    }
                }
            } catch (_: Exception) {}
        }

        val nativeSampleRate = getNativeSampleRate()
        val nativeFrames = getNativeFramesPerBuffer()

        val availableList = mutableListOf<Map<String, Any?>>()
        val currentDevId = selectedDeviceId ?: activeDevice?.id
        for (device in devices) {
            val dRates = device.sampleRates.toList().filter { it > 0 }
            var dBitDepth = 16
            for (encoding in device.encodings) {
                when (encoding) {
                    AudioFormat.ENCODING_PCM_FLOAT -> dBitDepth = maxOf(dBitDepth, 32)
                    AudioFormat.ENCODING_PCM_24BIT_PACKED -> dBitDepth = maxOf(dBitDepth, 24)
                    AudioFormat.ENCODING_PCM_32BIT -> dBitDepth = maxOf(dBitDepth, 32)
                }
            }
            val dName = device.productName.toString().ifBlank { getDeviceTypeName(device.type) }
            val isCurrent = (device.id == currentDevId)
            availableList.add(mapOf(
                "id" to device.id,
                "name" to dName,
                "type" to device.type,
                "typeName" to getDeviceTypeName(device.type),
                "isCurrent" to isCurrent,
                "sampleRates" to (if (dRates.isNotEmpty()) dRates else listOf(44100, 48000)),
                "maxBitDepth" to dBitDepth
            ))
        }

        result["deviceName"] = deviceName
        result["isUsbDac"] = isUsb
        result["sampleRate"] = if (targetSampleRate > 0) targetSampleRate else (if (isUsb) maxSampleRate else nativeSampleRate)
        result["nativeSampleRate"] = nativeSampleRate
        result["nativeFramesPerBuffer"] = nativeFrames
        result["bitDepth"] = if (targetBitDepth > 0) targetBitDepth else bitDepth
        result["isBitPerfectActive"] = isBitPerfectActive || bitPerfectRequested
        result["isBitPerfectSupported"] = true
        result["supportedSampleRates"] = if (sampleRates.isNotEmpty()) sampleRates else listOf(44100, 48000, 88200, 96000, 176400, 192000, 384000)
        result["availableDevices"] = availableList
        result["targetSampleRate"] = targetSampleRate
        result["targetBitDepth"] = targetBitDepth

        return result
    }

    private fun getNativeSampleRate(): Int {
        if (audioManager == null) return 48000
        val nativeRate = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
        return nativeRate?.toIntOrNull() ?: 48000
    }

    private fun getNativeFramesPerBuffer(): Int {
        if (audioManager == null) return 192
        val frames = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
        return frames?.toIntOrNull() ?: 192
    }

    private fun getDeviceTypeName(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in Speaker"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth (A2DP)"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth (SCO)"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB Audio Device"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Headset"
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB Accessory"
            AudioDeviceInfo.TYPE_DOCK -> "Audio Dock"
            AudioDeviceInfo.TYPE_HDMI -> "HDMI Output"
            AudioDeviceInfo.TYPE_HDMI_ARC -> "HDMI (ARC)"
            AudioDeviceInfo.TYPE_HDMI_EARC -> "HDMI (eARC)"
            AudioDeviceInfo.TYPE_LINE_ANALOG -> "Line Out"
            AudioDeviceInfo.TYPE_LINE_DIGITAL -> "Digital Line Out"
            AudioDeviceInfo.TYPE_AUX_LINE -> "AUX Line"
            else -> "Audio Output"
        }
    }
}
