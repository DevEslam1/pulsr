package com.example.pulsr

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

class NowPlayingWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.widget_now_playing).apply {
                val title = widgetData.getString("title", "No song playing")
                val artist = widgetData.getString("artist", "Pulsr Music")
                val isPlaying = widgetData.getBoolean("isPlaying", false)
                val artworkPath = widgetData.getString("artwork", null)

                setTextViewText(R.id.widget_title, if (title.isNullOrEmpty()) "No song playing" else title)
                setTextViewText(R.id.widget_artist, if (artist.isNullOrEmpty()) "Pulsr Music" else artist)

                if (isPlaying) {
                    setImageViewResource(R.id.btn_play_pause, android.R.drawable.ic_media_pause)
                } else {
                    setImageViewResource(R.id.btn_play_pause, android.R.drawable.ic_media_play)
                }

                if (!artworkPath.isNullOrEmpty()) {
                    try {
                        val bitmap = BitmapFactory.decodeFile(artworkPath)
                        if (bitmap != null) {
                            setImageViewBitmap(R.id.widget_artwork, bitmap)
                        } else {
                            setImageViewResource(R.id.widget_artwork, R.mipmap.ic_launcher)
                        }
                    } catch (e: Exception) {
                        setImageViewResource(R.id.widget_artwork, R.mipmap.ic_launcher)
                    }
                } else {
                    setImageViewResource(R.id.widget_artwork, R.mipmap.ic_launcher)
                }

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)

                val playPauseIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("pulsrWidget://play_pause")
                )
                setOnClickPendingIntent(R.id.btn_play_pause, playPauseIntent)

                val prevIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("pulsrWidget://prev")
                )
                setOnClickPendingIntent(R.id.btn_prev, prevIntent)

                val nextIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("pulsrWidget://next")
                )
                setOnClickPendingIntent(R.id.btn_next, nextIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
