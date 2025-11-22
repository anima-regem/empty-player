import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:rive/rive.dart';
import 'package:flutter/services.dart';
import '../services/app_settings_service.dart';

/// A fun loading animation widget.
/// 
/// This widget displays a pulsating, rotating animation for loading states
/// instead of the standard CircularProgressIndicator, making loading more
/// engaging and playful. Supports both custom pulsating animation and Rive-based
/// animations that can be toggled via settings.
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

class _LoadingAnimationState extends State<LoadingAnimation> {
  final AppSettingsService _settings = AppSettingsService();
  String _animationType = 'pulsating';
  bool _riveAssetExists = false;

  @override
  void initState() {
    super.initState();
    _loadAnimationType();
    _checkRiveAsset();
  }

  Future<void> _loadAnimationType() async {
    await _settings.init();
    if (mounted) {
      setState(() {
        _animationType = _settings.loadingAnimationType;
      });
    }
  }

  Future<void> _checkRiveAsset() async {
    try {
      await rootBundle.load('assets/anime_cat.riv');
      if (mounted) {
        setState(() {
          _riveAssetExists = true;
        });
      }
    } catch (e) {
      // Asset doesn't exist, _riveAssetExists remains false (already initialized)
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: (_animationType == 'rive' && _riveAssetExists)
          ? _RiveLoadingAnimation(size: widget.size, color: widget.color)
          : _PulsatingLoadingAnimation(size: widget.size, color: widget.color),
    );
  }
}

/// Rive-based loading animation
/// Note: The color parameter is accepted for API consistency but not used,
/// as Rive animations have their own color schemes defined in the .riv file.
class _RiveLoadingAnimation extends StatelessWidget {
  final double size;
  final Color color; // Kept for API consistency with _PulsatingLoadingAnimation

  const _RiveLoadingAnimation({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: RiveAnimation.asset(
        'assets/anime_cat.riv',
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Custom pulsating loading animation
class _PulsatingLoadingAnimation extends StatefulWidget {
  final double size;
  final Color color;

  const _PulsatingLoadingAnimation({
    required this.size,
    required this.color,
  });

  @override
  State<_PulsatingLoadingAnimation> createState() => _PulsatingLoadingAnimationState();
}

class _PulsatingLoadingAnimationState extends State<_PulsatingLoadingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _rotationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    
    // Scale animation with reverse
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));

    // Rotation animation without reverse (continuous rotation)
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _rotationController,
      curve: Curves.linear,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_scaleController, _rotationController]),
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
