import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CustomLoader extends StatefulWidget {
  final double size;
  final Color? color;

  const CustomLoader({
    super.key,
    this.size = 40.0,
    this.color,
  });

  @override
  State<CustomLoader> createState() => _CustomLoaderState();
}

class _CustomLoaderState extends State<CustomLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _frameAnimation;
  
  // You have 32 frames (000 to 031)
  final int _frameCount = 32;

  @override
  void initState() {
    super.initState();
    
    // Duration dictates the speed of the animation. 
    // 1000ms for 32 frames is roughly 32 frames-per-second.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(); // This makes the animation loop endlessly

    // Create an integer tween that counts from 0 to 31
    _frameAnimation = IntTween(begin: 0, end: _frameCount - 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose(); // Always dispose controllers to prevent memory leaks!
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _frameAnimation,
      builder: (context, child) {
        // Format the integer to match your file naming convention (e.g., 001, 002, 010)
        final frameIndex = _frameAnimation.value.toString().padLeft(3, '0');
        
        return SvgPicture.asset(
          'assets/animations/loading_animation/generosity_18654316_$frameIndex.svg',
          width: widget.size,
          height: widget.size,
          // Optional: apply a color tint if you want it to match your primary green theme
          colorFilter: widget.color != null 
              ? ColorFilter.mode(widget.color!, BlendMode.srcIn)
              : null,
        );
      },
    );
  }
}