package com.example.iqbal_hires

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import androidx.media3.common.Player
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.squareup.picasso.Picasso
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MediaNotificationManager(
    private val context: Context,
    private val player: Player,
    private val mediaSession: MediaSession
) {
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "iqbal_hires_media_channel"
        private const val CHANNEL_NAME = "Music Playback"
    }

    private val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private var currentTitle = ""
    private var currentArtist = ""
    private var albumArtUrl = ""

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Media playback controls"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun updateNotification(title: String, artist: String, artUrl: String) {
        currentTitle = title
        currentArtist = artist
        albumArtUrl = artUrl

        android.util.Log.d("MediaNotificationManager", "🔔 updateNotification called: title=$title, artist=$artist, artUrl=$artUrl")

        // Load album art in background
        CoroutineScope(Dispatchers.Default).launch {
            val albumArt = loadAlbumArt(artUrl)
            android.util.Log.d("MediaNotificationManager", "📷 Album art loaded: ${albumArt != null}")
            
            // Show notification on main thread
            CoroutineScope(Dispatchers.Main).launch {
                showNotification(albumArt)
            }
        }
    }

    private suspend fun loadAlbumArt(url: String): Bitmap? = withContext(Dispatchers.IO) {
        try {
            if (url.isNotEmpty()) {
                Picasso.get().load(url).get()
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun showNotification(albumArt: Bitmap?) {
        val playPauseAction = if (player.isPlaying) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                "Pause",
                createPendingIntent("pause")
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                "Play",
                createPendingIntent("play")
            )
        }

        android.util.Log.d("MediaNotificationManager", "🎨 Building notification: $currentTitle - $currentArtist")

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setSubText("Iqbal Hires")
            .setLargeIcon(albumArt)
            .addAction(playPauseAction)
            .setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setMediaSession(mediaSession.sessionCompatToken)
                    .setShowActionsInCompactView(0)
            )
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setContentIntent(createContentIntent())
            .build()

        android.util.Log.d("MediaNotificationManager", "📢 Posting notification with ID $NOTIFICATION_ID")
        notificationManager.notify(NOTIFICATION_ID, notification)
        android.util.Log.d("MediaNotificationManager", "✅ Notification posted successfully")
    }

    private fun createPendingIntent(action: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = "media_control_$action"
            putExtra("action", action)
        }
        return PendingIntent.getActivity(
            context,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createContentIntent(): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun hide() {
        notificationManager.cancel(NOTIFICATION_ID)
    }
}
