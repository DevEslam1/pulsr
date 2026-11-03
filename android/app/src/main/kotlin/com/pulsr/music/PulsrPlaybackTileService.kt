package com.pulsr.music

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.KeyEvent
import androidx.annotation.RequiresApi

/**
 * Quick Settings Tile allowing one-tap play/pause toggle from the notification shade.
 *
 * The tile never guesses the new state optimistically: it renders the last
 * state written by the player. Call [PlaybackTileState.setPlaying] from the
 * player (a native hook is still required) and the system re-binds the tile.
 */
@RequiresApi(Build.VERSION_CODES.N)
class PulsrPlaybackTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        try {
            // Send standard Play/Pause key event to MediaButtonReceiver
            val keyDown = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setComponent(ComponentName(this@PulsrPlaybackTileService, "androidx.media.session.MediaButtonReceiver"))
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            }
            sendBroadcast(keyDown)

            val keyUp = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setComponent(ComponentName(this@PulsrPlaybackTileService, "androidx.media.session.MediaButtonReceiver"))
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            }
            sendBroadcast(keyUp)

            // Ask the system to re-bind the tile once the player publishes the
            // real state. No optimistic toggle here.
            PlaybackTileState.requestRefresh(this)
        } catch (_: Exception) {}
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        tile.label = getString(R.string.tile_playback_label)
        tile.state = if (PlaybackTileState.isPlaying(this)) {
            Tile.STATE_ACTIVE
        } else {
            Tile.STATE_INACTIVE
        }
        tile.updateTile()
    }
}

/** Persisted tile state, written by the playback owner. */
object PlaybackTileState {
    private const val PREFS = "pulsr_playback_tile"
    private const val KEY_PLAYING = "is_playing"

    fun isPlaying(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_PLAYING, false)

    fun setPlaying(context: Context, playing: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PLAYING, playing)
            .apply()
        requestRefresh(context)
    }

    fun requestRefresh(context: Context) {
        try {
            TileService.requestListeningState(
                context,
                ComponentName(context, PulsrPlaybackTileService::class.java)
            )
        } catch (_: Exception) {
        }
    }
}
