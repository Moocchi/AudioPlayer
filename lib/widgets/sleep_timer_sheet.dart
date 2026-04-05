import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/exoplayer_service.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'player_menu_sheet.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => const SleepTimerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sleep Timer', style: AppTheme.heading2),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: ExoPlayerService(),
            builder: (context, child) {
              final audio = ExoPlayerService();

              if (audio.stopAfterCurrentSong) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer_off_outlined,
                            size: 32,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Berhenti di Akhir Lagu',
                              style: AppTheme.body.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          audio.cancelSleepTimer();
                          Navigator.pop(context); // Close Sleep Timer
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Batalkan Timer',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (audio.sleepTimerDuration != null) {
                final duration = audio.sleepTimerDuration!;
                String timeStr;
                if (duration.inHours > 0) {
                  final h = duration.inHours;
                  final m = (duration.inMinutes % 60).toString().padLeft(
                    2,
                    '0',
                  );
                  final s = (duration.inSeconds % 60).toString().padLeft(
                    2,
                    '0',
                  );
                  timeStr = '$h:$m:$s';
                } else {
                  final m = duration.inMinutes;
                  final s = (duration.inSeconds % 60).toString().padLeft(
                    2,
                    '0',
                  );
                  timeStr = '$m:$s';
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 32,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  timeStr,
                                  style: AppTheme.heading2.copyWith(
                                    fontSize: 24,
                                  ),
                                ),
                                const Text(
                                  'Waktu Tersisa',
                                  style: AppTheme.caption,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => audio.addSleepTimerDuration(
                        const Duration(minutes: 5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surface,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppTheme.divider),
                        ),
                      ),
                      child: Text('Tambah 5 menit', style: AppTheme.body),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        audio.cancelSleepTimer();
                        Navigator.pop(context); // Close Sleep Timer
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Batalkan Timer',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTimerOption(context, '5 menit', 1.0),
                  _buildTimerOption(context, '15 menit', 3.0),
                  _buildTimerOption(context, '30 menit', 6.0),
                  _buildTimerOption(context, '1 jam', 12.0),
                  _buildTimerOption(context, 'Akhir lagu', 13.0, isEnd: true),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimerOption(
    BuildContext context,
    String title,
    double value, {
    bool isEnd = false,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        ExoPlayerService().setSleepTimer(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.divider.withOpacity(0.05)),
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Text(title, style: AppTheme.body.copyWith(fontSize: 16)),
      ),
    );
  }
}
