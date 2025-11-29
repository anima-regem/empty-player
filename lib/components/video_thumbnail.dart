import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:empty_player/services/thumbnail_service.dart';

/// A widget that displays a video thumbnail.
/// Loads thumbnails asynchronously without blocking the UI.
class VideoThumbnail extends StatefulWidget {
  final String? assetId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const VideoThumbnail({
    super.key,
    required this.assetId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  Uint8List? _thumbnailData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (widget.assetId == null) return;

    // Check if thumbnail is already cached
    final cached = ThumbnailService.getCachedThumbnail(widget.assetId);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _thumbnailData = cached;
          _isLoading = false;
        });
      }
      return;
    }

    // Load thumbnail asynchronously
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final data = await ThumbnailService.loadThumbnail(widget.assetId);

    if (mounted) {
      setState(() {
        _thumbnailData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_thumbnailData != null) {
      content = Image.memory(
        _thumbnailData!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder();
        },
      );
    } else {
      content = _buildPlaceholder();
    }

    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return content;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey.shade900,
      child: _isLoading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                ),
              ),
            )
          : Icon(
              Icons.movie_outlined,
              color: Colors.grey.shade700,
              size: 24,
            ),
    );
  }
}
