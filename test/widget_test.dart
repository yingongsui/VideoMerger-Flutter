import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_merger/floating_toast.dart';
import 'package:video_merger/main.dart';
import 'package:video_merger/progress_style.dart';
import 'package:video_merger/video_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FloatingToast.dismiss();
  });

  test('checkCompatibility catches timebase, fps, pixFmt, and audio sample rate mismatches', () {
    const a = VideoMetadata(
      videoCodec: 'H264',
      videoProfile: 'High',
      resolution: '1920x1080',
      fpsValue: 30,
      pixelFormat: 'yuv420p',
      videoTimeBase: '1/15360',
      audioCodec: 'AAC',
      audioSampleRate: '48000 Hz',
      audioChannelLayout: 'stereo',
    );
    const b = VideoMetadata(
      videoCodec: 'H264',
      videoProfile: 'High',
      resolution: '1920x1080',
      fpsValue: 60,
      pixelFormat: 'yuv420p10le',
      videoTimeBase: '1/90000',
      audioCodec: 'AAC',
      audioSampleRate: '44100 Hz',
      audioChannelLayout: 'stereo',
    );

    final result = VideoService.checkCompatibility([a, b]);
    expect(result.isCompatible, isFalse);
    expect(result.warnings, contains('Timebase mismatch (timeline risk)'));
    expect(result.warnings, contains('FPS mismatch'));
    expect(result.warnings, contains('Pixel format / bit-depth mismatch'));
    expect(result.warnings, contains('Audio sample rate mismatch'));
  });

  testWidgets(
    'MergePage renders empty queue and Settings supports Theme, Progress Style, Extensions & About',
    (WidgetTester tester) async {
      await tester.pumpWidget(const VideoMergerApp());
      await tester.pumpAndSettle();

      expect(find.text('Direct-Stream Merger'), findsOneWidget);
      expect(find.text('No Videos in Queue'), findsOneWidget);
      expect(find.text('Add Videos'), findsOneWidget);
      expect(find.text('Merge'), findsOneWidget);

      // Open Settings from the top-right icon
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Progress Style & Accent'), findsOneWidget);
      expect(find.text('Dodger Blue'), findsOneWidget);
      expect(find.text('sample_clip_01.mp4'), findsOneWidget);

      // Switch progress style to Dual and color to Emerald, verify persistence
      await tester.tap(find.text('Dual'));
      await tester.pumpAndSettle();
      expect(await ProgressStylePrefs.loadStyle(), ProgressBarStyle.dualGlow);

      await tester.tap(find.byTooltip('Emerald'));
      await tester.pumpAndSettle();
      expect(find.text('Emerald'), findsOneWidget);
      expect(
        await ProgressStylePrefs.loadColor(),
        ProgressColorPreset.emerald,
      );

      // Switch theme to Light inside Settings
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);

      // Scroll down to Custom Video Extensions & About
      await tester.scrollUntilVisible(
        find.text('Custom Video Extensions'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'flv, .M4V');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('.flv'), findsOneWidget);
      expect(find.text('.m4v'), findsOneWidget);

      final allExts = await VideoService.getAllSupportedExtensions();
      expect(allExts, containsAll(['.mp4', '.flv', '.m4v']));

      await tester.scrollUntilVisible(
        find.text('https://github.com/yingongsui/VideoMerger-Flutter'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('ABOUT'), findsOneWidget);
      expect(find.text('VideoMerger'), findsOneWidget);

      // Let the floating toast auto-dismiss cleanly
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
