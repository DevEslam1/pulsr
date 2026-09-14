package com.pulsr.music

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

/**
 * Cast framework options for the dev/ytm flavors.
 *
 * Uses Google's public Default Media Receiver (`CC1AD845`), so no custom
 * receiver application id or Cast developer account is required for basic
 * audio playback. A custom receiver id can be substituted here if one is
 * registered later.
 *
 * This class lives in src/ytmEnabled so the prod "Pure" (offline) variant never
 * links Play Services Cast.
 */
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            .setReceiverApplicationId(DEFAULT_RECEIVER_APP_ID)
            .setResumeSavedSession(true)
            .setStopReceiverApplicationWhenEndingSession(true)
            .build()

    override fun getAdditionalSessionProviders(context: Context): MutableList<SessionProvider>? =
        null

    companion object {
        const val DEFAULT_RECEIVER_APP_ID = "CC1AD845"
    }
}
