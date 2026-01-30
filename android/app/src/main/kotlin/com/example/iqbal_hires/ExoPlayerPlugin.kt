package com.example.iqbal_hires

import android.content.ComponentName
import android.content.Intent
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Tracks
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.FileDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.dash.manifest.DashManifest
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionToken
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.content.Context
import android.os.Handler
import android.os.Looper

class ExoPlayerPlugin : FlutterPlugin, MethodCallHandler, Player.Listener, PlaybackService.SkipCallback {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    private var exoPlayer: ExoPlayer? = null
    private var currentManifest: DashManifest? = null
    private val handler = Handler(Looper.getMainLooper())
    
    // SkipCallback implementation - send events to Flutter
    override fun onSkipNext() {
        android.util.Log.d("ExoPlayer", "⏭️ Skip Next triggered from notification")
        sendEvent("skip_next", mapOf("action" to "next"))
    }
    
    override fun onSkipPrevious() {
        android.util.Log.d("ExoPlayer", "⏮️ Skip Previous triggered from notification")
        sendEvent("skip_previous", mapOf("action" to "previous"))
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "exoplayer")
        channel.setMethodCallHandler(this)
        
        // Register as SkipCallback
        PlaybackService.skipCallback = this
        
        // Start PlaybackService as regular service (not foreground yet)
        val serviceIntent = Intent(context, PlaybackService::class.java)
        context.startService(serviceIntent)
        
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "exoplayer/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "setDashSource" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    setDashSource(url, result)
                } else {
                    result.error("INVALID_ARGUMENT", "URL is null", null)
                }
            }
            "play" -> {
                android.util.Log.d("ExoPlayer", "▶️  Play called | Player ready: ${exoPlayer?.playWhenReady} | State: ${exoPlayer?.playbackState}")
                if (exoPlayer != null) {
                    exoPlayer!!.play()
                    android.util.Log.d("ExoPlayer", "✅ Play() called successfully")
                } else {
                    android.util.Log.e("ExoPlayer", "❌ ExoPlayer is null!")
                }
                result.success(null)
            }
            "pause" -> {
                android.util.Log.d("ExoPlayer", "⏸️  Pause called")
                exoPlayer?.pause()
                android.util.Log.d("ExoPlayer", "✅ Pause() called successfully")
                result.success(null)
            }
            "stop" -> {
                exoPlayer?.stop()
                result.success(null)
            }
            "seekTo" -> {
                val positionMs = call.argument<Int>("positionMs")?.toLong() ?: 0L
                if (exoPlayer != null && positionMs >= 0) {
                    android.util.Log.d("ExoPlayer", "⏩ Seeking to ${positionMs}ms, player state: ${exoPlayer?.playbackState}")
                    
                    // Log audio format BEFORE seek
                    logCurrentAudioFormat("BEFORE SEEK")
                    
                    // Set seek parameters for precise seeking on FLAC/Hi-Res
                    exoPlayer?.setSeekParameters(androidx.media3.exoplayer.SeekParameters.CLOSEST_SYNC)
                    
                    // Perform seek - ExoPlayer handles queueing internally even if not ready
                    exoPlayer?.seekTo(positionMs)
                    android.util.Log.d("ExoPlayer", "✅ Seek queued successfully")
                    
                    // Log audio format AFTER seek (with small delay to ensure it's applied)
                    handler.postDelayed({
                        logCurrentAudioFormat("AFTER SEEK")
                    }, 200)
                    
                    result.success(null)
                } else {
                    android.util.Log.e("ExoPlayer", "❌ Seek failed: player null or invalid position")
                    result.error("SEEK_ERROR", "Player not initialized or invalid position", null)
                }
            }
            "getCurrentPosition" -> {
                val position = exoPlayer?.currentPosition?.toInt() ?: 0
                result.success(position)
            }
            "getDuration" -> {
                val duration = exoPlayer?.duration?.let { 
                    if (it == C.TIME_UNSET) 0 else it.toInt() 
                } ?: 0
                result.success(duration)
            }
            "getManifestInfo" -> {
                result.success(getCurrentManifestInfo())
            }
            "updateMetadata" -> {
                val title = call.argument<String>("title") ?: ""
                val artist = call.argument<String>("artist") ?: ""
                val albumCover = call.argument<String>("albumCover") ?: ""
                updateNotification(title, artist, albumCover)
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun setDashSource(url: String, result: Result) {
        try {
            // Only create new player if not exists
            if (exoPlayer == null) {
                // Use DefaultRenderersFactory for better device compatibility
                // This avoids stuck loading issues on different hardware
                val renderersFactory = androidx.media3.exoplayer.DefaultRenderersFactory(context)
                    .setEnableDecoderFallback(true)
                    .setExtensionRendererMode(androidx.media3.exoplayer.DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
                
                exoPlayer = ExoPlayer.Builder(context)
                    .setRenderersFactory(renderersFactory)
                    .setAudioAttributes(
                        androidx.media3.common.AudioAttributes.Builder()
                            .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
                            .setUsage(androidx.media3.common.C.USAGE_MEDIA)
                            .build(),
                        true // Handle audio focus
                    )
                    .build().apply {
                        addListener(this@ExoPlayerPlugin)
                        // Set seek parameters for precise seeking on FLAC/Hi-Res audio
                        setSeekParameters(androidx.media3.exoplayer.SeekParameters.CLOSEST_SYNC)
                        
                        android.util.Log.d("ExoPlayer", "✅ ExoPlayer configured: Default renderer, Hi-Res passthrough enabled")
                    }
                
                // Pass player to PlaybackService for notifications
                PlaybackService.instance?.setPlayer(exoPlayer!!)
            }

            // Check if it's a file URL or HTTP URL
            if (url.startsWith("file://")) {
                // For file URLs, use ProgressiveMediaSource
                val filePath = url.removePrefix("file://")
                val mediaItem = MediaItem.fromUri(android.net.Uri.parse("file://$filePath"))
                
                // Create file data source factory
                val dataSourceFactory = FileDataSource.Factory()
                
                // Create progressive media source for local files
                val progressiveMediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(mediaItem)
                
                exoPlayer?.setMediaSource(progressiveMediaSource)
                exoPlayer?.prepare()
                
                sendEvent("source_set", mapOf("url" to url, "type" to "file"))
                android.util.Log.d("ExoPlayer", "✅ File source prepared: $url")
            } else {
                // For HTTP URLs (including localhost manifest serving)
                // Use DefaultHttpDataSource with longer timeouts for Hi-Res streaming
                val httpDataSourceFactory = DefaultHttpDataSource.Factory()
                    .setAllowCrossProtocolRedirects(true)
                    .setConnectTimeoutMs(30000)
                    .setReadTimeoutMs(30000)
                    .setUserAgent("ExoPlayer-HiRes/1.0 (Tidal Compatible)")

                // Check if it's a DASH manifest URL
                if (url.endsWith(".mpd") || url.contains("manifest")) {
                    // DASH source - simplified for VOD seeking
                    val dashMediaSource = DashMediaSource.Factory(httpDataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(url))
                    
                    exoPlayer?.setMediaSource(dashMediaSource)
                    exoPlayer?.prepare()
                    
                    sendEvent("source_set", mapOf("url" to url, "type" to "dash"))
                    android.util.Log.d("ExoPlayer", "✅ DASH source prepared with VOD seeking support: $url")
                } else {
                    // Progressive source for regular audio files
                    val progressiveMediaSource = ProgressiveMediaSource.Factory(httpDataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(url))
                    
                    exoPlayer?.setMediaSource(progressiveMediaSource)
                    exoPlayer?.prepare()
                    
                    sendEvent("source_set", mapOf("url" to url, "type" to "progressive"))
                    android.util.Log.d("ExoPlayer", "✅ Progressive source prepared: $url")
                }
            }
            
            result.success(null)
            
        } catch (e: Exception) {
            android.util.Log.e("ExoPlayer", "Error setting source: ${e.message}", e)
            result.error("DASH_ERROR", "Failed to set DASH source", e.message)
        }
    }

    private fun getCurrentManifestInfo(): Map<String, Any>? {
        val manifest = currentManifest ?: return null
        
        return try {
            val manifestInfo = mutableMapOf<String, Any>()
            manifestInfo["periodCount"] = manifest.periodCount
            manifestInfo["duration"] = if (manifest.durationMs == C.TIME_UNSET) 0 else manifest.durationMs
            manifestInfo["dynamic"] = manifest.dynamic
            
            // Get adaptation sets info
            val adaptationSets = mutableListOf<Map<String, Any>>()
            for (i in 0 until manifest.periodCount) {
                val period = manifest.getPeriod(i)
                for (j in 0 until period.adaptationSets.size) {
                    val adaptationSet = period.adaptationSets[j]
                    val setInfo = mutableMapOf<String, Any>()
                    setInfo["id"] = adaptationSet.id
                    setInfo["type"] = adaptationSet.type
                    setInfo["representationCount"] = adaptationSet.representations.size
                    adaptationSets.add(setInfo)
                }
            }
            manifestInfo["adaptationSets"] = adaptationSets
            
            manifestInfo
        } catch (e: Exception) {
            null
        }
    }

    override fun onTimelineChanged(timeline: Timeline, reason: Int) {
        try {
            // Get current manifest from timeline
            if (timeline.windowCount > 0) {
                val windowIndex = exoPlayer?.currentMediaItemIndex ?: 0
                if (windowIndex < timeline.windowCount) {
                    val window = Timeline.Window()
                    timeline.getWindow(windowIndex, window)
                    
                    // Try to get manifest from media source
                    sendEvent("timeline_changed", mapOf(
                        "windowCount" to timeline.windowCount,
                        "reason" to reason
                    ))
                }
            }
        } catch (e: Exception) {
            sendEvent("error", mapOf("message" to "Timeline error: ${e.message}"))
        }
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        val stateString = when (playbackState) {
            Player.STATE_IDLE -> "idle"
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY -> "ready"
            Player.STATE_ENDED -> "ended"
            else -> "unknown"
        }
        android.util.Log.d("ExoPlayer", "🎭 Playback state: $stateString")
        sendEvent("playback_state_changed", mapOf("state" to stateString))
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        android.util.Log.d("ExoPlayer", "▶️ Is playing changed: $isPlaying, eventSink: ${eventSink != null}")
        sendEvent("is_playing_changed", mapOf("is_playing" to isPlaying))
        if (isPlaying) {
            // Log audio format when playback starts
            logCurrentAudioFormat("PLAYBACK STARTED")
        }
    }
    
    override fun onTracksChanged(tracks: Tracks) {
        // Log whenever track selection changes (important for quality monitoring)
        logCurrentAudioFormat("TRACKS CHANGED")
    }
    
    private fun logCurrentAudioFormat(debugContext: String) {
        try {
            val currentTracks = exoPlayer?.currentTracks ?: return
            
            android.util.Log.d("ExoPlayer", "═══════════════════════════════════════")
            android.util.Log.d("ExoPlayer", "🎵 AUDIO QUALITY DEBUG - $debugContext")
            android.util.Log.d("ExoPlayer", "═══════════════════════════════════════")
            
            // Get Android native audio output sample rate
            try {
                val audioManager = this.context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                val nativeSampleRate = audioManager.getProperty(android.media.AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
                val nativeFramesPerBuffer = audioManager.getProperty(android.media.AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
                android.util.Log.d("ExoPlayer", "📱 Android Native Output: $nativeSampleRate Hz, Buffer: $nativeFramesPerBuffer frames")
            } catch (e: Exception) {
                android.util.Log.w("ExoPlayer", "Could not get native audio properties: ${e.message}")
            }
            
            // Find audio track
            for (trackGroup in currentTracks.groups) {
                if (trackGroup.type == C.TRACK_TYPE_AUDIO && trackGroup.isSelected) {
                    for (i in 0 until trackGroup.length) {
                        if (trackGroup.isTrackSelected(i)) {
                            val format = trackGroup.getTrackFormat(i)
                            logAudioFormatDetails(format)
                        }
                    }
                }
            }
            
            android.util.Log.d("ExoPlayer", "═══════════════════════════════════════")
        } catch (e: Exception) {
            android.util.Log.e("ExoPlayer", "Error logging audio format: ${e.message}")
        }
    }
    
    private fun logAudioFormatDetails(format: Format) {
        android.util.Log.d("ExoPlayer", "🎧 Codec: ${format.sampleMimeType ?: "Unknown"}")
        
        val sampleRate = format.sampleRate
        val sampleRateKhz = sampleRate / 1000.0
        val hiResIndicator = when {
            sampleRate >= 96000 -> "🌟 Hi-Res (96kHz+)"
            sampleRate >= 48000 -> "⭐ Hi-Res (48kHz)"
            sampleRate >= 44100 -> "✓ CD Quality (44.1kHz)"
            else -> "⚠️ Low Quality"
        }
        android.util.Log.d("ExoPlayer", "📊 Sample Rate: $sampleRate Hz (${sampleRateKhz} kHz) - $hiResIndicator")
        
        android.util.Log.d("ExoPlayer", "🔊 Channels: ${format.channelCount}")
        android.util.Log.d("ExoPlayer", "💾 Bitrate: ${if (format.bitrate > 0) "${format.bitrate / 1000} kbps" else "Unknown"}")
        
        val bitDepth = format.pcmEncoding.let { 
            when(it) {
                C.ENCODING_PCM_16BIT -> "16-bit"
                C.ENCODING_PCM_24BIT -> "24-bit"
                C.ENCODING_PCM_32BIT -> "32-bit"
                C.ENCODING_PCM_FLOAT -> "32-bit Float"
                else -> "Unknown ($it)"
            }
        }
        android.util.Log.d("ExoPlayer", "🎚️ Bit Depth: $bitDepth")
        android.util.Log.d("ExoPlayer", "📦 Container: ${format.containerMimeType ?: "Unknown"}")
        android.util.Log.d("ExoPlayer", "🔢 Format ID: ${format.id ?: "N/A"}")
        
        // Warning if potential quality degradation
        if (sampleRate < 44100) {
            android.util.Log.w("ExoPlayer", "⚠️ WARNING: Sample rate below CD quality! Possible resampling detected!")
        }
    }
    


    override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
        sendEvent("error", mapOf("message" to error.message))
    }

    private fun sendEvent(event: String, data: Map<String, Any?>) {
        handler.post {
            val eventData = mutableMapOf<String, Any?>()
            eventData["event"] = event
            eventData.putAll(data)
            android.util.Log.d("ExoPlayer", "📤 Sending event: $event, data: $data, sink: ${eventSink != null}")
            eventSink?.success(eventData)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        // Don't release player here - PlaybackService manages it
        exoPlayer?.removeListener(this)
        exoPlayer = null
    }

    private fun updateNotification(title: String, artist: String, albumCover: String) {
        // Update metadata in PlaybackService - this will trigger automatic notification
        PlaybackService.instance?.updateMetadata(title, artist, albumCover)
        android.util.Log.d("ExoPlayer", "🔔 Notification updated via PlaybackService: $title - $artist")
    }
}