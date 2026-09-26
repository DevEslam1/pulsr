package com.pulsr.music

import android.content.Context
import android.media.audiofx.AudioEffect
import android.os.Build
import android.util.Log
import java.util.UUID

/**
 * Controller for detecting and best-effort disabling system/OEM audio effects
 * (such as Dolby Atmos, DAP, Samsung SoundAlive, Dirac, Moto Audio).
 *
 * Status reporting is strictly honest:
 * - "bypassed": Successfully disabled or natively bypassed on output-mix session.
 * - "active": Detected and running in the output chain.
 * - "unknown": Present but status could not be affirmatively determined.
 * - "unsupportedDevice": No recognized system effects or OEM blocked session-0 access.
 */
class SystemAudioEffectsController(private val context: Context) {

    companion object {
        private const val TAG = "SystemAudioEffects"

        // Known vendor Dolby / OEM effect UUIDs and name signatures
        val KNOWN_VENDOR_EFFECTS = listOf(
            // Dolby Atmos / DAP UUIDs
            VendorEffectSignature("Dolby Atmos / DAP (Universal)", UUID.fromString("46d279d0-fc77-11e4-aae0-0002a5d5c51b"), "dolby"),
            VendorEffectSignature("Dolby DAP (Alternative)", UUID.fromString("9d49200e-2374-11e8-b467-0ed5f89f718b"), "dap"),
            // Samsung SoundAlive / Atmos
            VendorEffectSignature("Samsung SoundAlive", UUID.fromString("c2e5d5f0-94bd-4763-afae-4e12d633f8b9"), "soundalive"),
            // OnePlus / Oppo Dirac Sound
            VendorEffectSignature("Dirac Sound Research", UUID.fromString("e0e6539b-1781-7261-676f-6f7974656368"), "dirac"),
            // Motorola Moto Audio
            VendorEffectSignature("Motorola Moto Audio", UUID.fromString("37cc2c00-dddd-11db-8577-0002a5d5c51b"), "motoaudio"),
            // Generic fallback keywords: "dolby", "atmos", "dap", "dirac", "soundalive", "waves"
            VendorEffectSignature("Generic Dolby/Vendor Match", null, "atmos")
        )
    }

    data class VendorEffectSignature(
        val label: String,
        val uuid: UUID?,
        val keyword: String
    )

    enum class Status(val value: String) {
        BYPASSED("bypassed"),
        PARTIALLY_BYPASSED("partiallyBypassed"),
        ACTIVE("active"),
        UNKNOWN("unknown"),
        UNSUPPORTED_DEVICE("unsupportedDevice");

        companion object {
            fun fromString(s: String): Status {
                return entries.firstOrNull { it.value.equals(s, ignoreCase = true) } ?: UNKNOWN
            }
        }
    }

    enum class Policy(val value: String) {
        AUTO("auto"),
        TRY_DISABLE("tryDisable"),
        LEAVE_ON("leaveOn");

        companion object {
            fun fromString(s: String): Policy {
                return entries.firstOrNull { it.value.equals(s, ignoreCase = true) } ?: AUTO
            }
        }
    }

    private var currentStatus: Status = Status.UNKNOWN
    private var currentPolicy: Policy = Policy.AUTO
    private var detectedBundles: MutableList<String> = mutableListOf()
    private var partiallyBypassedEffects: MutableList<String> = mutableListOf()
    private var managedEffects: MutableList<AudioEffect> = mutableListOf()

    fun getStatus(): Status = currentStatus
    fun getDetectedBundles(): List<String> = detectedBundles.toList()
    fun getPartiallyBypassedEffects(): List<String> = partiallyBypassedEffects.toList()

    /**
     * Query audio effects installed in the Android HAL / AudioFlinger.
     */
    fun detect(): Map<String, Any?> {
        detectedBundles.clear()
        try {
            val descriptors = AudioEffect.queryEffects() ?: emptyArray()
            for (desc in descriptors) {
                val name = desc.name ?: ""
                val implementor = desc.implementor ?: ""
                val typeUuid = desc.type
                val uuid = desc.uuid

                for (vendor in KNOWN_VENDOR_EFFECTS) {
                    val matchKeyword = vendor.keyword.isNotEmpty() &&
                            (name.contains(vendor.keyword, ignoreCase = true) ||
                             implementor.contains(vendor.keyword, ignoreCase = true))
                    val matchUuid = vendor.uuid != null &&
                            (typeUuid == vendor.uuid || uuid == vendor.uuid)

                    if (matchKeyword || matchUuid) {
                        val descriptorInfo = "$name ($implementor)"
                        if (!detectedBundles.contains(descriptorInfo)) {
                            detectedBundles.add(descriptorInfo)
                        }
                    }
                }
            }

            currentStatus = if (detectedBundles.isNotEmpty()) {
                val disabledCount = managedEffects.count { !it.enabled }
                when {
                    disabledCount == 0 -> {
                        if (managedEffects.isNotEmpty() && managedEffects.all { it.enabled }) Status.ACTIVE
                        else if (currentStatus == Status.BYPASSED || currentStatus == Status.PARTIALLY_BYPASSED || currentStatus == Status.ACTIVE) currentStatus
                        else Status.UNKNOWN
                    }
                    disabledCount < detectedBundles.size -> Status.PARTIALLY_BYPASSED
                    else -> Status.BYPASSED
                }
            } else {
                Status.UNSUPPORTED_DEVICE
            }
        } catch (e: Exception) {
            Log.w(TAG, "AudioEffect.queryEffects failed gracefully: ${e.message}")
            currentStatus = Status.UNSUPPORTED_DEVICE
        }

        return mapOf(
            "status" to currentStatus.value,
            "detectedBundles" to detectedBundles,
            "partiallyBypassedEffects" to partiallyBypassedEffects,
            "hasDolbyOrVendor" to (detectedBundles.isNotEmpty())
        )
    }

