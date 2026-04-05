import 'package:flutter/material.dart';
import 'package:iqbal_hires/services/exoplayer_service.dart';
import 'package:iqbal_hires/theme/app_theme.dart';

class PlayerAboutView extends StatelessWidget {
  const PlayerAboutView({Key? key}) : super(key: key);

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

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Info Lagu', style: AppTheme.heading2),
                const SizedBox(height: 24),
                _buildInfoRow('Judul', song.title),
                _buildInfoRow('Artis', song.artist),
                _buildInfoRow(
                  'Album',
                  'Unknown Album',
                ), // Need to add album to Song model
                const Divider(color: AppTheme.divider, height: 32),
                Text('Audio Quality', style: AppTheme.heading3),
                const SizedBox(height: 16),
                _buildQualityBadge(song.isHiRes, song.isLossless),
                const SizedBox(height: 16),
                if (song.filePath != null)
                  _buildInfoRow('File Path', song.filePath!),
                if (song.url.startsWith('http'))
                  _buildInfoRow('Stream URL', song.url),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityBadge(bool isHiRes, bool isLossless) {
    String text = 'Standard Quality';
    Color color = Colors.grey;
    IconData icon = Icons.sd_storage;

    if (isHiRes) {
      text = 'Hi-Res Lossless';
      color = const Color(0xFFFFD700); // Gold
      icon = Icons.auto_awesome;
    } else if (isLossless) {
      text = 'Lossless';
      color = AppTheme.primary;
      icon = Icons.high_quality;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
