import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_merger/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MergePage renders empty queue and opens Settings with Theme & About', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VideoMergerApp());
    await tester.pumpAndSettle();

    expect(find.text('Direct-Stream Merger'), findsOneWidget);
    expect(find.text('No Videos in Queue'), findsOneWidget);
    expect(find.text('Add Videos'), findsOneWidget);
    expect(find.text('Start Concat'), findsOneWidget);

    // Open Settings from the top-left icon
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('VideoMerger'), findsOneWidget);
    expect(
      find.text('https://github.com/yingongsui/VideoMerger-Flutter'),
      findsOneWidget,
    );
    expect(find.text('Open Source Licenses'), findsOneWidget);

    // Switch theme to Light inside Settings
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.light);
  });
}
