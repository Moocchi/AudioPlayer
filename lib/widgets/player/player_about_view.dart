import 'package:flutter/material.dart';
import 'package:iqbal_hires/models/song.dart';
import 'package:iqbal_hires/services/exoplayer_service.dart';
import 'package:iqbal_hires/theme/app_theme.dart';
import 'package:iqbal_hires/widgets/hires_badge.dart';

class PlayerAboutView extends StatelessWidget {
  const PlayerAboutView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ExoPlayerService(),
      builder: (context, _) {
        final audio = ExoPlayerService();
        final song = audio.currentSong;

        if (song == null) {
          return const Center(child: Text('No Song Playing'));
        }

        final bestQualityTag = _resolveBestQualityTag(song);

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Judul', song.title),
                _buildInfoRow('Artis', song.artist),
                _buildInfoRow('Album', song.albumTitle),
                _buildInfoRow('Durasi', song.durationFormatted),
                const SizedBox(height: 8),
                Text('Audio Quality', style: AppTheme.heading3),
                const SizedBox(height: 12),
                _buildQualityBadge(bestQualityTag),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _resolveBestQualityTag(Song song) {
    final normalizedTags = song.mediaTags
        .where((tag) => tag.trim().isNotEmpty)
        .map((tag) => tag.trim().toUpperCase())
        .toSet()
        .toList();

    final hasHiRes = normalizedTags.any(
      (tag) => tag.contains('HIRES') || tag.contains('HI_RES') || tag.contains('HI-RES'),
    );

    if (hasHiRes) {
      return 'HIRES_LOSSLESS';
    }

    final hasLossless = normalizedTags.any((tag) => tag.contains('LOSSLESS'));
    if (hasLossless) {
      return 'LOSSLESS';
    }

    if (song.isHiRes) {
      return 'HIRES_LOSSLESS';
    }
    if (song.isLossless) {
      return 'LOSSLESS';
    }
    return 'STANDARD';
  }

  String _formatTag(String rawTag) {
    final words = rawTag
        .toLowerCase()
        .split('_')
        .where((word) => word.isNotEmpty)
        .toList();

    return words
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  Widget _buildQualityBadge(String tag) {
    final lowerTag = tag.toLowerCase();
    final isHiRes =
        lowerTag.contains('hires') ||
        lowerTag.contains('hi_res') ||
        lowerTag.contains('hi-res');
    final isLossless = lowerTag.contains('lossless');

    if (isHiRes) {
      return Transform.scale(
        scale: 1.3,
        alignment: Alignment.centerLeft,
        child: AnimatedHiResBadge(),
      );
    }

    if (isLossless) {
      return Transform.scale(
        scale: 1.3,
        alignment: Alignment.centerLeft,
        child: LosslessBadge(),
      );
    }

    Color color = AppTheme.textSecondary;
    IconData icon = Icons.tag;
    final displayTag = _formatTag(tag);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            displayTag,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
