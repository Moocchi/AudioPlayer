import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/exoplayer_service.dart';

class CacheBadge extends StatelessWidget {
  final Song song;
  final Widget child;
  final double size;
  final double top;
  final double right;

  const CacheBadge({
    Key? key,
    required this.song,
    required this.child,
    this.size = 7,
    this.top = 5,
    this.right = 5,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.loose,
      children: [
        child,
        Positioned(
          top: top,
          right: right,
          child: FutureBuilder<CacheStatus>(
            future: ExoPlayerService().getSongCacheStatus(
              song,
              song.isHiRes ? 'HI_RES' : (song.isLossless ? 'LOSSLESS' : 'REGULAR'),
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data != CacheStatus.full) {
                return const SizedBox.shrink();
              }
              
              return Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  color: Color(0xFF00FF41),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
