import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'progress_style.dart';
import 'video_service.dart';

enum _TrimHandle { start, end }

/// Coarse (time-based) + Fine (frame-based) trim editor with live start/end frame previews.
class TrimPanel extends StatefulWidget {
  final String videoPath;
  final VideoMetadata? metadata;
  final double startSeconds;
  final double endSeconds;
  final bool enabled;
  final ProgressColorPreset accentPreset;
  final void Function(double startSec, double endSec) onRangeChanged;

  const TrimPanel({
    super.key,
    required this.videoPath,
    required this.metadata,
    required this.startSeconds,
    required this.endSeconds,
    required this.enabled,
    required this.accentPreset,
    required this.onRangeChanged,
  });

  @override
  State<TrimPanel> createState() => _TrimPanelState();
}

class _TrimPanelState extends State<TrimPanel> {
  _TrimHandle _activeHandle = _TrimHandle.start;
  String? _startPreviewPath;
  String? _endPreviewPath;
  bool _loadingStart = false;
  bool _loadingEnd = false;

  Timer? _startDebounce;
  Timer? _endDebounce;
  int _startRequestSeq = 0;
  int _endRequestSeq = 0;

  bool _seekingKeyframe = false;
  bool _autoSnapKeyframe = true;
  double? _lastSnappedKf;

  double get _totalDuration => widget.metadata?.durationSeconds ?? 0.0;
  double get _fps =>
      (widget.metadata?.fpsValue ?? 0.0) > 0 ? widget.metadata!.fpsValue : 30.0;
  double get _frameDuration => 1.0 / _fps;
  double get _activeSeconds => _activeHandle == _TrimHandle.start
      ? widget.startSeconds
      : widget.endSeconds;

  int _secondsToFrame(double seconds) => (seconds * _fps).round();

  @override
  void initState() {
    super.initState();
    if (_totalDuration > 0) {
      _schedulePreview(_TrimHandle.start, widget.startSeconds, immediate: true);
      _schedulePreview(_TrimHandle.end, widget.endSeconds, immediate: true);
    }
  }

  @override
  void didUpdateWidget(covariant TrimPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pathChanged = oldWidget.videoPath != widget.videoPath;
    final metaJustLoaded =
        (oldWidget.metadata?.durationSeconds ?? 0) <= 0 && _totalDuration > 0;

    if (pathChanged || metaJustLoaded) {
      _startPreviewPath = null;
      _endPreviewPath = null;
      _lastSnappedKf = null;
      if (_totalDuration > 0) {
        _schedulePreview(
          _TrimHandle.start,
          widget.startSeconds,
          immediate: true,
        );
        _schedulePreview(_TrimHandle.end, widget.endSeconds, immediate: true);
      }
    }
  }

  void _applyHandlePosition(_TrimHandle handle, double targetSeconds) {
    if (!widget.enabled || _totalDuration <= 0) return;
    final minGap = _frameDuration;
    if (handle == _TrimHandle.start) {
      final nextStart = targetSeconds.clamp(
        0.0,
        (widget.endSeconds - minGap).clamp(0.0, _totalDuration),
      );
      widget.onRangeChanged(nextStart, widget.endSeconds);
      _schedulePreview(_TrimHandle.start, nextStart, immediate: true);
    } else {
      final nextEnd = targetSeconds.clamp(
        (widget.startSeconds + minGap).clamp(0.0, _totalDuration),
        _totalDuration,
      );
      widget.onRangeChanged(widget.startSeconds, nextEnd);
      _schedulePreview(_TrimHandle.end, nextEnd, immediate: true);
    }
  }

  Future<void> _seekKeyframe(
    _TrimHandle handle,
    Future<double?> Function() query,
  ) async {
    if (!widget.enabled || _seekingKeyframe || _totalDuration <= 0) return;
    final targetPath = widget.videoPath;
    setState(() => _seekingKeyframe = true);
    final kf = await query();
    if (!mounted || widget.videoPath != targetPath) return;
    setState(() {
      _seekingKeyframe = false;
      if (kf != null) _lastSnappedKf = kf;
    });
    if (kf != null) {
      _applyHandlePosition(handle, kf);
    }
  }

