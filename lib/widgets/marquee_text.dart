import 'package:flutter/material.dart';

/// A widget that scrolls text horizontally if it overflows
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double velocity; // pixels per second
  final Duration pauseDuration;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.velocity = 30.0,
    this.pauseDuration = const Duration(seconds: 1),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;
  bool _needsScroll = false;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOverflow();
    });
  }

  void _checkOverflow() {
    if (!mounted) return;
    
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0 && !_needsScroll) {
        setState(() => _needsScroll = true);
        _startScrolling();
      }
    }
  }

  Future<void> _startScrolling() async {
    if (!mounted || _isScrolling) return;
    _isScrolling = true;

    while (mounted && _needsScroll) {
      // Wait at start
      await Future.delayed(widget.pauseDuration);
      if (!mounted) break;

      // Scroll to end
      final maxScroll = _scrollController.position.maxScrollExtent;
      final duration = Duration(
        milliseconds: (maxScroll / widget.velocity * 1000).round(),
      );
      
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          maxScroll,
          duration: duration,
          curve: Curves.linear,
        );
      }

      if (!mounted) break;

      // Wait at end
      await Future.delayed(widget.pauseDuration);
      if (!mounted) break;

      // Scroll back to start
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: duration,
          curve: Curves.linear,
        );
      }
    }
    
    _isScrolling = false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
      ),
    );
  }
}