    /**
     * Apply policy: "auto", "tryDisable", "leaveOn".
     * @param isHiResOrBitPerfect true when audio is in Hi-Res or Bit-Perfect mode (where Auto attempts disable)
     */
    fun applyPolicy(policyStr: String, isHiResOrBitPerfect: Boolean = false): Status {
        currentPolicy = Policy.fromString(policyStr)

        if (detectedBundles.isEmpty()) {
            detect()
        }

        if (detectedBundles.isEmpty()) {
            currentStatus = Status.UNSUPPORTED_DEVICE
            return currentStatus
        }

        val shouldDisable = when (currentPolicy) {
            Policy.TRY_DISABLE -> true
            Policy.LEAVE_ON -> false
            Policy.AUTO -> isHiResOrBitPerfect
        }

        if (shouldDisable) {
            currentStatus = attemptDisableSession0()
        } else {
            releaseManagedEffects()
            currentStatus = Status.ACTIVE
        }

        return currentStatus
    }

    /**
     * Best-effort attach to session 0 (AUDIO_SESSION_OUTPUT_MIX) and disable.
     */
    private fun attemptDisableSession0(): Status {
        releaseManagedEffects()
        partiallyBypassedEffects.clear()

        var disableSuccessCount = 0
        try {
            val descriptors = AudioEffect.queryEffects() ?: emptyArray()
            for (desc in descriptors) {
                val name = desc.name ?: ""
                val implementor = desc.implementor ?: ""

                val isMatched = KNOWN_VENDOR_EFFECTS.any { vendor ->
                    (vendor.keyword.isNotEmpty() &&
                     (name.contains(vendor.keyword, ignoreCase = true) ||
                      implementor.contains(vendor.keyword, ignoreCase = true))) ||
                    (vendor.uuid != null && (desc.type == vendor.uuid || desc.uuid == vendor.uuid))
                }

                if (isMatched && desc.type != null && desc.uuid != null) {
                    val descriptorInfo = "$name ($implementor)"
                    try {
                        val effect = createEffectSafely(desc.type, desc.uuid, 0, 0)
                        if (effect != null && effect.hasControl()) {
                            effect.enabled = false
                            managedEffects.add(effect)
                            disableSuccessCount++
                            if (!partiallyBypassedEffects.contains(descriptorInfo)) {
                                partiallyBypassedEffects.add(descriptorInfo)
                            }
                        } else {
                            effect?.release()
                        }
                    } catch (secEx: SecurityException) {
                        Log.w(TAG, "Lacking permission or OEM blocked session 0 access for ${desc.name}: ${secEx.message}")
                    } catch (illEx: IllegalStateException) {
                        Log.w(TAG, "Illegal state modifying session 0 effect for ${desc.name}: ${illEx.message}")
                    } catch (unsuppEx: UnsupportedOperationException) {
                        Log.w(TAG, "Unsupported effect attach on this hardware: ${unsuppEx.message}")
                    } catch (e: Exception) {
                        Log.w(TAG, "AudioEffect attach caught exception gracefully: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "attemptDisableSession0 query failed: ${e.message}")
        }

        return when {
            disableSuccessCount == 0 -> {
                if (detectedBundles.isNotEmpty()) Status.ACTIVE else Status.UNSUPPORTED_DEVICE
            }
            disableSuccessCount < detectedBundles.size -> {
                Status.PARTIALLY_BYPASSED
            }
            else -> {
                Status.BYPASSED
            }
        }
    }

    /**
     * Release all held AudioEffect session references to restore original OEM state.
     */
    fun release() {
        releaseManagedEffects()
    }

    private fun createEffectSafely(type: UUID, uuid: UUID, priority: Int = 0, audioSession: Int = 0): AudioEffect? {
        return try {
            val constructor = AudioEffect::class.java.getDeclaredConstructor(
                UUID::class.java,
                UUID::class.java,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType
            )
            constructor.isAccessible = true
            constructor.newInstance(type, uuid, priority, audioSession) as? AudioEffect
        } catch (e: NoSuchMethodException) {
            Log.d(TAG, "AudioEffect reflection constructor not found: ${e.message}")
            null
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException accessing AudioEffect constructor: ${e.message}")
            null
        } catch (e: Exception) {
            Log.d(TAG, "Cannot create AudioEffect via reflection: ${e.message}")
            null
        }
    }

    private fun releaseManagedEffects() {
        for (effect in managedEffects) {
            try {
                effect.release()
            } catch (_: Exception) {}
        }
        managedEffects.clear()
        partiallyBypassedEffects.clear()
    }
}
