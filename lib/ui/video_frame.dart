import 'package:empty_player/pages/home_page.dart';
import 'package:empty_player/pages/video_player.dart';
import 'package:empty_player/models/media_source.dart';
import 'package:empty_player/ui/app_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VideoFrame extends StatefulWidget {
  const VideoFrame({super.key});

  @override
  State<VideoFrame> createState() => _VideoFrameState();
}

class _VideoFrameState extends State<VideoFrame> {
  static const _intentChannel = MethodChannel(
    'com.example.empty_player/intent',
  );
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  bool _initializedIntentListener = false;

  @override
  void initState() {
    super.initState();
    _setupIntentListener();
  }

  void _setupIntentListener() {
    if (_initializedIntentListener) return;
    _initializedIntentListener = true;

    // Handle intents arriving after startup
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'openVideo') {
        final uri =
            call.arguments as String; // content:// or file:// or http(s)
        _openVideoFromIntent(uri);
      }
    });
  }

  void _openVideoFromIntent(String uri) {
    // Decide title from last path segment
    final lastSegment = Uri.parse(uri).pathSegments.isNotEmpty
        ? Uri.parse(uri).pathSegments.last
        : 'Video';
    try {
      final source = MediaSource.fromInput(uri);
      _navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => VideoApp(source: source, title: lastSegment),
        ),
      );
    } on FormatException {
      // Ignore unsupported intent URIs.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      title: 'Empty Player',
      home: const HomePage(),
    );
  }
}
