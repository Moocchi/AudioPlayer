import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';

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
        // Display Section
        const SizedBox(height: 8),
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

        const SizedBox(height: 100), // Space for mini player
      ],
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
}
