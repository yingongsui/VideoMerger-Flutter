import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Curated primary color palettes for progress indicators (defaults to Dodger Blue).
enum ProgressColorPreset {
  dodgerBlue(
    'Dodger Blue',
    primary: Color(0xFF1E90FF),
    light: Color(0xFF5EB5FF),
    deep: Color(0xFF0B6AD4),
  ),
  cyan(
    'Cyan',
    primary: Color(0xFF00BCD4),
    light: Color(0xFF62EFFF),
    deep: Color(0xFF008BA3),
  ),
  emerald(
    'Emerald',
    primary: Color(0xFF10B981),
    light: Color(0xFF5EEAD4),
    deep: Color(0xFF047857),
  ),
  violet(
    'Violet',
    primary: Color(0xFF8B5CF6),
    light: Color(0xFFC4B5FD),
    deep: Color(0xFF6D28D9),
  ),
  amber(
    'Amber',
    primary: Color(0xFFF59E0B),
    light: Color(0xFFFCD34D),
    deep: Color(0xFFB45309),
  ),
  rose(
    'Rose',
    primary: Color(0xFFF43F5E),
    light: Color(0xFFFDA4AF),
    deep: Color(0xFFBE123C),
  );

  final String label;
  final Color primary;
  final Color light;
  final Color deep;

  const ProgressColorPreset(
    this.label, {
    required this.primary,
    required this.light,
    required this.deep,
  });
}

enum ProgressBarStyle {
  cardSweep('Sweep', 'Card Sweep'),
  bottomLine('Line', 'Bottom Line'),
  dualGlow('Dual', 'Sweep + Line');

  final String shortLabel;
  final String displayName;

  const ProgressBarStyle(this.shortLabel, this.displayName);
}

class ProgressStylePrefs {
  static const String _prefStyleKey = 'progress_bar_style';
  static const String _prefColorKey = 'progress_bar_color';

  static Future<ProgressBarStyle> loadStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefStyleKey);
      for (final style in ProgressBarStyle.values) {
        if (style.name == saved) return style;
      }
    } catch (_) {}
    return ProgressBarStyle.cardSweep;
  }

  static Future<void> saveStyle(ProgressBarStyle style) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefStyleKey, style.name);
    } catch (_) {}
  }

  static Future<ProgressColorPreset> loadColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefColorKey);
      for (final preset in ProgressColorPreset.values) {
        if (preset.name == saved) return preset;
      }
    } catch (_) {}
    return ProgressColorPreset.dodgerBlue;
  }

  static Future<void> saveColor(ProgressColorPreset preset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefColorKey, preset.name);
    } catch (_) {}
  }
}

/// Wraps a video queue card's content with a smoothly animated progress layer.
class AnimatedCardProgressOverlay extends StatelessWidget {
  final double progress;
  final bool showProgress;
  final ProgressBarStyle style;
  final ProgressColorPreset colorPreset;
  final bool isDark;
  final Widget child;

  const AnimatedCardProgressOverlay({
    super.key,
    required this.progress,
    required this.showProgress,
    required this.style,
    required this.colorPreset,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final target = showProgress ? progress.clamp(0.0, 1.0) : 0.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final bool hasSweep =
            style == ProgressBarStyle.cardSweep ||
            style == ProgressBarStyle.dualGlow;
        final bool hasBottomLine =
            style == ProgressBarStyle.bottomLine ||
            style == ProgressBarStyle.dualGlow;

        final bool visible = showProgress && value > 0.001;

        return Stack(
          children: [
            Container(
              decoration: (visible && hasSweep)
                  ? BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorPreset.deep.withValues(
                            alpha: isDark ? 0.28 : 0.16,
                          ),
                          colorPreset.primary.withValues(
                            alpha: isDark ? 0.34 : 0.22,
                          ),
                          colorPreset.light.withValues(
                            alpha: isDark ? 0.42 : 0.28,
                          ),
                          Colors.transparent,
                        ],
                        stops: [
                          0.0,
                          (value - 0.06).clamp(0.0, 1.0),
                          value,
                          value,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    )
                  : null,
              child: child,
            ),
            if (visible && hasBottomLine)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 3.5,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: constraints.maxWidth * value,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorPreset.deep,
                                colorPreset.primary,
                                colorPreset.light,
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Smooth global progress bar with frame & percentage telemetry.
class GlobalMergeProgressBar extends StatelessWidget {
  final double progress;
  final int currentFrame;
  final int totalFrames;
  final ProgressColorPreset colorPreset;
  final bool isDark;
  final String trailingLabel;

  const GlobalMergeProgressBar({
    super.key,
    required this.progress,
    required this.currentFrame,
    required this.totalFrames,
    required this.colorPreset,
    required this.isDark,
    this.trailingLabel = 'Pass-Through (-c copy)',
  });

  @override
  Widget build(BuildContext context) {
    final target = progress.clamp(0.0, 1.0);
    final trackColor = colorPreset.primary.withValues(
      alpha: isDark ? 0.18 : 0.14,
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final pctText = '${(value * 100).toStringAsFixed(0)}%';
        final frameText = totalFrames > 0
            ? 'Frame $currentFrame / $totalFrames'
            : 'Frame $currentFrame';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$frameText  •  $pctText',
                  style: TextStyle(
                    color: isDark ? colorPreset.light : colorPreset.deep,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  trailingLabel,
                  style: TextStyle(
                    color: colorPreset.primary.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 7,
                width: double.infinity,
                color: trackColor,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: constraints.maxWidth * value,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [
                              colorPreset.deep,
                              colorPreset.primary,
                              colorPreset.light,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorPreset.primary.withValues(
                                alpha: 0.45,
                              ),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
