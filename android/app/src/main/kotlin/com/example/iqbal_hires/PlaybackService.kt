package com.example.iqbal_hires

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.ForwardingPlayer
import androidx.media3.exoplayer.ExoPlayer
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
    private var currentAlbumArt: Bitmap? = null
    
    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            android.util.Log.d("PlaybackService", "🎵 isPlaying changed: $isPlaying")
            // Update notification when play state changes
            if (currentTitle.isNotEmpty()) {
                showNotification(currentAlbumArt)
            }
        }
        
        override fun onPlaybackStateChanged(playbackState: Int) {
            android.util.Log.d("PlaybackService", "🎭 Playback state changed: $playbackState")
            // Update notification on state changes to keep it visible
            if (currentTitle.isNotEmpty() && playbackState != Player.STATE_IDLE) {
                showNotification(currentAlbumArt)
            }
        }
    }

    // Callback interface untuk komunikasi dengan ExoPlayerPlugin
    interface SkipCallback {
        fun onSkipNext()
        fun onSkipPrevious()
    }
    
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "iqbal_hires_playback"
        const val ACTION_PLAY = "play"
        const val ACTION_PAUSE = "pause"
        const val ACTION_NEXT = "next"
        const val ACTION_PREVIOUS = "previous"
        
        var instance: PlaybackService? = null
            private set
        
        var skipCallback: SkipCallback? = null
    }
    
    fun getPlayer(): Player? {
        return player
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        android.util.Log.d("PlaybackService", "✅ PlaybackService created")
    }
    
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        android.util.Log.d("PlaybackService", "✅ PlaybackService onStartCommand, action: ${intent?.action}")
        
        // Handle play/pause/skip actions from notification
        when (intent?.action) {
            ACTION_PLAY -> {
                android.util.Log.d("PlaybackService", "▶️ Play action received")
                player?.play()
            }
            ACTION_PAUSE -> {
                android.util.Log.d("PlaybackService", "⏸️ Pause action received")
                player?.pause()
            }
            ACTION_NEXT -> {
                android.util.Log.d("PlaybackService", "⏭️ Next action received")
                skipCallback?.onSkipNext()
            }
            ACTION_PREVIOUS -> {
                android.util.Log.d("PlaybackService", "⏮️ Previous action received")
                skipCallback?.onSkipPrevious()
            }
        }
        
        // START_NOT_STICKY: Don't restart service if killed by system
        return START_NOT_STICKY
    }
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        android.util.Log.d("PlaybackService", "📱 App swiped away - stopping playback")
        
        // Stop playback
        player?.stop()
        
        // Release MediaSession
        mediaSession?.release()
        mediaSession = null
        
        // Stop foreground and remove notification
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        
        super.onTaskRemoved(rootIntent)
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
        // If same player, do nothing
        if (this.player === exoPlayer && mediaSession != null) {
            android.util.Log.d("PlaybackService", "⚠️ Player already set, skipping")
            return
        }
        
        // Remove listener from old player if exists
        this.player?.removeListener(playerListener)
        
        // Release old MediaSession if exists
        mediaSession?.let {
            android.util.Log.d("PlaybackService", "🔄 Releasing old MediaSession")
            it.release()
            mediaSession = null
        }
        
        this.player = exoPlayer
        
        // Add listener to track playback state changes
        exoPlayer.addListener(playerListener)
        
        // Create MediaSession with unique ID using timestamp
        try {
            val forwardingPlayer = object : ForwardingPlayer(exoPlayer) {
                override fun hasNextMediaItem(): Boolean = true
                override fun hasPreviousMediaItem(): Boolean = true

                override fun seekToNextMediaItem() {
                    android.util.Log.d("PlaybackService", "⏭️ Intercepted seekToNextMediaItem from MediaSession")
                    skipCallback?.onSkipNext()
                }

                override fun seekToPreviousMediaItem() {
                    android.util.Log.d("PlaybackService", "⏮️ Intercepted seekToPreviousMediaItem from MediaSession")
                    skipCallback?.onSkipPrevious()
                }

                override fun seekToNext() {
                    android.util.Log.d("PlaybackService", "⏭️ Intercepted seekToNext from MediaSession")
                    skipCallback?.onSkipNext()
                }

                override fun seekToPrevious() {
                    android.util.Log.d("PlaybackService", "⏮️ Intercepted seekToPrevious from MediaSession")
                    skipCallback?.onSkipPrevious()
                }

                override fun getAvailableCommands(): Player.Commands {
                    return super.getAvailableCommands().buildUpon()
                        .add(Player.COMMAND_SEEK_TO_NEXT)
                        .add(Player.COMMAND_SEEK_TO_PREVIOUS)
                        .add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                        .add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                        .build()
                }
            }

            mediaSession = MediaSession.Builder(this, forwardingPlayer)
                .setId("HiresSession_${System.currentTimeMillis()}")
                .build()
            android.util.Log.d("PlaybackService", "✅ Player and MediaSession set")
        } catch (e: IllegalStateException) {
            android.util.Log.e("PlaybackService", "❌ MediaSession creation failed: ${e.message}")
            // Session ID conflict - try to continue without MediaSession
        }
    }
    
    fun updateMetadata(title: String, artist: String, artUrl: String) {
        currentTitle = title
        currentArtist = artist
        currentArtUrl = artUrl
        
        android.util.Log.d("PlaybackService", "🔔 updateMetadata: $title - $artist")

        // Keep MediaSession metadata in sync so quick settings media card
        // (including HyperOS control center) can show current song info.
        syncNowPlayingMetadata()
        
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
                currentAlbumArt = albumArt
                showNotification(albumArt)
            }
        }
    }

    private fun syncNowPlayingMetadata() {
        val exoPlayer = player as? ExoPlayer ?: return

        try {
            val metadataBuilder = MediaMetadata.Builder()
            if (currentTitle.isNotEmpty()) {
                metadataBuilder.setTitle(currentTitle)
            }
            if (currentArtist.isNotEmpty()) {
                metadataBuilder.setArtist(currentArtist)
            }
            if (currentArtUrl.isNotEmpty()) {
                metadataBuilder.setArtworkUri(Uri.parse(currentArtUrl))
            }

            val metadata = metadataBuilder.build()
            val currentIndex = exoPlayer.currentMediaItemIndex
            val currentItem = exoPlayer.currentMediaItem

            if (currentItem != null && currentIndex != -1) {
                val currentPosition = exoPlayer.currentPosition
                val playWhenReady = exoPlayer.playWhenReady

                val updatedItem = currentItem
                    .buildUpon()
                    .setMediaMetadata(metadata)
                    .build()

                exoPlayer.replaceMediaItem(currentIndex, updatedItem)

                if (currentPosition > 0) {
                    exoPlayer.seekTo(currentIndex, currentPosition)
                }
                exoPlayer.playWhenReady = playWhenReady

                android.util.Log.d(
                    "PlaybackService",
                    "✅ MediaItem metadata synced for quick settings: $currentTitle - $currentArtist"
                )
            }
        } catch (e: Exception) {
            android.util.Log.e(
                "PlaybackService",
                "❌ Failed to sync MediaSession metadata: ${e.message}"
            )
        }
    }
    
    private fun showNotification(albumArt: Bitmap?) {
        val isPlaying = player?.isPlaying ?: false
        android.util.Log.d("PlaybackService", "📢 showNotification: isPlaying=$isPlaying, title=$currentTitle")
        
        // Previous action
        val previousAction = NotificationCompat.Action(
            R.drawable.ic_previous,
            "Previous",
            createActionPendingIntent(ACTION_PREVIOUS)
        )
        
        // Play/Pause action
        val playPauseAction = if (isPlaying) {
            NotificationCompat.Action(
                R.drawable.ic_pause,
                "Pause",
                createActionPendingIntent(ACTION_PAUSE)
            )
        } else {
            NotificationCompat.Action(
                R.drawable.ic_play,
                "Play",
                createActionPendingIntent(ACTION_PLAY)
            )
        }
        
        // Next action
        val nextAction = NotificationCompat.Action(
            R.drawable.ic_next,
            "Next",
            createActionPendingIntent(ACTION_NEXT)
        )
        
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_music_note)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setLargeIcon(albumArt)
            .addAction(previousAction)  // Index 0
            .addAction(playPauseAction) // Index 1
            .addAction(nextAction)      // Index 2
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setOngoing(true) // Always ongoing to prevent dismissal
        
        // Add MediaStyle if MediaSession is available
        // Show Previous (0), Play/Pause (1), Next (2) in compact view
        mediaSession?.let { session ->
            notificationBuilder.setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setMediaSession(session.sessionCompatToken)
                    .setShowActionsInCompactView(0, 1, 2)
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
        android.util.Log.d("PlaybackService", "🔄 PlaybackService destroying...")
        
        // Remove listener from player
        player?.removeListener(playerListener)
        player = null
        
        // Release MediaSession
        mediaSession?.release()
        mediaSession = null
        
        // Clear instance
        instance = null
        
        super.onDestroy()
        android.util.Log.d("PlaybackService", "✅ PlaybackService destroyed")
    }
}