  @override
  void dispose() {
    _startDebounce?.cancel();
    _endDebounce?.cancel();
    super.dispose();
  }

  void _schedulePreview(
    _TrimHandle handle,
    double seconds, {
    bool immediate = false,
  }) {
    if (_totalDuration <= 0) return;

    if (handle == _TrimHandle.start) {
      _startDebounce?.cancel();
      final delay = immediate ? Duration.zero : const Duration(milliseconds: 200);
      _startDebounce = Timer(delay, () => _extractPreview(handle, seconds));
    } else {
      _endDebounce?.cancel();
      final delay = immediate ? Duration.zero : const Duration(milliseconds: 200);
      _endDebounce = Timer(delay, () => _extractPreview(handle, seconds));
    }
  }

  Future<void> _extractPreview(_TrimHandle handle, double seconds) async {
    if (!mounted) return;
    final isStart = handle == _TrimHandle.start;
    final seq = isStart ? ++_startRequestSeq : ++_endRequestSeq;

    setState(() {
      if (isStart) {
        _loadingStart = true;
      } else {
        _loadingEnd = true;
      }
    });

    // Clamp slightly inside duration so the final frame decodes reliably
    final safeSec = seconds.clamp(
      0.0,
      (_totalDuration - _frameDuration).clamp(0.0, _totalDuration),
    );
    final path = await VideoService.extractFramePreview(
      widget.videoPath,
      safeSec,
      tag: isStart ? 's' : 'e',
    );

    if (!mounted) return;
    if (isStart && seq != _startRequestSeq) return;
    if (!isStart && seq != _endRequestSeq) return;

    setState(() {
      if (isStart) {
        _startPreviewPath = path;
        _loadingStart = false;
      } else {
        _endPreviewPath = path;
        _loadingEnd = false;
      }
    });
  }

  void _stepActiveBySeconds(double deltaSeconds) {
    _applyHandlePosition(_activeHandle, _activeSeconds + deltaSeconds);
  }

  void _stepActiveByFrames(int deltaFrames) {
    _stepActiveBySeconds(deltaFrames * _frameDuration);
  }

  Future<void> _editTimestampDialog(_TrimHandle handle) async {
    if (!widget.enabled || _totalDuration <= 0) return;
    final isStart = handle == _TrimHandle.start;
    final current = isStart ? widget.startSeconds : widget.endSeconds;
    final controller = TextEditingController(
      text: current.toStringAsFixed(3),
    );

    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isStart ? 'Set Start Time (sec)' : 'Set End Time (sec)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: '0.000 ~ ${_totalDuration.toStringAsFixed(3)}',
            helperText: 'Supports seconds (e.g. 12.5) or MM:SS.mmm',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (raw == null || raw.isEmpty || !mounted) return;
    final parsed = _parseFlexibleTimestamp(raw);
    if (parsed == null) return;
    _applyHandlePosition(handle, parsed);
  }

