package com.pulsr.music

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
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
    private var lastBitPerfectReason: String? = null
    private var selectedDeviceId: Int? = null
    private var targetSampleRate: Int = 0
    private var targetBitDepth: Int = 0
    private var audioDeviceCallback: AudioDeviceCallback? = null
    private var usbReceiver: BroadcastReceiver? = null
    // Cached reflection methods to avoid thrashing on every getAudioOutputDetails()
    private var cachedMixerBehaviorMethod: java.lang.reflect.Method? = null
    private var cachedGetSupportedMixerMethod: java.lang.reflect.Method? = null
    private var cachedSetMixerMethod: java.lang.reflect.Method? = null
    private var cachedClearMixerMethod: java.lang.reflect.Method? = null
    private var cachedGetMixerMethod: java.lang.reflect.Method? = null

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
                context.registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
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
        val info = try { getAudioOutputDetails() } catch (e: Exception) { return }
        // Don't emit if no Dart listener yet; latest info will be sent on onListen
        val sink = eventSink ?: return
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try {
                sink.success(info)
            } catch (_: Exception) {}
        }
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
            "setBitPerfectModeDetailed" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                bitPerfectRequested = enabled
                val success = applyBitPerfectMode(enabled)
                notifyDeviceChange()
                result.success(mapOf("success" to success, "reason" to lastBitPerfectReason))
            }
            "setOutputDevice" -> {
                val deviceId = call.argument<Int>("deviceId")
                selectedDeviceId = deviceId
                var success = false
                var actualError: String? = null
                if (audioManager != null && deviceId != null) {
                    val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    val target = devices.firstOrNull { it.id == deviceId }
                    if (target != null) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                if (Build.VERSION.SDK_INT >= 33) {
                                    try {
                                        val strat = 0
                                        val m = AudioManager::class.java.getMethod("setPreferredDeviceForStrategy", Int::class.javaPrimitiveType, AudioDeviceInfo::class.java)
                                        success = (m.invoke(audioManager, strat, target) as? Boolean) ?: false
                                        if (!success) actualError = "setPreferredDeviceForStrategy returned false"
                                    } catch (e: Exception) { actualError = e.message }
                                }
                                if (!success && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    success = audioManager.setCommunicationDevice(target)
                                    if (!success && actualError == null) actualError = "setCommunicationDevice returned false"
                                }
                            }
                        } catch (e: Exception) { actualError = e.message }
                    } else {
                        actualError = "device not found"
                    }
                } else {
                    actualError = "audioManager or deviceId null"
                }
                notifyDeviceChange()
                // Return actual success; don't lie when routing failed
                if (!success && actualError != null) {
                    result.success(mapOf("success" to false, "error" to actualError))
                } else {
                    result.success(success)
                }
            }
            "clearOutputDevice" -> {
                selectedDeviceId = null
                if (audioManager != null) {
                    try {
                        if (Build.VERSION.SDK_INT >= 33) {
                            val strat = 0
                            val m = AudioManager::class.java.getMethod("clearPreferredDeviceForStrategy", Int::class.javaPrimitiveType)
                            m.invoke(audioManager, strat)
                        }
                    } catch (_: Exception) {}
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) audioManager.clearCommunicationDevice()
                    } catch (_: Exception) {}
                }
                notifyDeviceChange()
                result.success(true)
            }
            "getUsbDacCapabilities" -> {
            val (uac, label) = probeUsbDac()
            result.success(mapOf("usbAudioClass" to uac, "usbDacLabel" to label))
        }
        "getDirectCapabilities" -> {
            result.success(mapOf("directFormats" to probeDirectFormats()))
        }
        "setTargetOutputFormat", "configureTargetAudio" -> {
                val sampleRate = call.argument<Int>("sampleRate") ?: 0
                val bitDepth = call.argument<Int>("bitDepth") ?: 0
                targetSampleRate = sampleRate
                targetBitDepth = bitDepth
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
        try { methodChannel.setMethodCallHandler(null) } catch (_: Exception) {}
        try { eventChannel.setStreamHandler(null) } catch (_: Exception) {}
        eventSink = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioManager != null && audioDeviceCallback != null) {
            try { audioManager.unregisterAudioDeviceCallback(audioDeviceCallback) } catch (_: Exception) {}
            audioDeviceCallback = null
        }
        if (usbReceiver != null) {
            try {
                context.unregisterReceiver(usbReceiver)
            } catch (_: Exception) {
                try { context.unregisterReceiver(usbReceiver) } catch (_: Exception) {}
            }
            usbReceiver = null
        }
    }

    private fun isBitPerfectSupportedOnPlatform(): Boolean {
        // USB bit-perfect requires API 34 mixer attributes, but wired direct is available from API 23+
        if (Build.VERSION.SDK_INT >= 34) return true
        // Wired direct fallback: check if any output advertises direct high-res capability
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioManager != null) {
            try {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                for (d in devices) {
                    if (d.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || d.type == AudioDeviceInfo.TYPE_WIRED_HEADSET) {
                        // Direct if supports >48k or FLOAT/24-bit
                        val hasHiRes = (d.sampleRates.any { it > 48000 }) ||
                            d.encodings.contains(AudioFormat.ENCODING_PCM_FLOAT) ||
                            d.encodings.contains(AudioFormat.ENCODING_PCM_24BIT_PACKED)
                        if (hasHiRes) return true
                    }
                }
            } catch (_: Exception) {}
        }
        return false
    }

    private fun isDirectSupportedForDevice(device: AudioDeviceInfo?): Boolean {
        if (device == null) return false
        // Bluetooth is never bit-perfect (transcoded)
        if (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) return false
        // Check encodings for direct-capable formats
        val hasDirectEncoding = device.encodings.contains(AudioFormat.ENCODING_PCM_FLOAT) ||
            device.encodings.contains(AudioFormat.ENCODING_PCM_24BIT_PACKED) ||
            device.encodings.contains(AudioFormat.ENCODING_PCM_32BIT)
        val hasHiResRate = device.sampleRates.any { it >= 88200 }
        // API 29+ can query directly
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                val fmt = AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_FLOAT).setSampleRate(96000).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build()
                val attr = android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_MEDIA).setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC).build()
                val supported = AudioTrack.isDirectPlaybackSupported(fmt, attr)
                if (supported) return true
            } catch (_: Exception) {}
        }
        return hasDirectEncoding || hasHiResRate
    }

    private fun getMixerBehaviorCached(attr: Any): Int? {
        return try {
            var m = cachedMixerBehaviorMethod
            if (m == null || m.declaringClass != attr.javaClass) {
                m = attr.javaClass.getMethod("getMixerBehavior")
                cachedMixerBehaviorMethod = m
            }
            m.invoke(attr) as? Int
        } catch (_: Exception) { null }
    }

    private fun applyBitPerfectMode(enabled: Boolean): Boolean {
        if (audioManager == null) {
            lastBitPerfectReason = "audio_manager_unavailable"
            return false
        }
        // Bluetooth explicitly not supported — transcoded
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val activeBt = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
        val usbDevice = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET }
        val wiredDevice = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET }

        // If Bluetooth is the active output and no USB/wired present, fail with clear reason
        if (activeBt != null && usbDevice == null && wiredDevice == null) {
            lastBitPerfectReason = "bluetooth_transcoded"
            if (enabled) return false
        }

        // USB path via AudioMixerAttributes (API 34) — true exclusive
        if (usbDevice != null) {
            if (Build.VERSION.SDK_INT < 34) {
                lastBitPerfectReason = "requires_android_14_for_usb"
                return false
            }
            return try {
                var getSupported = cachedGetSupportedMixerMethod
                if (getSupported == null) {
                    getSupported = AudioManager::class.java.getMethod("getSupportedAudioMixerAttributes", AudioDeviceInfo::class.java)
                    cachedGetSupportedMixerMethod = getSupported
                }
                val supportedAttributes = getSupported.invoke(audioManager, usbDevice) as? List<*> ?: emptyList<Any>()
                if (supportedAttributes.isEmpty()) {
                    lastBitPerfectReason = "no_supported_mixer_attributes"
                    return false
                }
                if (enabled) {
                    var selectedAttr: Any? = null
                    for (attr in supportedAttributes) {
                        if (attr != null) {
                            val behavior = getMixerBehaviorCached(attr)
                            if (behavior == 1) { selectedAttr = attr; break }
                        }
                    }
                    if (selectedAttr == null) selectedAttr = supportedAttributes.first()
                    val mixerAttrClass = Class.forName("android.media.AudioMixerAttributes")
                    var setM = cachedSetMixerMethod
                    if (setM == null) {
                        setM = AudioManager::class.java.getMethod("setAudioMixerAttributes", AudioDeviceInfo::class.java, mixerAttrClass)
                        cachedSetMixerMethod = setM
                    }
                    val ok = (setM.invoke(audioManager, usbDevice, selectedAttr) as? Boolean) ?: false
                    lastBitPerfectReason = if (ok) null else "set_mixer_attributes_failed"
                    ok
                } else {
                    var clearM = cachedClearMixerMethod
                    if (clearM == null) {
                        clearM = AudioManager::class.java.getMethod("clearAudioMixerAttributes", AudioDeviceInfo::class.java)
                        cachedClearMixerMethod = clearM
                    }
                    val ok = (clearM.invoke(audioManager, usbDevice) as? Boolean) ?: false
                    lastBitPerfectReason = null
                    ok
                }
            } catch (e: NoSuchMethodException) {
                lastBitPerfectReason = "reflection_method_not_found"
                Log.w(TAG, "Bit-perfect API not available on this device: ${e.message}")
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try { eventSink?.error("BIT_PERFECT_NOT_AVAILABLE", e.message, null) } catch (_: Exception) {}
                }
                false
            } catch (e: ClassNotFoundException) {
                lastBitPerfectReason = "audio_mixer_class_not_found"
                Log.w(TAG, "AudioMixerAttributes class not found: ${e.message}")
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try { eventSink?.error("AUDIO_MIXER_CLASS_NOT_FOUND", e.message, null) } catch (_: Exception) {}
                }
                false
            } catch (e: Throwable) {
                lastBitPerfectReason = "unknown_error_${e.message}"
                Log.w(TAG, "Bit-perfect mode failed: ${e.message}")
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try { eventSink?.error("BIT_PERFECT_FAILED", e.message, null) } catch (_: Exception) {}
                }
                false
            }
        }

        // Wired direct fallback — not true mixer bypass but direct/offload path (bit-perfect for wire)
        if (wiredDevice != null) {
            if (enabled) {
                if (isDirectSupportedForDevice(wiredDevice)) {
                    lastBitPerfectReason = null
                    return true // Direct will be enforced via AudioTrack preferredDevice path (notifyDeviceChange reflects it)
                } else {
                    lastBitPerfectReason = "wired_direct_not_supported"
                    return false
                }
            } else {
                lastBitPerfectReason = null
                return true
            }
        }

        if (enabled) {
            lastBitPerfectReason = "no_usb_device"
            return false
        }
        lastBitPerfectReason = null
        return true
    }

    /** Phase 4: enumerate USB audio devices and report the advertised UAC
     * version + label (diagnostics only - never claims native-DSD support). */
    private fun probeUsbDac(): Pair<Int, String?> {
        return try {
            val usbAudioDevice = usbManager?.deviceList?.values?.firstOrNull { device ->
                (0 until device.interfaceCount).any {
                    val cls = device.getInterface(it).interfaceClass
                    cls == UsbConstants.USB_CLASS_AUDIO || cls == 0xFF // vendor-specific UAC
                }
            } ?: return Pair(UsbDacDiagnostics.UAC_NONE, null)
            val label = listOfNotNull(usbAudioDevice.manufacturerName, usbAudioDevice.productName)
                .joinToString(" ").trim().ifEmpty { null }
            val interfacePairs = (0 until usbAudioDevice.interfaceCount).map {
                val iface = usbAudioDevice.getInterface(it)
                Pair(iface.interfaceSubclass, iface.interfaceProtocol)
            }
            val uac = try {
                UsbDacDiagnostics.uacVersionFromUsbInterfaces(interfacePairs)
            } catch (_: Throwable) {
                UsbDacDiagnostics.UAC_NONE
            }
            Pair(uac, label)
        } catch (_: Throwable) {
            Pair(UsbDacDiagnostics.UAC_NONE, null)
        }
    }

    /** Phase 4: per-format direct-playback capability probe (API 29+). */
    private fun probeDirectFormats(): List<Map<String, Any?>> {
        return UsbDacDiagnostics.directFormatsFor { tag, rate ->
            if (Build.VERSION.SDK_INT < 29) {
                null
            } else {
                try {
                    val encoding = when (tag) {
                        "float" -> AudioFormat.ENCODING_PCM_FLOAT
                        "24" -> AudioFormat.ENCODING_PCM_24BIT_PACKED
                        "32" -> AudioFormat.ENCODING_PCM_32BIT
                        else -> return@directFormatsFor null
                    }
                    val fmt = AudioFormat.Builder().setEncoding(encoding)
                        .setSampleRate(rate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build()
                    val attr = android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                    AudioTrack.isDirectPlaybackSupported(fmt, attr)
                } catch (_: Throwable) {
                    null
                }
            }
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
            result["usbAudioClass"] = UsbDacDiagnostics.UAC_NONE
            result["usbDacLabel"] = null
            result["directFormats"] = emptyList<Map<String, Any?>>()
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
            usbDevice != null -> getCleanDeviceName(usbDevice)
            activeDevice != null -> getCleanDeviceName(activeDevice)
            else -> "Default Audio Output"
        }

        val sampleRates = activeDevice?.sampleRates?.toList()?.filter { it > 0 } ?: listOf(44100, 48000)
        val maxSampleRate = sampleRates.maxOrNull() ?: 48000

        var bitDepth = 16
        var isDirectSupported = false
        var isOffloadSupported = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && activeDevice != null) {
            for (encoding in activeDevice.encodings) {
                when (encoding) {
                    AudioFormat.ENCODING_PCM_FLOAT -> {
                        bitDepth = maxOf(bitDepth, 32)
                        isDirectSupported = true
                    }
                    AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                        bitDepth = maxOf(bitDepth, 24)
                        isDirectSupported = true
                    }
                    AudioFormat.ENCODING_PCM_32BIT -> bitDepth = maxOf(bitDepth, 32)
                }
            }
            // Offload supported on Q+ if not Bluetooth
            isOffloadSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                activeDevice.type != AudioDeviceInfo.TYPE_BLUETOOTH_A2DP &&
                activeDevice.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            // More precise direct check
            isDirectSupported = isDirectSupportedForDevice(activeDevice) || isDirectSupported
        }

        var isBitPerfectActive = false
        if (Build.VERSION.SDK_INT >= 34 && isUsb && usbDevice != null) {
            try {
                var getM = cachedGetMixerMethod
                if (getM == null) {
                    getM = AudioManager::class.java.getMethod("getAudioMixerAttributes", AudioDeviceInfo::class.java)
                    cachedGetMixerMethod = getM
                }
                val currentAttr = getM.invoke(audioManager, usbDevice)
                if (currentAttr != null) {
                    val behavior = getMixerBehaviorCached(currentAttr)
                    if (behavior == 1) {
                        isBitPerfectActive = true
                    }
                }
            } catch (_: Exception) {}
        } else if (isDirectSupported && bitPerfectRequested && activeDevice != null && !isBluetoothActive(devices)) {
            // Wired direct counts as exclusive when requested and direct is supported
            isBitPerfectActive = true
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
            val dName = getCleanDeviceName(device)
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

        val isBluetooth = isBluetoothActive(devices)
        val activeType = when (activeDevice?.type) {
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "usb"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
            AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC, AudioDeviceInfo.TYPE_HDMI_EARC -> "hdmi"
            else -> "builtin"
        }
        // Final bit-perfect eligibility for all outputs
        val finalIsBitPerfectSupported = when {
            isUsb -> isBitPerfectSupportedOnPlatform()
            activeDevice?.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || activeDevice?.type == AudioDeviceInfo.TYPE_WIRED_HEADSET -> isDirectSupported
            else -> false
        } && !isBluetooth
        val finalIsBitPerfectActive = when {
            isBluetooth -> false
            isUsb -> isBitPerfectActive // only true if system actually granted it, not just requested
            isDirectSupported && bitPerfectRequested && (activeDevice?.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || activeDevice?.type == AudioDeviceInfo.TYPE_WIRED_HEADSET) -> true
            else -> isBitPerfectActive
        }
        val failureReason = when {
            isBluetooth -> "bluetooth_transcoded"
            finalIsBitPerfectActive -> null
            lastBitPerfectReason != null -> lastBitPerfectReason
            !finalIsBitPerfectSupported && isUsb -> "usb_not_supported"
            !finalIsBitPerfectSupported -> "direct_not_supported"
            else -> null
        }

        result["deviceName"] = deviceName
        result["isUsbDac"] = isUsb
        result["sampleRate"] = if (targetSampleRate > 0) targetSampleRate else (if (isUsb) maxSampleRate else nativeSampleRate)
        result["nativeSampleRate"] = nativeSampleRate
        result["nativeFramesPerBuffer"] = nativeFrames
        result["bitDepth"] = if (targetBitDepth > 0) targetBitDepth else bitDepth
        result["isBitPerfectActive"] = finalIsBitPerfectActive
        result["isBitPerfectSupported"] = finalIsBitPerfectSupported
        result["isDirectSupported"] = isDirectSupported
        result["isOffloadSupported"] = isOffloadSupported
        result["isBluetooth"] = isBluetooth
        result["activeDeviceType"] = activeType
        // Phase 4: USB Audio Class + direct-format diagnostics
        val (usbAudioClass, usbDacLabel) = probeUsbDac()
        result["usbAudioClass"] = usbAudioClass
        result["usbDacLabel"] = usbDacLabel
        result["directFormats"] = probeDirectFormats()
        result["supportedSampleRates"] = if (sampleRates.isNotEmpty()) sampleRates else listOf(44100, 48000, 88200, 96000, 176400, 192000, 384000)
        result["availableDevices"] = availableList
        result["targetSampleRate"] = targetSampleRate
        result["targetBitDepth"] = targetBitDepth
        result["bitPerfectFailureReason"] = failureReason

        return result
    }

    private fun isBluetoothActive(devices: Array<AudioDeviceInfo>): Boolean {
        return devices.any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO } &&
            devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET } == null &&
            devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET } == null
    }

    private fun getCleanDeviceName(device: AudioDeviceInfo): String {
        val prodName = device.productName.toString().trim()
        val isGenericModel = prodName.isBlank() ||
            prodName.startsWith("sdk_") ||
            prodName.contains("emulator", ignoreCase = true) ||
            prodName.equals(Build.PRODUCT, ignoreCase = true) ||
            prodName.equals(Build.MODEL, ignoreCase = true) ||
            prodName.equals(Build.DEVICE, ignoreCase = true)

        return when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone Speaker"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Phone Earpiece"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> {
                if (!isGenericModel) prodName else "Bluetooth Audio"
            }
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> {
                if (!isGenericModel) "$prodName (USB DAC)" else "USB Audio DAC"
            }
            AudioDeviceInfo.TYPE_LINE_ANALOG, AudioDeviceInfo.TYPE_AUX_LINE -> "Line Output (Aux)"
            AudioDeviceInfo.TYPE_LINE_DIGITAL -> "Digital Line Out"
            AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC, AudioDeviceInfo.TYPE_HDMI_EARC -> "HDMI Output"
            else -> if (!isGenericModel) prodName else getDeviceTypeName(device.type)
        }
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
