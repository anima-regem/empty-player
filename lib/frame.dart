import 'package:empty_player/pages/video_player.dart';
import 'package:empty_player/ui/video_frame.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';


class Frame extends StatelessWidget {
  const Frame({super.key});

  @override
  Widget build(BuildContext context) {
    return VideoFrame();
  }
}