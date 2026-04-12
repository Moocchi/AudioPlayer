import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';
import '../services/play_history_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'cached_songs_screen.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
                    'Settings',
                    style: AppTheme.heading1.copyWith(fontSize: 28),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: ListenableBuilder(
                listenable: SettingsService(),
                builder: (context, _) => _buildContent(),
              ),
            ),
            // Mini player
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Storage Section
        const SizedBox(height: 8),
        Text(
          'Storage',
          style: AppTheme.caption.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        _buildCacheEntry(),
        const SizedBox(height: 24),

        // Display Section
        Text(
          'Display',
          style: AppTheme.caption.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),

        // Collection Layout Setting
        _buildLayoutToggle(),

        const SizedBox(height: 12),

        // Auto-Hide Overlay Setting (Grid mode only)
        _buildAutoHideToggle(),

        const SizedBox(height: 24),

        // Data Section
        Text(
          'Data & History',
          style: AppTheme.caption.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        
        _buildClearHistoryEntry(),

        const SizedBox(height: 100), // Space for mini player
      ],
    );
  }

  Widget _buildCacheEntry() {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CachedSongsScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.storage_outlined, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cached Songs', style: AppTheme.body),
                    SizedBox(height: 2),
                    Text('Manage songs stored for offline playback', style: AppTheme.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClearHistoryEntry() {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Text('Clear History?', style: AppTheme.heading2),
              content: const Text(
                'This will reset your Quick Picks and Quick Shortcuts on the Home screen. This action cannot be undone.',
                style: AppTheme.body,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                TextButton(
                  onPressed: () {
                    PlayHistoryService().clearHistory();
                    Navigator.pop(ctx);
                    Fluttertoast.showToast(
                      msg: 'Home history cleared successfully!',
                      toastLength: Toast.LENGTH_SHORT,
                      gravity: ToastGravity.BOTTOM,
                    );
                  },
                  child: Text('Clear', style: TextStyle(color: AppTheme.primary)),
                ),
              ],
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Clear Home History', style: AppTheme.body),
                    SizedBox(height: 2),
                    Text('Reset quick picks and shortcuts', style: AppTheme.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayoutToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.view_module_outlined,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Collection Layout', style: AppTheme.body),
                    SizedBox(height: 2),
                    Text(
                      'Choose how to display playlists',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSegmentedButton(),
        ],
      ),
    );
  }

  Widget _buildSegmentedButton() {
    final settingsService = SettingsService();
    final isGridMode = settingsService.collectionLayoutMode == 'grid';

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // Sliding Background Indicator
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: isGridMode
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),

          // Buttons Row
          Row(
            children: [
              Expanded(
                child: _buildSegmentButton(
                  icon: Icons.grid_view_rounded,
                  label: 'Grid',
                  isSelected: isGridMode,
                  onTap: () {
                    settingsService.setCollectionLayoutMode('grid');
                  },
                ),
              ),
              Expanded(
                child: _buildSegmentButton(
                  icon: Icons.view_list_rounded,
                  label: 'List',
                  isSelected: !isGridMode,
                  onTap: () {
                    settingsService.setCollectionLayoutMode('list');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                tween: ColorTween(
                  end: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
                builder: (context, color, _) {
                  return Icon(icon, size: 18, color: color);
                },
              ),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAutoHideToggle() {
    final settingsService = SettingsService();
    final isEnabled = settingsService.gridAutoHideOverlay;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: Icon(
              isEnabled ? Icons.visibility_off : Icons.visibility,
              key: ValueKey(isEnabled),
              size: 22,
              color: isEnabled ? AppTheme.primary : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Auto-Hide Grid Overlay', style: AppTheme.body),
                SizedBox(height: 2),
                Text('Hide name & menu after 2s idle', style: AppTheme.caption),
              ],
            ),
          ),
          Switch(
            value: isEnabled,
            onChanged: (value) {
              settingsService.setGridAutoHideOverlay(value);
            },
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}
