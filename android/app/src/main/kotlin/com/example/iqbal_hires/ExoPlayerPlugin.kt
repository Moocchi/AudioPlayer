package com.example.iqbal_hires

import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.C
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.FileDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.dash.manifest.DashManifest
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.content.Context
import android.os.Handler
import android.os.Looper

class ExoPlayerPlugin : FlutterPlugin, MethodCallHandler, Player.Listener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    private var exoPlayer: ExoPlayer? = null
    private var currentManifest: DashManifest? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "exoplayer")
        channel.setMethodCallHandler(this)
        
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
                exoPlayer?.play()
                result.success(null)
            }
            "pause" -> {
                exoPlayer?.pause()
                result.success(null)
            }
            "stop" -> {
                exoPlayer?.stop()
                result.success(null)
            }
            "seekTo" -> {
                val position = call.argument<Int>("position")?.toLong() ?: 0L
                exoPlayer?.seekTo(position)
                result.success(null)
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
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun setDashSource(url: String, result: Result) {
        try {
            // Release current player
            exoPlayer?.release()
            
            // Create new ExoPlayer with optimized settings for Hi-Res streaming
            exoPlayer = ExoPlayer.Builder(context)
                .build().apply {
                    addListener(this@ExoPlayerPlugin)
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
                    // DASH source - ExoPlayer will fetch manifest from localhost
                    // and segments from external CDN (Tidal)
                    val dashMediaSource = DashMediaSource.Factory(httpDataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(url))
                    
                    exoPlayer?.setMediaSource(dashMediaSource)
                    exoPlayer?.prepare()
                    
                    sendEvent("source_set", mapOf("url" to url, "type" to "dash"))
                    android.util.Log.d("ExoPlayer", "DASH source set: $url")
                } else {
                    // Progressive source for regular audio files
                    val progressiveMediaSource = ProgressiveMediaSource.Factory(httpDataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(url))
                    
                    exoPlayer?.setMediaSource(progressiveMediaSource)
                    exoPlayer?.prepare()
                    
                    sendEvent("source_set", mapOf("url" to url, "type" to "progressive"))
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
        sendEvent("playback_state_changed", mapOf("state" to stateString))
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        sendEvent("is_playing_changed", mapOf("isPlaying" to isPlaying))
    }

    override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
        sendEvent("error", mapOf("message" to error.message))
    }

    private fun sendEvent(event: String, data: Map<String, Any?>) {
        handler.post {
            val eventData = mutableMapOf<String, Any?>()
            eventData["event"] = event
            eventData.putAll(data)
            eventSink?.success(eventData)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        exoPlayer?.release()
        exoPlayer = null
    }
}