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

        val FRAMEWORK_EFFECT_TYPE_UUIDS: Set<UUID> = buildSet {
            add(AudioEffect.EFFECT_TYPE_EQUALIZER)
            add(AudioEffect.EFFECT_TYPE_BASS_BOOST)
            add(AudioEffect.EFFECT_TYPE_VIRTUALIZER)
            add(AudioEffect.EFFECT_TYPE_LOUDNESS_ENHANCER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                add(AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING)
            }
            add(AudioEffect.EFFECT_TYPE_PRESET_REVERB)
            add(AudioEffect.EFFECT_TYPE_ENV_REVERB)
            // Visualizer doesn't expose a public AudioEffect.EFFECT_TYPE_* constant.
            add(UUID.fromString("e46b26a0-dddd-11db-8afd-0002a5d5c51b"))
        }

        // Known vendor Dolby / OEM effect UUIDs and name signatures
        val KNOWN_VENDOR_EFFECTS = listOf(
            // Dolby Atmos / DAP UUIDs
            VendorEffectSignature("Dolby Atmos / DAP (Universal)", UUID.fromString("46d279d0-fc77-11e4-aae0-0002a5d5c51b"), "dolby"),
            VendorEffectSignature("Dolby DAP (Alternative)", UUID.fromString("9d49200e-2374-11e8-b467-0ed5f89f718b"), "dap"),
            // Samsung SoundAlive / Atmos
            VendorEffectSignature("Samsung SoundAlive", UUID.fromString("c2e5d5f0-94bd-4763-afae-4e12d633f8b9"), "soundalive"),
            // OnePlus / Oppo Dirac Sound
            VendorEffectSignature("Dirac Sound Research", UUID.fromString("e0e6539b-1781-7261-676f-6f7974656368"), "dirac"),
            // Motorola Moto Audio (implementor/name keyword match only; no stock type UUID)
            VendorEffectSignature("Motorola Moto Audio", null, "motoaudio"),
            // Generic fallback keywords: "dolby", "atmos", "dap", "dirac", "soundalive", "waves"
            VendorEffectSignature("Generic Dolby/Vendor Match", null, "atmos")
        )

        internal fun matchesVendorDescriptor(
            name: String,
            implementor: String,
            typeUuid: UUID?,
            effectUuid: UUID?,
        ): Boolean {
            val isFrameworkType = typeUuid != null && typeUuid in FRAMEWORK_EFFECT_TYPE_UUIDS
            val isFrameworkImpl = effectUuid != null && effectUuid in FRAMEWORK_EFFECT_TYPE_UUIDS
            return KNOWN_VENDOR_EFFECTS.any { vendor ->
                val matchKeyword = vendor.keyword.isNotEmpty() &&
                    (name.contains(vendor.keyword, ignoreCase = true) ||
                        implementor.contains(vendor.keyword, ignoreCase = true))
                val matchUuid = vendor.uuid != null &&
                    !isFrameworkType &&
                    !isFrameworkImpl &&
                    (typeUuid == vendor.uuid || effectUuid == vendor.uuid)
                matchKeyword || matchUuid
            }
        }
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

    internal interface ManagedEffectHandle {
        fun hasControl(): Boolean
        var enabled: Boolean
        fun release()
    }

    private data class ManagedEffect(
        val handle: ManagedEffectHandle,
        val priorEnabled: Boolean,
    )

    private fun AudioEffect.asHandle(): ManagedEffectHandle = object : ManagedEffectHandle {
        override fun hasControl(): Boolean = this@asHandle.hasControl()
        override var enabled: Boolean
            get() = this@asHandle.enabled
            set(value) {
                this@asHandle.enabled = value
            }
        override fun release() = this@asHandle.release()
    }

    private var currentStatus: Status = Status.UNKNOWN
    private var currentPolicy: Policy = Policy.AUTO
    private var detectedBundles: MutableList<String> = mutableListOf()
    private var partiallyBypassedEffects: MutableList<String> = mutableListOf()
    private var managedEffects: MutableList<ManagedEffect> = mutableListOf()

    fun getStatus(): Status = currentStatus
    fun getDetectedBundles(): List<String> = detectedBundles.toList()
    fun getPartiallyBypassedEffects(): List<String> = partiallyBypassedEffects.toList()

    /**
     * Applies the verdict implied by a detection result.
     *
     * `bundles` are the descriptors detection matched; the managed set is what
     * this controller actually silenced. A non-empty detection with no held
     * effect is ACTIVE (the OEM effect is running), a fully silenced set is
     * BYPASSED, and a partially silenced set is PARTIALLY_BYPASSED. BYPASSED is
     * therefore never inferred from detection alone.
     */
    private fun applyDetectionResult(bundles: List<String>): Status {
        currentStatus = when {
            bundles.isEmpty() -> Status.UNSUPPORTED_DEVICE
            managedEffects.isEmpty() -> Status.ACTIVE
            partiallyBypassedEffects.isEmpty() -> Status.BYPASSED
            else -> Status.PARTIALLY_BYPASSED
        }
        return currentStatus
    }

    /**
     * Test seam: runs the post-detection verdict as if [bundles] had been found.
     * Uses the production [applyDetectionResult] so the regression covers the real
     * decision, not a copy of it.
     */
    internal fun applyDetectionResultForTesting(bundles: List<String>): Status {
        detectedBundles.clear()
        detectedBundles.addAll(bundles)
        return applyDetectionResult(bundles)
    }

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

                if (matchesVendorDescriptor(name, implementor, typeUuid, uuid)) {
                    val descriptorInfo = "$name ($implementor)"
                    if (!detectedBundles.contains(descriptorInfo)) {
                        detectedBundles.add(descriptorInfo)
                    }
                }
            }

            // Detection only refreshes what exists on the device. The bypass
            // verdict belongs to applyPolicy(), which knows whether every matched
            // descriptor could actually be controlled; counting held effects
            // against the deduped display list reported PARTIALLY_BYPASSED for a
            // device we had silenced completely (and vice versa).
            //
            // Item 6: the verdict must be refreshed for a NON-empty result too. It
            // used to be written only when no bundle was found, so a stale BYPASSED
            // survived a reboot, a system update or an OEM turn-off forever. Never
            // report BYPASSED from detection alone: nothing is bypassed unless we
            // still hold a silenced effect.
            applyDetectionResult(detectedBundles);
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

        // Always re-detect: a stale non-empty list outlived a reboot, a system
        // update and an OEM effect being switched off, so the reported status
        // (and the "unverified" flag derived from it) could never recover.
        detect()

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

        // Count descriptors, not display bundles: detectedBundles is deduped by
        // "name (implementor)", so the two lists are not comparable.
        var matchedDescriptors = 0
        var silencedDescriptors = 0
        try {
            val descriptors = AudioEffect.queryEffects() ?: emptyArray()
            for (desc in descriptors) {
                val name = desc.name ?: ""
                val implementor = desc.implementor ?: ""

                val isMatched = matchesVendorDescriptor(name, implementor, desc.type, desc.uuid)

                if (isMatched && desc.type != null && desc.uuid != null) {
                    matchedDescriptors++
                    val descriptorInfo = "$name ($implementor)"
                    try {
                        val effect = createEffectSafely(desc.type, desc.uuid, 0, 0)
                        if (effect != null && effect.hasControl()) {
                            val priorEnabled = try { effect.enabled } catch (_: Exception) { false }
                            effect.enabled = false
                            if (!effect.enabled) {
                                managedEffects.add(ManagedEffect(effect.asHandle(), priorEnabled))
                                silencedDescriptors++
                            } else {
                                // Still processing: this is the honest content of
                                // the "partially bypassed" list.
                                effect.release()
                                if (!partiallyBypassedEffects.contains(descriptorInfo)) {
                                    partiallyBypassedEffects.add(descriptorInfo)
                                }
                            }
                        } else {
                            effect?.release()
                            if (!partiallyBypassedEffects.contains(descriptorInfo)) {
                                partiallyBypassedEffects.add(descriptorInfo)
                            }
                        }
                    } catch (secEx: SecurityException) {
                        Log.w(TAG, "Lacking permission or OEM blocked session 0 access for ${desc.name}: ${secEx.message}")
                        if (!partiallyBypassedEffects.contains(descriptorInfo)) {
                            partiallyBypassedEffects.add(descriptorInfo)
                        }
                    } catch (illEx: IllegalStateException) {
                        Log.w(TAG, "Illegal state modifying session 0 effect for ${desc.name}: ${illEx.message}")
                        if (!partiallyBypassedEffects.contains(descriptorInfo)) {
                            partiallyBypassedEffects.add(descriptorInfo)
                        }
                    } catch (unsuppEx: UnsupportedOperationException) {
                        Log.w(TAG, "Unsupported effect attach on this hardware: ${unsuppEx.message}")
                        if (!partiallyBypassedEffects.contains(descriptorInfo)) {
                            partiallyBypassedEffects.add(descriptorInfo)
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "AudioEffect attach caught exception gracefully: ${e.message}")
                        if (!partiallyBypassedEffects.contains(descriptorInfo)) {
                            partiallyBypassedEffects.add(descriptorInfo)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "attemptDisableSession0 query failed: ${e.message}")
        }

        return when {
            matchedDescriptors == 0 -> {
                if (detectedBundles.isNotEmpty()) Status.ACTIVE else Status.UNSUPPORTED_DEVICE
            }
            partiallyBypassedEffects.isEmpty() -> Status.BYPASSED
            silencedDescriptors > 0 -> Status.PARTIALLY_BYPASSED
            else -> Status.ACTIVE
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

    internal fun registerManagedEffectForTesting(handle: ManagedEffectHandle, priorEnabled: Boolean) {
        managedEffects.add(ManagedEffect(handle, priorEnabled))
    }

    private fun releaseManagedEffects() {
        for (managed in managedEffects) {
            try {
                if (managed.priorEnabled && managed.handle.hasControl()) {
                    managed.handle.enabled = true
                }
            } catch (_: Exception) {}
            try {
                managed.handle.release()
            } catch (_: Exception) {}
        }
        managedEffects.clear()
        partiallyBypassedEffects.clear()
    }
}
