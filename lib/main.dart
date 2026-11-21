import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'merge_page.dart';
import 'progress_style.dart';

void main() => runApp(const VideoMergerApp());

class VideoMergerApp extends StatefulWidget {
  const VideoMergerApp({super.key});

  @override
  State<VideoMergerApp> createState() => _VideoMergerAppState();
}

class _VideoMergerAppState extends State<VideoMergerApp> {
  static const String _prefThemeModeKey = 'theme_mode';
  static const String _legacyDarkModeKey = 'is_dark_mode';

  ThemeMode _themeMode = ThemeMode.system;
  ProgressBarStyle _progressStyle = ProgressBarStyle.cardSweep;
  ProgressColorPreset _progressColor = ProgressColorPreset.dodgerBlue;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefThemeModeKey);
      ThemeMode? resolved;
      if (savedMode == 'system') {
        resolved = ThemeMode.system;
      } else if (savedMode == 'light') {
        resolved = ThemeMode.light;
      } else if (savedMode == 'dark') {
        resolved = ThemeMode.dark;
      } else if (prefs.containsKey(_legacyDarkModeKey)) {
        resolved = prefs.getBool(_legacyDarkModeKey) == false
            ? ThemeMode.light
            : ThemeMode.dark;
      }

      final savedStyle = await ProgressStylePrefs.loadStyle();
      final savedColor = await ProgressStylePrefs.loadColor();
      if (mounted) {
        setState(() {
          if (resolved != null) _themeMode = resolved;
          _progressStyle = savedStyle;
          _progressColor = savedColor;
        });
      }
    } catch (_) {}
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefThemeModeKey, mode.name);
    } catch (_) {}
  }

  Future<void> _setProgressStyle(ProgressBarStyle style) async {
    setState(() => _progressStyle = style);
    await ProgressStylePrefs.saveStyle(style);
  }

  Future<void> _setProgressColor(ProgressColorPreset preset) async {
    setState(() => _progressColor = preset);
    await ProgressStylePrefs.saveColor(preset);
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ProgressColorPreset.dodgerBlue.primary,
      secondary: ProgressColorPreset.dodgerBlue.light,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E1116) : const Color(0xFFF5F7FA),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor:
            isDark ? const Color(0xFF141920) : const Color(0xFFFFFFFF),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF171D26) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(
              alpha: isDark ? 0.35 : 0.6,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VideoMerger',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: MergePage(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        progressStyle: _progressStyle,
        onProgressStyleChanged: _setProgressStyle,
        progressColor: _progressColor,
        onProgressColorChanged: _setProgressColor,
      ),
    );
  }
}
