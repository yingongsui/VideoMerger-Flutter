import 'dart:async';
import 'package:flutter/material.dart';

enum ToastType { info, success, warning, error }

/// Compact floating pill toast displayed via Overlay instead of a full-width bottom SnackBar.
class FloatingToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    dismiss();

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    late final IconData icon;
    late final Color accent;
    switch (type) {
      case ToastType.success:
        icon = Icons.check_circle_rounded;
        accent = const Color(0xFF10B981);
      case ToastType.warning:
        icon = Icons.warning_amber_rounded;
        accent = const Color(0xFFF59E0B);
      case ToastType.error:
        icon = Icons.error_outline_rounded;
        accent = const Color(0xFFEF4444);
      case ToastType.info:
        icon = Icons.info_outline_rounded;
        accent = const Color(0xFF1E90FF);
    }

    _currentEntry = OverlayEntry(
      builder: (ctx) => _FloatingToastWidget(
        message: message,
        icon: icon,
        accent: accent,
        isDark: isDark,
        onDismiss: dismiss,
      ),
    );

    overlay.insert(_currentEntry!);
    _dismissTimer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _FloatingToastWidget extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color accent;
  final bool isDark;
  final VoidCallback onDismiss;

  const _FloatingToastWidget({
    required this.message,
    required this.icon,
    required this.accent,
    required this.isDark,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight + 10;

    return Positioned(
      top: topPadding,
      left: 24,
      right: 24,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * -10),
              child: child,
            ),
          ),
          child: GestureDetector(
            onTap: onDismiss,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 340),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E2633).withValues(alpha: 0.96)
                      : const Color(0xFFFFFFFF).withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.45),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.45 : 0.14,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.94)
                              : const Color(0xFF1A1F29),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
