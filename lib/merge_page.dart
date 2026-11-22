import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'file_tree_picker.dart';
import 'floating_toast.dart';
import 'progress_style.dart';
import 'settings_page.dart';
import 'trim_panel.dart';
import 'video_service.dart';

class VideoItem {
  final String path;
  final String name;
  String? thumbPath;
  VideoMetadata? metadata;

  int startFrame = 0;
  int endFrame = 0;

  VideoItem(this.path) : name = path.split('/').last;
}

class MergePage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ProgressBarStyle progressStyle;
  final ValueChanged<ProgressBarStyle> onProgressStyleChanged;
  final ProgressColorPreset progressColor;
  final ValueChanged<ProgressColorPreset> onProgressColorChanged;

  const MergePage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.progressStyle,
    required this.onProgressStyleChanged,
    required this.progressColor,
    required this.onProgressColorChanged,
  });

  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  static const int _maxConsoleLines = 300;

  final List<VideoItem> _videoItems = [];
  bool _isMerging = false;
  bool _hasMerged = false;
  bool _isConsoleExpanded = false;

  Timer? _timer;
  int _mergeSeconds = 0;
  int _currentGlobalFrame = 0;
  int _totalMergeFrames = 0;

  String _currentCommand = '';
  final List<String> _consoleLogs = [];
  final ScrollController _consoleScrollController = ScrollController();

  String? _customTargetFolder;
  String? _customOutputFileName;

  double _trimStartSeconds = 0.0;
  double _trimEndSeconds = 0.0;

  bool get _isTrimMode => _videoItems.length == 1;

  void _syncTrimRangeIfSingle() {
    if (_videoItems.length == 1) {
      final dur = _videoItems.first.metadata?.durationSeconds ?? 0.0;
      _trimStartSeconds = 0.0;
      _trimEndSeconds = dur;
    } else {
      _trimStartSeconds = 0.0;
      _trimEndSeconds = 0.0;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _consoleScrollController.dispose();
    super.dispose();
  }

  String _computeDefaultFileName() {
    if (_videoItems.isEmpty) return 'output_merged.mp4';
    final suffix = _isTrimMode ? '_trimmed' : '_merged';
    final firstName = _videoItems.first.name;
    final dotIndex = firstName.lastIndexOf('.');
    if (dotIndex > 0) {
      final base = firstName.substring(0, dotIndex);
      final ext = firstName.substring(dotIndex).toLowerCase();
      final safeExt =
          VideoService.supportedExtensions.contains(ext) ? ext : '.mp4';
      return '$base$suffix$safeExt';
    }
    return '$firstName$suffix.mp4';
  }

  String get _resolvedOutputFileName =>
      (_customOutputFileName != null && _customOutputFileName!.trim().isNotEmpty)
          ? _customOutputFileName!.trim()
          : _computeDefaultFileName();

  String get _resolvedOutputDirectory {
    if (_customTargetFolder != null) return _customTargetFolder!;
    if (_videoItems.isNotEmpty) return File(_videoItems.first.path).parent.path;
    return 'Default (Same as 1st video)';
  }

  Future<List<String>?> _openFilePicker({
    required bool pickFolderMode,
    List<String> allowedExtensions = const [],
    required String permissionDeniedMessage,
  }) async {
    final hasPermission = await VideoService.requestStoragePermission();
    if (!hasPermission) {
      _showToast(permissionDeniedMessage, type: ToastType.warning);
      return null;
    }
    if (!mounted) return null;

    return Navigator.push<List<String>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => MultiFileTreePicker(
          allowedExtensions: allowedExtensions,
          pickFolderMode: pickFolderMode,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _addFiles() async {
    final allowedExtensions = await VideoService.getAllSupportedExtensions();
    final selectedPaths = await _openFilePicker(
      pickFolderMode: false,
      allowedExtensions: allowedExtensions,
      permissionDeniedMessage:
          'Storage permission is required to browse video files.',
    );

    if (selectedPaths == null || selectedPaths.isEmpty || !mounted) return;

    if (_hasMerged) {
      setState(() {
        _hasMerged = false;
        _currentGlobalFrame = 0;
        _consoleLogs.clear();
        _currentCommand = '';
      });
    }

    for (final path in selectedPaths) {
      if (_videoItems.any((item) => item.path == path)) continue;

      final newItem = VideoItem(path);
      setState(() {
        _videoItems.add(newItem);
        if (_videoItems.length != 1) {
          _trimStartSeconds = 0.0;
          _trimEndSeconds = 0.0;
        }
      });

      VideoService.generateThumbnail(path).then((thumb) {
        if (mounted) setState(() => newItem.thumbPath = thumb);
      });

      VideoService.getVideoMetadata(path).then((meta) {
        if (mounted) {
          setState(() {
            newItem.metadata = meta;
            if (_videoItems.length == 1 && _videoItems.first == newItem) {
              _trimStartSeconds = 0.0;
              _trimEndSeconds = meta.durationSeconds;
            }
          });
        }
      });
    }
  }

  Future<void> _selectTargetFolder() async {
    final selectedFolder = await _openFilePicker(
      pickFolderMode: true,
      permissionDeniedMessage:
          'Storage permission is required to choose a folder.',
    );

    if (selectedFolder != null && selectedFolder.isNotEmpty && mounted) {
      setState(() => _customTargetFolder = selectedFolder.first);
    }
  }

  Future<void> _editOutputFileName() async {
    final controller = TextEditingController(text: _resolvedOutputFileName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Output Filename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. merged_video.mp4',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Reset Default'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result != null && mounted) {
      setState(() {
        _customOutputFileName = result.isEmpty ? null : result;
      });
    }
  }

  void _clearQueue() {
    if (_isMerging || _videoItems.isEmpty) return;
    setState(() {
      _videoItems.clear();
      _hasMerged = false;
      _currentGlobalFrame = 0;
      _trimStartSeconds = 0.0;
      _trimEndSeconds = 0.0;
      _consoleLogs.clear();
      _currentCommand = '';
      _customOutputFileName = null;
    });
  }

  void _stopOperation() {
    if (!_isMerging) return;

    final action = _isTrimMode ? 'Trim' : 'Merge';
    VideoService.cancelCurrentOperation();
    _stopTimer();

    setState(() {
      _isMerging = false;
      _appendLog('[USER ACTION] $action pipeline manually terminated.');
    });
    _scrollToBottom();
    _showToast('$action force-stopped.', type: ToastType.warning);
  }

  void _startTimer() {
    _stopTimer();
    _mergeSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _mergeSeconds++);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _appendLog(String line) {
    _consoleLogs.add(line);
    if (_consoleLogs.length > _maxConsoleLines) {
      _consoleLogs.removeRange(0, _consoleLogs.length - _maxConsoleLines);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScrollController.hasClients) {
        _consoleScrollController.jumpTo(
          _consoleScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  Future<void> _copyLogs() async {
    final text = [
      if (_currentCommand.isNotEmpty) '\$ $_currentCommand',
      ..._consoleLogs,
    ].join('\n');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _showToast('Console logs copied to clipboard.');
  }

  Future<void> _runPipelineJob({
    required String commandDisplay,
    required int totalFrames,
    required String successVerb,
    required String failMessage,
    required Future<String?> Function(
      Function(int) onProgressFrames,
      Function(String) onLogReceived,
    )
    runner,
  }) async {
    setState(() {
      _consoleLogs.clear();
      _hasMerged = false;
      _isMerging = true;
      _isConsoleExpanded = true;
      _currentGlobalFrame = 0;
      _totalMergeFrames = totalFrames;
      _currentCommand = commandDisplay;
    });
    _startTimer();

    final outputPath = await runner(
      (currentFrame) {
        if (mounted) {
          setState(() => _currentGlobalFrame = currentFrame);
        }
      },
      (logLine) {
        if (mounted) {
          setState(() => _appendLog(logLine));
          _scrollToBottom();
        }
      },
    );

    _stopTimer();
    if (!mounted) return;

    setState(() {
      _isMerging = false;
      if (outputPath != null) {
        _hasMerged = true;
      }
    });

    if (outputPath != null) {
      final fileName = outputPath.split('/').last;
      _showToast(
        '$successVerb in ${_mergeSeconds}s • $fileName',
        type: ToastType.success,
      );
    } else {
      if (_consoleLogs.isNotEmpty &&
          _consoleLogs.last.contains('[USER ACTION]')) {
        return;
      }
      _showToast(failMessage, type: ToastType.error);
    }
  }

  Future<void> _startTrim() async {
    if (_videoItems.length != 1) return;
    final item = _videoItems.first;
    final duration = _trimEndSeconds - _trimStartSeconds;
    if (duration <= 0) {
      _showToast('Invalid trim range.', type: ToastType.warning);
      return;
    }

    final finalOutputDirPath =
        _customTargetFolder ?? File(item.path).parent.path;
    final computedOutPath = '$finalOutputDirPath/$_resolvedOutputFileName';

    final fps =
        (item.metadata?.fpsValue ?? 0.0) > 0 ? item.metadata!.fpsValue : 30.0;
    final expectedFrames = (duration * fps).round().clamp(1, 1 << 30);

    item.startFrame = 0;
    item.endFrame = expectedFrames;

    await _runPipelineJob(
      commandDisplay:
          'ffmpeg -y -ss ${_trimStartSeconds.toStringAsFixed(3)} -i "${item.name}" -t ${duration.toStringAsFixed(3)} -c copy -avoid_negative_ts make_zero "$computedOutPath"',
      totalFrames: expectedFrames,
      successVerb: 'Trimmed',
      failMessage: 'Trim failed. Check console logs for details.',
      runner: (onProgress, onLog) => VideoService.trimVideoDirectly(
        inputPath: item.path,
        startSeconds: _trimStartSeconds,
        endSeconds: _trimEndSeconds,
        expectedFrames: expectedFrames,
        outputPath: computedOutPath,
        onProgressFrames: onProgress,
        onLogReceived: onLog,
      ),
    );
  }

  Future<void> _startMerge() async {
    if (_videoItems.isEmpty) {
      _showToast('Add at least one video file first.');
      return;
    }

    final finalOutputDirPath =
        _customTargetFolder ?? File(_videoItems.first.path).parent.path;
    final computedOutPath = '$finalOutputDirPath/$_resolvedOutputFileName';

    int currentOffsetFrames = 0;
    for (final item in _videoItems) {
      item.startFrame = currentOffsetFrames;
      final itemFrames = item.metadata?.totalFrames ?? 0;
      item.endFrame = currentOffsetFrames + itemFrames;
      currentOffsetFrames = item.endFrame;
    }

    final paths = _videoItems.map((item) => item.path).toList();

    await _runPipelineJob(
      commandDisplay:
          'ffmpeg -y -f concat -safe 0 -i merge_list.txt -c copy "$computedOutPath"',
      totalFrames: currentOffsetFrames,
      successVerb: 'Merged',
      failMessage: 'Merge failed. Check stream compatibility or logs.',
      runner: (onProgress, onLog) => VideoService.mergeVideosDirectly(
        filePaths: paths,
        totalFrames: currentOffsetFrames,
        outputPath: computedOutPath,
        onProgressFrames: onProgress,
        onLogReceived: onLog,
      ),
    );
  }

  void _showToast(String message, {ToastType type = ToastType.info}) {
    if (!mounted) return;
    FloatingToast.show(context, message, type: type);
  }

  void _showCompatibilityDialog(StreamCompatibilityResult compatibility) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              compatibility.isCompatible
                  ? Icons.verified_rounded
                  : Icons.warning_amber_rounded,
              color: compatibility.isCompatible ? Colors.green : Colors.amber,
            ),
            const SizedBox(width: 8),
            Text(
              compatibility.isCompatible
                  ? 'Streams Aligned'
                  : 'Compatibility Warning',
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compatibility.isCompatible)
                const Text(
                  'All clips share matching codec, resolution, timebase, FPS, pixel format, and audio parameters for safe lossless (-c copy) merging.',
                  style: TextStyle(fontSize: 13),
                )
              else ...[
                const Text(
                  'Detected differences that may cause broken timelines, audio desync, or playback glitches with -c copy:',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                for (final w in compatibility.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $w',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              for (int i = 0; i < _videoItems.length; i++) ...[
                Text(
                  '#${i + 1} ${_videoItems[i].name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_videoItems[i].metadata != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(
                      '${_videoItems[i].metadata!.resolution} • ${_videoItems[i].metadata!.fps}\n'
                      '${_formatVideoStreamLine(_videoItems[i].metadata!)}\n'
                      '${_formatAudioAndBitrateLine(_videoItems[i].metadata!)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          currentThemeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          currentProgressStyle: widget.progressStyle,
          onProgressStyleChanged: widget.onProgressStyleChanged,
          currentProgressColor: widget.progressColor,
          onProgressColorChanged: widget.onProgressColorChanged,
        ),
      ),
    );
  }

  Widget _buildMetaBadge(String? text, MaterialColor color) {
    if (text == null || text.isEmpty || text == 'Unknown' || text == 'null') {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: color.withValues(alpha: 0.32),
          width: 0.6,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _isDark ? color[300] : color[800],
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compatibility = VideoService.checkCompatibility(
      _videoItems.map((e) => e.metadata).toList(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.merge_type_rounded, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text(
              'VideoToolKit',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
          ],
        ),
        actions: [
          if (_videoItems.isNotEmpty && !_isMerging)
            IconButton(
              tooltip: 'Clear queue',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearQueue,
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildOutputSettingsCard(colorScheme),
          if (_videoItems.isNotEmpty)
            _buildQueueSummaryBar(colorScheme, compatibility),
          Expanded(
            child: _videoItems.isEmpty
                ? _buildEmptyState(colorScheme)
                : _isTrimMode
                    ? _buildTrimWorkspace(colorScheme)
                    : _buildVideoList(colorScheme),
          ),
          if (_videoItems.isNotEmpty) _buildConsolePanel(colorScheme),
          if (_isMerging || _hasMerged) _buildActiveProgressBanner(),
          _buildBottomActionBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildOutputSettingsCard(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _isMerging ? null : _selectTargetFolder,
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Target Directory',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _resolvedOutputDirectory,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontFamily: 'monospace',
                              color: _customTargetFolder != null
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_customTargetFolder != null && !_isMerging)
                      IconButton(
                        tooltip: 'Reset to default folder',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.restart_alt_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () =>
                            setState(() => _customTargetFolder = null),
                      ),
                    if (!_isMerging)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
              if (_videoItems.isNotEmpty) ...[
                Divider(
                  height: 14,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _isMerging ? null : _editOutputFileName,
                  child: Row(
                    children: [
                      Icon(
                        Icons.drive_file_rename_outline_rounded,
                        size: 18,
                        color: colorScheme.secondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _resolvedOutputFileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (!_isMerging)
                        Text(
                          'Rename',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueSummaryBar(
    ColorScheme colorScheme,
    StreamCompatibilityResult compatibility,
  ) {
    final totalSecs = _videoItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.metadata?.durationSeconds ?? 0.0),
    );
    final totalBytes = _videoItems.fold<int>(
      0,
      (sum, item) => sum + (item.metadata?.sizeBytes ?? 0),
    );

    final summaryParts = <String>[
      '${_videoItems.length} ${_videoItems.length == 1 ? 'clip' : 'clips'}',
      if (totalSecs > 0) VideoService.formatDuration(totalSecs),
      if (totalBytes > 0) VideoService.formatBytes(totalBytes),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summaryParts.join(' • '),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_videoItems.length >= 2)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showCompatibilityDialog(compatibility),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (compatibility.isCompatible
                          ? Colors.green
                          : Colors.amber)
                      .withValues(alpha: _isDark ? 0.18 : 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      compatibility.isCompatible
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      size: 13,
                      color: compatibility.isCompatible
                          ? (_isDark
                              ? Colors.green[300]
                              : Colors.green[800])
                          : (_isDark
                              ? Colors.amber[300]
                              : Colors.amber[900]),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      compatibility.isCompatible
                          ? 'Stream Aligned'
                          : compatibility.warnings.length > 1
                              ? '${compatibility.warnings.length} Mismatches'
                              : compatibility.warnings.first,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: compatibility.isCompatible
                            ? (_isDark
                                ? Colors.green[300]
                                : Colors.green[800])
                            : (_isDark
                                ? Colors.amber[300]
                                : Colors.amber[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.video_library_outlined,
                size: 44,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Videos in Queue',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select 1 video to trim losslessly, or 2+ videos to merge.\nDrag items to reorder before merging.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrimWorkspace(ColorScheme colorScheme) {
    final item = _videoItems.first;
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      children: [
        _buildVideoCard(item, 0, colorScheme, showDragHandle: false),
        TrimPanel(
          videoPath: item.path,
          metadata: item.metadata,
          startSeconds: _trimStartSeconds,
          endSeconds: _trimEndSeconds,
          enabled: !_isMerging,
          accentPreset: widget.progressColor,
          onRangeChanged: (startSec, endSec) {
            setState(() {
              _hasMerged = false;
              _trimStartSeconds = startSec;
              _trimEndSeconds = endSec;
            });
          },
        ),
      ],
    );
  }

  Widget _buildVideoList(ColorScheme colorScheme) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: _videoItems.length,
      onReorderItem: (oldIndex, newIndex) {
        if (_isMerging) return;
        setState(() {
          _hasMerged = false;
          final item = _videoItems.removeAt(oldIndex);
          _videoItems.insert(newIndex, item);
        });
      },
      itemBuilder: (context, i) => _buildVideoCard(
        _videoItems[i],
        i,
        colorScheme,
        showDragHandle: true,
      ),
    );
  }

  Widget _buildVideoCard(
    VideoItem item,
    int i,
    ColorScheme colorScheme, {
    required bool showDragHandle,
  }) {
    final localProgress = _computeLocalProgress(item);
    final isActiveSlot =
        _isMerging && localProgress > 0.0 && localProgress < 1.0;

    return Card(
          key: ValueKey(item.path),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isActiveSlot
                  ? widget.progressColor.primary
                  : colorScheme.outlineVariant.withValues(
                      alpha: _isDark ? 0.35 : 0.6,
                    ),
              width: isActiveSlot ? 1.8 : 1.0,
            ),
          ),
          child: AnimatedCardProgressOverlay(
            progress: localProgress,
            showProgress: _isMerging || _hasMerged,
            style: widget.progressStyle,
            colorPreset: widget.progressColor,
            isDark: _isDark,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              leading: _buildThumbnailWithIndex(item, i, colorScheme),
              title: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              subtitle: item.metadata == null
                  ? Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Inspecting media streams...',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            _buildMetaBadge(
                              item.metadata!.resolution,
                              Colors.blue,
                            ),
                            _buildMetaBadge(
                              item.metadata!.duration,
                              Colors.cyan,
                            ),
                            _buildMetaBadge(item.metadata!.fps, Colors.teal),
                            _buildMetaBadge(
                              item.metadata!.size,
                              Colors.blueGrey,
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _formatVideoStreamLine(item.metadata!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatAudioAndBitrateLine(item.metadata!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
              trailing: (_isMerging || _hasMerged)
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${(localProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isActiveSlot
                              ? (_isDark
                                  ? widget.progressColor.light
                                  : widget.progressColor.primary)
                              : widget.progressColor.deep,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Remove',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: colorScheme.error,
                          ),
                          onPressed: () {
                            setState(() {
                              _videoItems.removeAt(i);
                              _hasMerged = false;
                              _syncTrimRangeIfSingle();
                            });
                          },
                        ),
                        if (showDragHandle)
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        );
  }

  String _formatVideoStreamLine(VideoMetadata meta) {
    final parts = <String>[];
    if (meta.videoCodec != 'Unknown') {
      final profile =
          meta.videoProfile != 'Unknown' ? ' (${meta.videoProfile})' : '';
      parts.add('${meta.videoCodec}$profile');
    }
    if (meta.pixelFormat != 'Unknown') {
      parts.add(meta.pixelFormat);
    }
    if (meta.videoTimeBase != 'Unknown') {
      parts.add('TB ${meta.videoTimeBase}');
    }
    return parts.isEmpty ? 'Video: Unknown' : parts.join(' • ');
  }

  String _formatAudioAndBitrateLine(VideoMetadata meta) {
    final audioExtras = <String>[
      if (meta.audioSampleRate != 'Unknown') meta.audioSampleRate,
      if (meta.audioChannelLayout != 'Unknown') meta.audioChannelLayout,
    ];
    final audioText = audioExtras.isEmpty
        ? meta.audioCodec
        : '${meta.audioCodec} (${audioExtras.join(', ')})';

    final parts = <String>[
      audioText,
      if (meta.bitrate != 'Unknown') meta.bitrate,
      if (meta.totalFrames > 0) '${meta.totalFrames}f',
    ];
    return parts.join('  |  ');
  }

  double _computeLocalProgress(VideoItem item) {
    if (_hasMerged) return 1.0;
    if (!_isMerging) return 0.0;
    if (_currentGlobalFrame < item.startFrame) return 0.0;
    if (_currentGlobalFrame > item.endFrame) return 1.0;
    final totalItemFrames = item.endFrame - item.startFrame;
    if (totalItemFrames <= 0) return 0.0;
    return ((_currentGlobalFrame - item.startFrame) / totalItemFrames)
        .clamp(0.0, 1.0);
  }

  Widget _buildThumbnailWithIndex(
    VideoItem item,
    int index,
    ColorScheme colorScheme,
  ) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: item.thumbPath != null
              ? Image.file(
                  File(item.thumbPath!),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _buildThumbFallback(colorScheme),
                )
              : _buildThumbFallback(colorScheme),
        ),
        Positioned(
          top: 2,
          left: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '#${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbFallback(ColorScheme colorScheme) {
    return Container(
      width: 56,
      height: 56,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.movie_outlined, color: colorScheme.primary),
    );
  }

  Widget _buildConsolePanel(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () =>
                setState(() => _isConsoleExpanded = !_isConsoleExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.terminal_rounded,
                    size: 14,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'CONSOLE LOGS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (_consoleLogs.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${_consoleLogs.length})',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_consoleLogs.isNotEmpty)
                    InkWell(
                      onTap: _copyLogs,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  Icon(
                    _isConsoleExpanded
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 18,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          if (_isConsoleExpanded) ...[
            const Divider(color: Colors.white12, height: 1),
            SizedBox(
              height: 112,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_currentCommand.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '\$ $_currentCommand',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    Expanded(
                      child: _consoleLogs.isEmpty
                          ? const Center(
                              child: Text(
                                'System idle. Ready for FFmpeg stream output...',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11.5,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _consoleScrollController,
                              itemCount: _consoleLogs.length,
                              itemBuilder: (_, idx) => Text(
                                _consoleLogs[idx],
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveProgressBanner() {
    double globalProgress = 0.0;
    if (_hasMerged) {
      globalProgress = 1.0;
    } else if (_totalMergeFrames > 0) {
      globalProgress = (_currentGlobalFrame / _totalMergeFrames).clamp(0.0, 1.0);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: GlobalMergeProgressBar(
        progress: globalProgress,
        currentFrame: _hasMerged ? _totalMergeFrames : _currentGlobalFrame,
        totalFrames: _totalMergeFrames,
        colorPreset: widget.progressColor,
        isDark: _isDark,
        trailingLabel: _hasMerged ? 'Completed' : 'Pass-Through (-c copy)',
      ),
    );
  }

  Widget _buildBottomActionBar(ColorScheme colorScheme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: _isMerging
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _stopOperation,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop'),
                    )
                  : FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _addFiles,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Videos'),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: (_isMerging || _videoItems.isEmpty)
                    ? null
                    : (_isTrimMode ? _startTrim : _startMerge),
                icon: _isMerging
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _videoItems.isEmpty
                            ? Icons.hourglass_empty_rounded
                            : _isTrimMode
                                ? Icons.content_cut_rounded
                                : Icons.merge_type_rounded,
                      ),
                label: Text(
                  _isMerging
                      ? (_isTrimMode
                          ? 'Trimming (${_mergeSeconds}s)'
                          : 'Merging (${_mergeSeconds}s)')
                      : _videoItems.isEmpty
                          ? 'Waiting'
                          : _isTrimMode
                              ? 'Trim'
                              : 'Merge',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
