import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'services/exoplayer_service.dart';
import 'services/play_history_service.dart';
import 'services/liked_songs_service.dart';
import 'services/playlist_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  ExoPlayerService();
  await PlayHistoryService().init();
  await LikedSongsService().init();
  await PlaylistService().init();

  // Set status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const IqbalHiresApp());
}

class IqbalHiresApp extends StatelessWidget {
  const IqbalHiresApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Iqbal Hires',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const NoGlowScrollBehavior(),
      home: const HomeScreen(),
    );
  }
}

class NoGlowScrollBehavior extends ScrollBehavior {
  const NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}