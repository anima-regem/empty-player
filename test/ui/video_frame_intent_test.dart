import 'package:empty_player/models/media_source.dart';
import 'package:empty_player/ui/video_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('openVideo intent pushes configured player page', (tester) async {
    await tester.pumpWidget(
      VideoFrame(
        homePage: const Scaffold(body: Text('home')),
        playerPageBuilder: (MediaSource source, String title) {
          return Scaffold(
            key: const Key('intent-player-page'),
            body: Text('$title|${source.rawInput}'),
          );
        },
      ),
    );

    await tester.pumpAndSettle();

    const channel = MethodChannel('com.example.empty_player/intent');
    const codec = StandardMethodCodec();
    final data = codec.encodeMethodCall(
      const MethodCall('openVideo', 'https://example.com/videos/demo.mp4'),
    );

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, data, (ByteData? _) {});

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('intent-player-page')), findsOneWidget);
    expect(find.textContaining('demo.mp4'), findsOneWidget);
  });
}
