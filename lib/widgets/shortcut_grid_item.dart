import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import 'song_menu_sheet.dart';

/// Grid item with scale animation on long press
class ShortcutGridItem extends StatefulWidget {
  final Song song;
  final VoidCallback onTap;

  const ShortcutGridItem({super.key, required this.song, required this.onTap});

  @override
  State<ShortcutGridItem> createState() => _ShortcutGridItemState();
}

class _ShortcutGridItemState extends State<ShortcutGridItem> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _scale = 0.95),
      onPointerUp: (_) => setState(() => _scale = 1.0),
      onPointerCancel: (_) => setState(() => _scale = 1.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: () {
          SongMenuSheet.show(context, widget.song);
        },
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Album cover
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: AppTheme.divider,
                ),
                child: CachedNetworkImage(
                  imageUrl: widget.song.albumCover ?? '',
                  memCacheWidth: 450,
                  maxWidthDiskCache: 450,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                  imageBuilder: (context, imageProvider) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: ColoredBox(
                      color: Color(0x11000000),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Image(
                          image: imageProvider,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                  placeholder: (context, url) => const SizedBox.shrink(),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(
                      Icons.music_note,
                      size: 24,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),

              // Gradient overlay at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(4),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),
              // Song title
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: Text(
                  widget.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
