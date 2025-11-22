import 'package:empty_player/pages/home_page.dart';
import 'package:empty_player/pages/video_player.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => VideoApp(videoUrl: uri, videoTitle: lastSegment),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.white,
        textTheme: GoogleFonts.latoTextTheme(ThemeData.dark().textTheme),
      ),
      title: 'Empty Player',
      home: const HomePage(),
    );
  }
}
