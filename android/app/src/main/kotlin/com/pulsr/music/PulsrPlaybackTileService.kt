package com.pulsr.music

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.KeyEvent
import androidx.annotation.RequiresApi

/**
 * Quick Settings Tile allowing one-tap play/pause toggle from the notification shade.
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

            // Visually toggle tile
            val tile = qsTile ?: return
            tile.state = if (tile.state == Tile.STATE_ACTIVE) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
            tile.updateTile()
        } catch (_: Exception) {}
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        tile.label = getString(R.string.tile_playback_label)
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()
    }
}
