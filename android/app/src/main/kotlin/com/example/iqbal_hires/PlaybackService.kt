package com.example.iqbal_hires

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaSession
import com.squareup.picasso.Picasso
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class PlaybackService : Service() {
    private var mediaSession: MediaSession? = null
    private var player: Player? = null
    
    private var currentTitle = ""
    private var currentArtist = ""
    private var currentArtUrl = ""

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "iqbal_hires_playback"
        
        var instance: PlaybackService? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        android.util.Log.d("PlaybackService", "✅ PlaybackService created")
    }
    
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d("PlaybackService", "✅ PlaybackService onStartCommand")
        
        // Show initial placeholder notification to keep service alive
        showPlaceholderNotification()
        
        return START_STICKY
    }
    
    private fun showPlaceholderNotification() {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Iqbal Hires")
            .setContentText("Ready to play")
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            android.util.Log.d("PlaybackService", "✅ Initial foreground notification shown")
        } catch (e: Exception) {
            android.util.Log.e("PlaybackService", "❌ Failed to show placeholder notification: ${e.message}")
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Music Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Media playback controls"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            android.util.Log.d("PlaybackService", "✅ Notification channel created")
        }
    }
    
    fun setPlayer(exoPlayer: Player) {
        this.player = exoPlayer
        
        // Create MediaSession
        mediaSession = MediaSession.Builder(this, exoPlayer)
            .build()
            
        android.util.Log.d("PlaybackService", "✅ Player and MediaSession set")
    }
    
    fun updateMetadata(title: String, artist: String, artUrl: String) {
        currentTitle = title
        currentArtist = artist
        currentArtUrl = artUrl
        
        android.util.Log.d("PlaybackService", "🔔 updateMetadata: $title - $artist")
        
        // Load album art and show notification
        CoroutineScope(Dispatchers.IO).launch {
            val albumArt = try {
                if (artUrl.isNotEmpty()) {
                    Picasso.get().load(artUrl).get()
                } else null
            } catch (e: Exception) {
                android.util.Log.e("PlaybackService", "Failed to load album art: ${e.message}")
                null
            }
            
            withContext(Dispatchers.Main) {
                showNotification(albumArt)
            }
        }
    }
    
    private fun showNotification(albumArt: Bitmap?) {
        val isPlaying = player?.isPlaying ?: false
        
        val playPauseAction = if (isPlaying) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                "Pause",
                createActionPendingIntent("pause")
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                "Play",
                createActionPendingIntent("play")
            )
        }
        
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setSubText("Iqbal Hires")
            .setLargeIcon(albumArt)
            .addAction(playPauseAction)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setOngoing(true)
        
        // Add MediaStyle if MediaSession is available
        mediaSession?.let { session ->
            notificationBuilder.setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setMediaSession(session.sessionCompatToken)
                    .setShowActionsInCompactView(0)
            )
        }
        
        val notification = notificationBuilder.build()
        
        android.util.Log.d("PlaybackService", "📢 Starting foreground with notification")
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            android.util.Log.d("PlaybackService", "✅ Foreground notification shown!")
        } catch (e: Exception) {
            android.util.Log.e("PlaybackService", "❌ Failed to start foreground: ${e.message}")
        }
    }
    
    private fun createActionPendingIntent(action: String): PendingIntent {
        val intent = Intent(this, PlaybackService::class.java).apply {
            this.action = action
        }
        return PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun onDestroy() {
        mediaSession?.release()
        instance = null
        super.onDestroy()
        android.util.Log.d("PlaybackService", "✅ PlaybackService destroyed")
    }
}
