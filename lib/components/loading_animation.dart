import 'package:flutter/material.dart';

/// A fun loading animation widget.
/// 
/// This widget displays a pulsating, rotating animation for loading states
/// instead of the standard CircularProgressIndicator, making loading more
/// engaging and playful.
class LoadingAnimation extends StatefulWidget {
  /// The color to use for the animation.
  /// Defaults to Colors.white.
  final Color color;
  
  /// The size of the loading animation widget.
  /// Defaults to 100x100.
  final double size;

  const LoadingAnimation({
    super.key,
    this.color = Colors.white,
    this.size = 100,
  });

  @override
  State<LoadingAnimation> createState() => _LoadingAnimationState();
}

class _LoadingAnimationState extends State<LoadingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 2 * 3.14159,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _rotationAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer circle
                  Container(
                    width: widget.size * 0.8,
                    height: widget.size * 0.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.color.withOpacity(0.3),
                        width: 3,
                      ),
                    ),
                  ),
                  // Inner pulsating circle
                  Container(
                    width: widget.size * 0.5,
                    height: widget.size * 0.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withOpacity(0.5),
                    ),
                  ),
                  // Center dot
                  Container(
                    width: widget.size * 0.2,
                    height: widget.size * 0.2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A compact version of the loading animation for smaller spaces.
class CompactLoadingAnimation extends StatelessWidget {
  final Color color;

  const CompactLoadingAnimation({
    super.key,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingAnimation(
      color: color,
      size: 48,
    );
  }
}
