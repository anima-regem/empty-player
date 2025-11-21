import 'package:empty_player/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VideoFrame extends StatelessWidget {
  const VideoFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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