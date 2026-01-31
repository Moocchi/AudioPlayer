import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../services/liked_songs_service.dart';
import 'liked_songs_screen.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Collection',
                    style: AppTheme.heading1.copyWith(fontSize: 28),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: _buildContent(),
            ),
            
            // Mini player

          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Liked Songs Item
        // Liked Songs Item
        ListenableBuilder(
          listenable: LikedSongsService(),
          builder: (context, _) {
            final service = LikedSongsService();
            return _buildCollectionItem(
              title: 'Liked Songs',
              subtitle: '${service.songCount} songs',
              icon: Icons.favorite_rounded,
              gradientColors: [Colors.purple.shade800, Colors.blue.shade800],
              imagePath: service.playlistCoverPath,
              onTap: () {
                Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => const LikedSongsScreen()),
                );
              },
            );
          },
        ),
        
        // Add more collections later (e.g. Downloaded, Local, etc.)
      ],
    );
  }

  Widget _buildCollectionItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    String? imagePath,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 80,
        decoration: BoxDecoration(
          color: AppTheme.surface, // Surface color
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Icon / Art
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: imagePath == null ? LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ) : null,
                image: imagePath != null ? DecorationImage(
                  image: FileImage(File(imagePath)),
                  fit: BoxFit.cover,
                ) : null,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: imagePath == null ? Center(
                child: Icon(icon, color: Colors.white, size: 32),
              ) : null,
            ),
            
            const SizedBox(width: 16),
            
            // Text
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}
