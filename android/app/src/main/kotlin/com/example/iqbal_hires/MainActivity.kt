package com.example.iqbal_hires

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register ExoPlayer plugin for Hi-Res audio streaming
        flutterEngine.plugins.add(ExoPlayerPlugin())
    }
}
