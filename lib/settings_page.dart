import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'floating_toast.dart';
import 'progress_style.dart';
import 'video_service.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ProgressBarStyle currentProgressStyle;
  final ValueChanged<ProgressBarStyle> onProgressStyleChanged;
  final ProgressColorPreset currentProgressColor;
  final ValueChanged<ProgressColorPreset> onProgressColorChanged;

  const SettingsPage({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.currentProgressStyle,
    required this.onProgressStyleChanged,
    required this.currentProgressColor,
    required this.onProgressColorChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  static const String _appName = 'VideoMerger';
  static const String _appVersion = 'v1.1.0';
  static const String _githubUrl =
      'https://github.com/yingongsui/VideoMerger-Flutter';

  late ThemeMode _selectedMode;
  late ProgressBarStyle _selectedProgressStyle;
  late ProgressColorPreset _selectedProgressColor;
  List<String> _customExtensions = [];
  final TextEditingController _extController = TextEditingController();

  late final AnimationController _previewController;
  double _previewProgress = 0.65;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.currentThemeMode;
    _selectedProgressStyle = widget.currentProgressStyle;
    _selectedProgressColor = widget.currentProgressColor;
    _previewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addListener(() {
        if (mounted) {
          setState(() => _previewProgress = _previewController.value);
        }
      });
    _loadCustomExtensions();
  }

  @override
  void dispose() {
    _previewController.dispose();
    _extController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomExtensions() async {
    final loaded = await VideoService.loadCustomExtensions();
    if (mounted) {
      setState(() => _customExtensions = loaded);
    }
  }

  void _updateThemeMode(ThemeMode mode) {
    setState(() => _selectedMode = mode);
    widget.onThemeModeChanged(mode);
  }

  void _updateProgressStyle(ProgressBarStyle style) {
    setState(() => _selectedProgressStyle = style);
    widget.onProgressStyleChanged(style);
  }

  void _updateProgressColor(ProgressColorPreset preset) {
    setState(() => _selectedProgressColor = preset);
    widget.onProgressColorChanged(preset);
  }

  void _replayPreview() {
    _previewController.forward(from: 0.0);
  }

  Future<void> _addCustomExtensions() async {
    final rawInput = _extController.text.trim();
    if (rawInput.isEmpty) return;

    final tokens = rawInput.split(RegExp(r'[\s,;，；]+'));
    final added = <String>[];
    final invalid = <String>[];

    for (final token in tokens) {
      if (token.isEmpty) continue;
      final normalized = VideoService.normalizeExtension(token);
      if (normalized == null) {
        invalid.add(token);
      } else if (!VideoService.supportedExtensions.contains(normalized) &&
          !_customExtensions.contains(normalized) &&
          !added.contains(normalized)) {
        added.add(normalized);
      }
    }

    if (added.isNotEmpty) {
      final updated = [..._customExtensions, ...added];
      setState(() {
        _customExtensions = updated;
        _extController.clear();
      });
      await VideoService.saveCustomExtensions(updated);
      _showToast('Added: ${added.join(', ')}');
    } else if (invalid.isNotEmpty) {
      _showToast('Invalid extension: ${invalid.join(', ')}');
    } else {
      _extController.clear();
      _showToast('Extension already in list.');
    }
  }

  Future<void> _removeCustomExtension(String ext) async {
    final updated = _customExtensions.where((e) => e != ext).toList();
    setState(() => _customExtensions = updated);
    await VideoService.saveCustomExtensions(updated);
  }

  void _showToast(String message, {ToastType type = ToastType.info}) {
    if (!mounted) return;
    FloatingToast.show(
      context,
      message,
      type: type,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Appearance', colorScheme),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Theme',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_rounded, size: 18),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_rounded, size: 18),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_rounded, size: 18),
                        ),
                      ],
                      selected: {_selectedMode},
                      onSelectionChanged: (selection) {
                        if (selection.isNotEmpty) {
                          _updateThemeMode(selection.first);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Progress Bar Style', colorScheme),
          const SizedBox(height: 8),
          _buildProgressStyleCard(colorScheme, isDark),
          const SizedBox(height: 24),
          _buildSectionHeader('Video Extensions', colorScheme),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.extension_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Custom Video Extensions',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Files with these extensions will be recognized as video containers in the file browser.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _extController,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addCustomExtensions(),
                          decoration: const InputDecoration(
                            hintText: 'e.g. flv, m4v, 3gp, dat',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _addCustomExtensions,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final ext in VideoService.supportedExtensions)
                        Chip(
                          label: Text(
                            ext,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      for (final ext in _customExtensions)
                        InputChip(
                          label: Text(
                            ext,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          backgroundColor: colorScheme.primaryContainer,
                          deleteIconColor: colorScheme.onPrimaryContainer,
                          visualDensity: VisualDensity.compact,
                          onDeleted: () => _removeCustomExtension(ext),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('About', colorScheme),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.merge_type_rounded,
                          size: 28,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              _appName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _appVersion,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                ListTile(
                  leading: Icon(
                    Icons.bolt_rounded,
                    color: colorScheme.primary,
                  ),
                  title: const Text('Merge Engine'),
                  subtitle: const Text(
                    'FFmpeg Direct-Stream Concat (-c copy, lossless)',
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                ListTile(
                  leading: Icon(
                    Icons.info_outline_rounded,
                    color: colorScheme.primary,
                  ),
                  title: const Text('About $_appName'),
                  subtitle: const Text(
                    'Combine multiple video files losslessly without re-encoding.',
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                ListTile(
                  leading: Icon(
                    Icons.code_rounded,
                    color: colorScheme.primary,
                  ),
                  title: const Text('GitHub Repository'),
                  subtitle: const Text(
                    _githubUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  trailing: Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onTap: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: _githubUrl),
                    );
                    _showToast('GitHub URL copied to clipboard.');
                  },
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text('Open Source Licenses'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: _appName,
                      applicationVersion: _appVersion,
                      applicationIcon: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Icon(
                          Icons.merge_type_rounded,
                          size: 40,
                          color: colorScheme.primary,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStyleCard(ColorScheme colorScheme, bool isDark) {
    const int demoTotalFrames = 3600;
    final int demoCurrentFrame = (_previewProgress * demoTotalFrames).round();
    final activeColor = _selectedProgressColor;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.linear_scale_rounded,
                  size: 20,
                  color: activeColor.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Progress Style & Accent',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: _replayPreview,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Preview'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: activeColor.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ProgressBarStyle>(
                segments: [
                  for (final style in ProgressBarStyle.values)
                    ButtonSegment<ProgressBarStyle>(
                      value: style,
                      label: Text(style.shortLabel),
                    ),
                ],
                selected: {_selectedProgressStyle},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    _updateProgressStyle(selection.first);
                  }
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Primary Color',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  activeColor.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? activeColor.light : activeColor.deep,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                for (final preset in ProgressColorPreset.values)
                  Tooltip(
                    message: preset.label,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _updateProgressColor(preset),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [preset.deep, preset.primary, preset.light],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: preset == activeColor
                                ? colorScheme.onSurface
                                : Colors.transparent,
                            width: 2.2,
                          ),
                          boxShadow: preset == activeColor
                              ? [
                                  BoxShadow(
                                    color: preset.primary.withValues(
                                      alpha: 0.45,
                                    ),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: preset == activeColor
                            ? const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Live sample video card preview
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _previewProgress > 0 && _previewProgress < 1
                      ? activeColor.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.45),
                  width: _previewProgress > 0 && _previewProgress < 1 ? 1.6 : 1,
                ),
              ),
              child: AnimatedCardProgressOverlay(
                progress: _previewProgress,
                showProgress: true,
                style: _selectedProgressStyle,
                colorPreset: activeColor,
                isDark: isDark,
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: activeColor.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.movie_outlined,
                      color: activeColor.primary,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    'sample_clip_01.mp4',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: Text(
                    '1920x1080 • 02:00 • 30 FPS • H264',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Text(
                    '${(_previewProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: isDark ? activeColor.light : activeColor.deep,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Live global progress bar preview
            GlobalMergeProgressBar(
              progress: _previewProgress,
              currentFrame: demoCurrentFrame,
              totalFrames: demoTotalFrames,
              colorPreset: activeColor,
              isDark: isDark,
              trailingLabel: _selectedProgressStyle.displayName,
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: activeColor.primary,
                thumbColor: activeColor.primary,
                overlayColor: activeColor.primary.withValues(alpha: 0.18),
              ),
              child: Slider(
                value: _previewProgress,
                onChanged: (val) {
                  if (_previewController.isAnimating) {
                    _previewController.stop();
                  }
                  setState(() => _previewProgress = val);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