  double? _parseFlexibleTimestamp(String input) {
    final direct = double.tryParse(input);
    if (direct != null) return direct;
    final parts = input.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = double.tryParse(parts[1]);
      if (m != null && s != null) return m * 60 + s;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final s = double.tryParse(parts[2]);
      if (h != null && m != null && s != null) return h * 3600 + m * 60 + s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accentPreset.primary;

    if (widget.metadata == null || _totalDuration <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading timeline & frame index...',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedDuration = (widget.endSeconds - widget.startSeconds).clamp(
      0.0,
      _totalDuration,
    );
    final activeFrame = _secondsToFrame(_activeSeconds);
    final totalFrames = widget.metadata!.totalFrames > 0
        ? widget.metadata!.totalFrames
        : _secondsToFrame(_totalDuration);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(Icons.content_cut_rounded, size: 18, color: accent),
                  const SizedBox(width: 8),
                  const Text(
                    'Trim Range',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Clip: ${VideoService.formatTimestamp(selectedDuration)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: isDark
                            ? widget.accentPreset.light
                            : widget.accentPreset.deep,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Side-by-side Start & End frame previews (tap to focus fine control)
              Row(
                children: [
                  Expanded(
                    child: _buildPreviewTile(
                      handle: _TrimHandle.start,
                      label: 'START',
                      seconds: widget.startSeconds,
                      previewPath: _startPreviewPath,
                      isLoading: _loadingStart,
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPreviewTile(
                      handle: _TrimHandle.end,
                      label: 'END',
                      seconds: widget.endSeconds,
                      previewPath: _endPreviewPath,
                      isLoading: _loadingEnd,
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 1. Coarse selection (Time RangeSlider)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Coarse • Time',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Total: ${VideoService.formatTimestamp(_totalDuration)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent,
                  inactiveTrackColor: accent.withValues(alpha: 0.18),
                  thumbColor: accent,
                  overlayColor: accent.withValues(alpha: 0.16),
                ),
                child: RangeSlider(
                  values: RangeValues(
                    widget.startSeconds.clamp(0.0, _totalDuration),
                    widget.endSeconds.clamp(0.0, _totalDuration),
                  ),
                  min: 0.0,
                  max: _totalDuration,
                  onChanged: widget.enabled
                      ? (values) {
                          final minGap = _frameDuration;
                          if (values.end - values.start < minGap) return;
                          final startMoved =
                              (values.start - widget.startSeconds).abs() >
                              0.0005;
                          final endMoved =
                              (values.end - widget.endSeconds).abs() > 0.0005;

                          setState(() {
                            if (startMoved && !endMoved) {
                              _activeHandle = _TrimHandle.start;
                            } else if (endMoved && !startMoved) {
                              _activeHandle = _TrimHandle.end;
                            }
                          });
                          widget.onRangeChanged(values.start, values.end);
                          if (startMoved) {
                            _schedulePreview(_TrimHandle.start, values.start);
                          }
                          if (endMoved) {
                            _schedulePreview(_TrimHandle.end, values.end);
                          }
                        }
                      : null,
                  onChangeEnd: widget.enabled &&
                          _autoSnapKeyframe &&
                          _activeHandle == _TrimHandle.start
                      ? (values) {
                          _seekKeyframe(
                            _TrimHandle.start,
                            () => VideoService.queryNearestKeyframe(
                              widget.videoPath,
                              values.start,
                            ),
                          );
                        }
                      : null,
                ),
              ),

              // Quick coarse time step buttons (-5s, -1s, +1s, +5s)
              Row(
                children: [
                  _buildStepButton('-5s', () => _stepActiveBySeconds(-5.0)),
                  const SizedBox(width: 6),
                  _buildStepButton('-1s', () => _stepActiveBySeconds(-1.0)),
                  const SizedBox(width: 6),
                  _buildStepButton('+1s', () => _stepActiveBySeconds(1.0)),
                  const SizedBox(width: 6),
                  _buildStepButton('+5s', () => _stepActiveBySeconds(5.0)),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 10),

              // Context-aware fine control:
              // START -> Keyframe alignment (lossless -c copy cuts start at keyframes)
              // END   -> Frame-level stepping (end cut can stop at any frame)
              if (_activeHandle == _TrimHandle.start)
                _buildKeyframeSection(colorScheme, isDark)
              else
                _buildEndFrameSection(
                  colorScheme,
                  isDark,
                  activeFrame: activeFrame,
                  totalFrames: totalFrames,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndFrameSection(
    ColorScheme colorScheme,
    bool isDark, {
    required int activeFrame,
    required int totalFrames,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 15,
                  color: widget.accentPreset.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  'Fine • End Frame',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Text(
              'Frame #$activeFrame / $totalFrames (${_fps.toStringAsFixed(0)} FPS)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: isDark
                    ? widget.accentPreset.light
                    : widget.accentPreset.deep,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStepButton(
              '-10f',
              () => _stepActiveByFrames(-10),
              accentBorder: true,
            ),
            const SizedBox(width: 6),
            _buildStepButton(
              '-1f',
              () => _stepActiveByFrames(-1),
              accentBorder: true,
            ),
            const SizedBox(width: 6),
            _buildStepButton(
              '+1f',
              () => _stepActiveByFrames(1),
              accentBorder: true,
            ),
            const SizedBox(width: 6),
            _buildStepButton(
              '+10f',
              () => _stepActiveByFrames(10),
              accentBorder: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewTile({
    required _TrimHandle handle,
    required String label,
    required double seconds,
    required String? previewPath,
    required bool isLoading,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    final isSelected = _activeHandle == handle;
    final accent = widget.accentPreset.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _activeHandle = handle),
      onLongPress: () => _editTimestampDialog(handle),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? accent
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
            width: isSelected ? 1.8 : 1.0,
          ),
          color: colorScheme.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.25 : 0.45,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (previewPath != null)
                    Image.file(
                      File(previewPath),
                      key: ValueKey(previewPath),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (isLoading)
                    Container(
                      color: Colors.black26,
                      child: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent
                            : Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                setState(() => _activeHandle = handle);
                _editTimestampDialog(handle);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      VideoService.formatTimestamp(seconds),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: isSelected
                            ? (isDark
                                ? widget.accentPreset.light
                                : widget.accentPreset.deep)
                            : colorScheme.onSurface,
                      ),
                    ),
                    Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyframeSection(ColorScheme colorScheme, bool isDark) {
    final accent = widget.accentPreset.primary;
    final isOnLastKf =
        _lastSnappedKf != null && (_lastSnappedKf! - _activeSeconds).abs() <= 0.02;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.key_rounded, size: 15, color: accent),
            const SizedBox(width: 5),
            Text(
              'Fine • Start Keyframe',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            if (_seekingKeyframe)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: accent,
                ),
              ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.enabled
                  ? () => setState(() => _autoSnapKeyframe = !_autoSnapKeyframe)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _autoSnapKeyframe
                      ? accent.withValues(alpha: isDark ? 0.24 : 0.14)
                      : colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _autoSnapKeyframe
                        ? accent.withValues(alpha: 0.65)
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _autoSnapKeyframe
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 12,
                      color: _autoSnapKeyframe
                          ? (isDark
                              ? widget.accentPreset.light
                              : widget.accentPreset.deep)
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _autoSnapKeyframe ? 'Auto-Snap ON' : 'Auto-Snap OFF',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _autoSnapKeyframe
                            ? (isDark
                                ? widget.accentPreset.light
                                : widget.accentPreset.deep)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStepButton(
              '◀ Prev KF',
              _seekingKeyframe
                  ? null
                  : () => _seekKeyframe(
                        _activeHandle,
                        () => VideoService.queryPrevKeyframe(
                          widget.videoPath,
                          _activeSeconds,
                        ),
                      ),
              accentBorder: true,
            ),
            const SizedBox(width: 6),
            _buildStepButton(
              isOnLastKf ? 'On KF ✓' : 'Snap KF',
              _seekingKeyframe
                  ? null
                  : () => _seekKeyframe(
                        _activeHandle,
                        () => VideoService.queryNearestKeyframe(
                          widget.videoPath,
                          _activeSeconds,
                        ),
                      ),
              accentBorder: true,
            ),
            const SizedBox(width: 6),
            _buildStepButton(
              'Next KF ▶',
              _seekingKeyframe
                  ? null
                  : () => _seekKeyframe(
                        _activeHandle,
                        () => VideoService.queryNextKeyframe(
                          widget.videoPath,
                          _activeSeconds,
                          _totalDuration,
                        ),
                      ),
              accentBorder: true,
            ),
          ],
        ),
        if (_lastSnappedKf != null) ...[
          const SizedBox(height: 6),
          Text(
            isOnLastKf
                ? 'Aligned to keyframe ${VideoService.formatTimestamp(_lastSnappedKf!)}'
                : 'Last keyframe: ${VideoService.formatTimestamp(_lastSnappedKf!)} (lossless -c copy cuts at keyframes)',
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepButton(
    String label,
    VoidCallback? onPressed, {
    bool accentBorder = false,
  }) {
    final accent = widget.accentPreset.primary;
    return Expanded(
      child: OutlinedButton(
        onPressed: widget.enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          visualDensity: VisualDensity.compact,
          side: accentBorder
              ? BorderSide(color: accent.withValues(alpha: 0.5))
              : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
