import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoMetadata {
  final String resolution;
  final String fps;
  final double fpsValue;
  final String bitrate;
  final int totalFrames;
  final String duration;
  final double durationSeconds;
  final String size;
  final int sizeBytes;
  final String videoCodec;
  final String videoProfile;
  final String pixelFormat;
  final String videoTimeBase;
  final String audioCodec;
  final String audioSampleRate;
  final String audioChannelLayout;

  const VideoMetadata({
    this.resolution = 'Unknown',
    this.fps = 'Unknown',
    this.fpsValue = 0.0,
    this.bitrate = 'Unknown',
    this.totalFrames = 0,
    this.duration = 'Unknown',
    this.durationSeconds = 0.0,
    this.size = 'Unknown',
    this.sizeBytes = 0,
    this.videoCodec = 'Unknown',
    this.videoProfile = 'Unknown',
    this.pixelFormat = 'Unknown',
    this.videoTimeBase = 'Unknown',
    this.audioCodec = 'No Audio',
    this.audioSampleRate = 'Unknown',
    this.audioChannelLayout = 'Unknown',
  });
}

class StreamCompatibilityResult {
  final bool isCompatible;
  final List<String> warnings;

  const StreamCompatibilityResult({
    required this.isCompatible,
    this.warnings = const [],
  });
}

class VideoService {
  static const String _prefCustomExtKey = 'custom_video_extensions';

  /// Serializes short native FFprobe/FFmpeg utility calls so libffmpegkit's
  /// native log queue is never raced concurrently across threads.
  static Future<void> _nativeQueue = Future<void>.value();

  static Future<T> _runSerialized<T>(Future<T> Function() action) {
    final next = _nativeQueue.then((_) => action(), onError: (_) => action());
    _nativeQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  static const List<String> supportedExtensions = [
    '.mp4',
    '.mkv',
    '.mov',
    '.avi',
    '.ts',
    '.webm',
  ];

  /// Normalizes a raw extension input (e.g. "m4v", ".FLV") into ".m4v" / ".flv".
  /// Returns null if the input is empty or contains invalid characters.
  static String? normalizeExtension(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceFirst(RegExp(r'^\.+'), '');
    if (cleaned.isEmpty) return null;
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(cleaned)) return null;
    return '.$cleaned';
  }

  static List<String> _sanitizeCustomExtensions(Iterable<String> raw) {
    return raw
        .map(normalizeExtension)
        .whereType<String>()
        .where((ext) => !supportedExtensions.contains(ext))
        .toSet()
        .toList();
  }

  static Future<List<String>> loadCustomExtensions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _sanitizeCustomExtensions(
        prefs.getStringList(_prefCustomExtKey) ?? const [],
      );
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCustomExtensions(List<String> extensions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefCustomExtKey,
        _sanitizeCustomExtensions(extensions),
      );
    } catch (_) {}
  }

  static Future<List<String>> getAllSupportedExtensions() async {
    final custom = await loadCustomExtensions();
    return [...supportedExtensions, ...custom];
  }

  static Future<bool> requestStoragePermission() async {
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return 'Unknown';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  static String formatDuration(double seconds) {
    if (seconds <= 0) return 'Unknown';
    final int totalSecs = seconds.round();
    final int hours = totalSecs ~/ 3600;
    final int minutes = (totalSecs % 3600) ~/ 60;
    final int secs = totalSecs % 60;
    final String minPart = minutes.toString().padLeft(2, '0');
    final String secPart = secs.toString().padLeft(2, '0');
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minPart:$secPart'
        : '$minPart:$secPart';
  }

  /// Formats seconds with millisecond precision (`HH:MM:SS.mmm` or `MM:SS.mmm`).
  static String formatTimestamp(double seconds) {
    final safe = seconds < 0 ? 0.0 : seconds;
    final int totalMs = (safe * 1000).round();
    final int hours = totalMs ~/ 3600000;
    final int minutes = (totalMs % 3600000) ~/ 60000;
    final int secs = (totalMs % 60000) ~/ 1000;
    final int ms = totalMs % 1000;
    final String mStr = minutes.toString().padLeft(2, '0');
    final String sStr = secs.toString().padLeft(2, '0');
    final String msStr = ms.toString().padLeft(3, '0');
    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$mStr:$sStr.$msStr'
        : '$mStr:$sStr.$msStr';
  }

  /// Checks whether all metadata entries share compatible streams for lossless `-c copy`.
  static StreamCompatibilityResult checkCompatibility(
    List<VideoMetadata?> metadataList,
  ) {
    final loaded = metadataList.whereType<VideoMetadata>().toList();
    if (loaded.length < 2) {
      return const StreamCompatibilityResult(isCompatible: true);
    }

    final warnings = <String>[];
    final first = loaded.first;

    bool differs(String Function(VideoMetadata m) selector) {
      final base = selector(first);
      if (base == 'Unknown' || base.isEmpty) return false;
      return loaded.any((m) {
        final v = selector(m);
        return v != 'Unknown' && v.isNotEmpty && v != base;
      });
    }

    if (differs((m) => m.videoCodec)) {
      warnings.add('Video codec mismatch');
    }
    if (differs((m) => m.resolution)) {
      warnings.add('Resolution mismatch');
    }
    if (differs((m) => m.videoTimeBase)) {
      warnings.add('Timebase mismatch (timeline risk)');
    }
    if (first.fpsValue > 0 &&
        loaded.any(
          (m) => m.fpsValue > 0 && (m.fpsValue - first.fpsValue).abs() > 0.5,
        )) {
      warnings.add('FPS mismatch');
    }
    if (differs((m) => m.pixelFormat)) {
      warnings.add('Pixel format / bit-depth mismatch');
    }
    if (differs((m) => m.videoProfile)) {
      warnings.add('Video profile mismatch');
    }
    if (loaded.any((m) => m.audioCodec != first.audioCodec)) {
      warnings.add('Audio codec mismatch');
    }
    if (differs((m) => m.audioSampleRate)) {
      warnings.add('Audio sample rate mismatch');
    }
    if (differs((m) => m.audioChannelLayout)) {
      warnings.add('Audio channel layout mismatch');
    }

    return StreamCompatibilityResult(
      isCompatible: warnings.isEmpty,
      warnings: warnings,
    );
  }

  static Future<String?> generateThumbnail(String videoPath) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final file = File(videoPath);
      int mtime = 0;
      try {
        if (await file.exists()) {
          mtime = (await file.lastModified()).millisecondsSinceEpoch;
        }
      } catch (_) {}

      final thumbPath =
          '${cacheDir.path}/thumb_${videoPath.hashCode}_$mtime.jpg';
      if (await File(thumbPath).exists()) return thumbPath;

      // Try 1s first for a meaningful frame, then fall back to the first frame for short clips
      for (final seekArgs in const [
        ['-ss', '00:00:01'],
        <String>[],
      ]) {
        final ok = await _runSerialized(() async {
          final session = await FFmpegKit.executeWithArguments([
            '-y',
            ...seekArgs,
            '-i',
            videoPath,
            '-vframes',
            '1',
            '-q:v',
            '4',
            '-vf',
            'scale=160:-1',
            thumbPath,
          ]);
          return ReturnCode.isSuccess(await session.getReturnCode()) &&
              await File(thumbPath).exists();
        });
        if (ok) return thumbPath;
      }
    } catch (e) {
      debugPrint('[VideoService] Thumbnail generation failed: $e');
    }
    return null;
  }

  static double _parseRational(String? raw) {
    if (raw == null || raw.isEmpty) return 0.0;
    if (raw.contains('/')) {
      final parts = raw.split('/');
      if (parts.length == 2) {
        final num = double.tryParse(parts[0]);
        final den = double.tryParse(parts[1]);
        if (num != null && den != null && den != 0) {
          final val = num / den;
          // Guard against invalid VFR timebases like 90000/1
          if (val > 0 && val <= 240) return val;
        }
      }
      return 0.0;
    }
    final val = double.tryParse(raw) ?? 0.0;
    return (val > 0 && val <= 240) ? val : 0.0;
  }

  static Future<VideoMetadata> getVideoMetadata(String videoPath) async {
    int sizeBytes = 0;
    String sizeStr = 'Unknown';
    try {
      final file = File(videoPath);
      if (await file.exists()) {
        sizeBytes = await file.length();
        sizeStr = formatBytes(sizeBytes);
      }
    } catch (_) {}

    try {
      final session = await _runSerialized(
        () => FFprobeKit.getMediaInformation(videoPath),
      );
      final info = session.getMediaInformation();
      if (info != null) {
        String bitrate = 'Unknown';
        final rawBitrate = info.getBitrate();
        if (rawBitrate != null) {
          final bps = double.tryParse(rawBitrate);
          if (bps != null && bps > 0) {
            bitrate = '${(bps / 1000).toStringAsFixed(0)} kbps';
          }
        }

        double durationSec = 0.0;
        String durationStr = 'Unknown';
        final rawDuration = info.getDuration();
        if (rawDuration != null) {
          final parsed = double.tryParse(rawDuration);
          if (parsed != null && parsed > 0) {
            durationSec = parsed;
            durationStr = formatDuration(durationSec);
          }
        }

        String resolution = 'Unknown';
        double fpsValue = 0.0;
        String fpsStr = 'Unknown';
        String vCodec = 'Unknown';
        String vProfile = 'Unknown';
        String pixFmt = 'Unknown';
        String vTimeBase = 'Unknown';
        String aCodec = 'No Audio';
        String aSampleRate = 'Unknown';
        String aChannelLayout = 'Unknown';
        bool foundVideo = false;
        bool foundAudio = false;

        final streams = info.getStreams();
        for (final stream in streams) {
          final type = stream.getType();
          if (type == 'video' && !foundVideo) {
            final codec = stream.getCodec()?.toLowerCase() ?? '';
            // Skip embedded album art / cover image streams
            if (codec == 'mjpeg' || codec == 'png') continue;

            foundVideo = true;
            final w = stream.getWidth();
            final h = stream.getHeight();
            if (w != null && h != null && w > 0 && h > 0) {
              resolution = '${w}x$h';
            }
            if (codec.isNotEmpty) {
              vCodec = codec.toUpperCase();
            }

            final rawProfile = stream.getStringProperty('profile');
            if (rawProfile != null && rawProfile.isNotEmpty) {
              vProfile = rawProfile;
            }
            final rawPixFmt = stream.getFormat();
            if (rawPixFmt != null && rawPixFmt.isNotEmpty) {
              pixFmt = rawPixFmt;
            }
            final rawTimeBase = stream.getTimeBase();
            if (rawTimeBase != null && rawTimeBase.isNotEmpty) {
              vTimeBase = rawTimeBase;
            }

            // Prefer average frame rate to avoid bogus timebase values on VFR clips
            fpsValue = _parseRational(stream.getAverageFrameRate());
            if (fpsValue <= 0) {
              fpsValue = _parseRational(stream.getRealFrameRate());
            }
            if (fpsValue > 0) {
              fpsStr = '${fpsValue.toStringAsFixed(0)} FPS';
            }
          } else if (type == 'audio' && !foundAudio) {
            foundAudio = true;
            final codec = stream.getCodec();
            if (codec != null && codec.isNotEmpty) {
              aCodec = codec.toUpperCase();
            }
            final sr = stream.getSampleRate();
            if (sr != null && sr.isNotEmpty) {
              aSampleRate = '$sr Hz';
            }
            final chLayout = stream.getChannelLayout();
            if (chLayout != null && chLayout.isNotEmpty) {
              aChannelLayout = chLayout;
            }
          }
        }

        final int totalFrames =
            (durationSec > 0 && fpsValue > 0) ? (durationSec * fpsValue).round() : 0;

        return VideoMetadata(
          resolution: resolution,
          fps: fpsStr,
          fpsValue: fpsValue,
          bitrate: bitrate,
          totalFrames: totalFrames,
          duration: durationStr,
          durationSeconds: durationSec,
          size: sizeStr,
          sizeBytes: sizeBytes,
          videoCodec: vCodec,
          videoProfile: vProfile,
          pixelFormat: pixFmt,
          videoTimeBase: vTimeBase,
          audioCodec: aCodec,
          audioSampleRate: aSampleRate,
          audioChannelLayout: aChannelLayout,
        );
      }
    } catch (e) {
      debugPrint('[VideoService] FFprobe failed for $videoPath: $e');
    }

    return VideoMetadata(size: sizeStr, sizeBytes: sizeBytes);
  }

  /// Shared FFmpeg runner with frame progress & log streaming callbacks.
  static Future<String?> _executeStreamJob({
    required List<String> args,
    required int totalFrames,
    required String outputPath,
    required String jobLabel,
    required Function(int) onProgressFrames,
    required Function(String) onLogReceived,
  }) async {
    FFmpegKitConfig.enableStatisticsCallback((statistics) {
      try {
        final int currentFrame = statistics.getVideoFrameNumber();
        if (currentFrame > 0) {
          onProgressFrames(currentFrame);
        }
      } catch (_) {}
    });

    FFmpegKitConfig.enableLogCallback((log) {
      final msg = log.getMessage().trimRight();
      if (msg.isNotEmpty) {
        onLogReceived(msg);
      }
    });

    debugPrint('[VideoService] Starting FFmpeg $jobLabel -> $outputPath');
    final session = await FFmpegKit.executeWithArguments(args);
    final returnCode = await session.getReturnCode();

    FFmpegKitConfig.enableStatisticsCallback(null);
    FFmpegKitConfig.enableLogCallback(null);

    if (ReturnCode.isSuccess(returnCode)) {
      onProgressFrames(totalFrames);
      return outputPath;
    }
    debugPrint('[VideoService] FFmpeg $jobLabel failed with code: $returnCode');
    return null;
  }

  /// Lossless direct-stream concatenation using FFmpeg concat demuxer (`-c copy`).
  static Future<String?> mergeVideosDirectly({
    required List<String> filePaths,
    required int totalFrames,
    required String outputPath,
    required Function(int) onProgressFrames,
    required Function(String) onLogReceived,
  }) async {
    if (filePaths.isEmpty) return null;
    if (!await requestStoragePermission()) return null;

    final cacheDir = await getTemporaryDirectory();
    final listFile = File(
      '${cacheDir.path}/merge_list_${DateTime.now().millisecondsSinceEpoch}.txt',
    );

    final buffer = StringBuffer();
    for (final path in filePaths) {
      // Escape single quotes per FFmpeg concat demuxer specification
      final escaped = path.replaceAll("'", "'\\''");
      buffer.writeln("file '$escaped'");
    }
    await listFile.writeAsString(buffer.toString());

    try {
      return await _executeStreamJob(
        args: [
          '-y',
          '-f',
          'concat',
          '-safe',
          '0',
          '-i',
          listFile.path,
          '-c',
          'copy',
          outputPath,
        ],
        totalFrames: totalFrames,
        outputPath: outputPath,
        jobLabel: 'concat',
        onProgressFrames: onProgressFrames,
        onLogReceived: onLogReceived,
      );
    } finally {
      try {
        if (await listFile.exists()) await listFile.delete();
      } catch (_) {}
    }
  }

  /// Reads keyframe (I-frame) timestamps in a bounded local window `[windowStart, windowStart + windowDuration]`
  /// using FFprobe `-read_intervals`. Bounded output prevents native log-buffer OOM on long videos.
  static Future<List<double>> getKeyframesInWindow(
    String videoPath, {
    required double windowStart,
    double windowDuration = 24.0,
  }) async {
    final safeStart = windowStart < 0 ? 0.0 : windowStart;
    final interval =
        '${safeStart.toStringAsFixed(2)}%+$windowDuration';

    try {
      return await _runSerialized(() async {
        final session = await FFprobeKit.executeWithArguments([
          '-v',
          'error',
          '-select_streams',
          'v:0',
          '-read_intervals',
          interval,
          '-show_entries',
          'packet=pts_time,dts_time,flags',
          '-of',
          'csv=p=0',
          videoPath,
        ]);
        if (!ReturnCode.isSuccess(await session.getReturnCode())) {
          return const <double>[];
        }

        final output = await session.getOutput();
        if (output == null || output.isEmpty) return const <double>[];

        final keyframes = <double>[];
        for (final rawLine in output.split('\n')) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          final parts = line.split(',');
          if (parts.length < 3) continue;
          if (!parts[2].contains('K')) continue;

          final ts = double.tryParse(parts[0]) ?? double.tryParse(parts[1]);
          if (ts != null && ts >= 0) {
            if (keyframes.isEmpty || (ts - keyframes.last).abs() > 0.001) {
              keyframes.add(ts);
            }
          }
        }
        keyframes.sort();
        return keyframes;
      });
    } catch (e) {
      debugPrint('[VideoService] Keyframe window scan failed: $e');
      return const [];
    }
  }

  /// Queries the nearest keyframe around [targetSeconds] using a safe bounded probe window.
  static Future<double?> queryNearestKeyframe(
    String videoPath,
    double targetSeconds,
  ) async {
    final kfs = await getKeyframesInWindow(
      videoPath,
      windowStart: (targetSeconds - 15.0).clamp(0.0, double.infinity),
      windowDuration: 30.0,
    );
    return findNearestKeyframe(kfs, targetSeconds);
  }

  /// Queries the previous keyframe before [targetSeconds].
  static Future<double?> queryPrevKeyframe(
    String videoPath,
    double targetSeconds,
  ) async {
    if (targetSeconds <= 0.01) return null;
    for (final span in const [20.0, 60.0]) {
      final start = (targetSeconds - span).clamp(0.0, double.infinity);
      final kfs = await getKeyframesInWindow(
        videoPath,
        windowStart: start,
        windowDuration: (targetSeconds - start) + 1.0,
      );
      final prev = findPrevKeyframe(kfs, targetSeconds);
      if (prev != null) return prev;
      if (start == 0.0) break;
    }
    return null;
  }

  /// Queries the next keyframe after [targetSeconds].
  static Future<double?> queryNextKeyframe(
    String videoPath,
    double targetSeconds,
    double totalDuration,
  ) async {
    if (targetSeconds >= totalDuration - 0.01) return null;
    for (final span in const [20.0, 60.0]) {
      final start = (targetSeconds - 0.5).clamp(0.0, double.infinity);
      final kfs = await getKeyframesInWindow(
        videoPath,
        windowStart: start,
        windowDuration: span,
      );
      final next = findNextKeyframe(kfs, targetSeconds);
      if (next != null) return next;
      if (start + span >= totalDuration) break;
    }
    return null;
  }

  /// Finds the nearest keyframe timestamp to [target] in a sorted [keyframes] list.
  static double? findNearestKeyframe(List<double> keyframes, double target) {
    if (keyframes.isEmpty) return null;
    double best = keyframes.first;
    double bestDist = (best - target).abs();
    for (final kf in keyframes) {
      final dist = (kf - target).abs();
      if (dist < bestDist) {
        best = kf;
        bestDist = dist;
      } else if (kf > target) {
        break;
      }
    }
    return best;
  }

  /// Finds the strictly previous keyframe before [target] (with small epsilon).
  static double? findPrevKeyframe(List<double> keyframes, double target) {
    double? prev;
    for (final kf in keyframes) {
      if (kf < target - 0.005) {
        prev = kf;
      } else {
        break;
      }
    }
    return prev;
  }

  /// Finds the strictly next keyframe after [target] (with small epsilon).
  static double? findNextKeyframe(List<double> keyframes, double target) {
    for (final kf in keyframes) {
      if (kf > target + 0.005) {
        return kf;
      }
    }
    return null;
  }

  /// Extracts a frame-accurate preview image at [seconds] using fast pre-seek + exact decode.
  static Future<String?> extractFramePreview(
    String videoPath,
    double seconds, {
    required String tag,
  }) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final safeSec = seconds < 0 ? 0.0 : seconds;
      final msKey = (safeSec * 1000).round();
      final outPath =
          '${cacheDir.path}/trim_${tag}_${videoPath.hashCode}_$msKey.jpg';

      if (await File(outPath).exists()) return outPath;

      final seekArgs = safeSec > 2.0
          ? ['-ss', (safeSec - 2.0).toStringAsFixed(3), '-i', videoPath, '-ss', '2.000']
          : ['-i', videoPath, '-ss', safeSec.toStringAsFixed(3)];

      final ok = await _runSerialized(() async {
        final session = await FFmpegKit.executeWithArguments([
          '-y',
          ...seekArgs,
          '-frames:v',
          '1',
          '-q:v',
          '4',
          '-vf',
          'scale=320:-1',
          outPath,
        ]);
        return ReturnCode.isSuccess(await session.getReturnCode()) &&
            await File(outPath).exists();
      });
      if (ok) return outPath;
    } catch (e) {
      debugPrint('[VideoService] Frame preview extraction failed: $e');
    }
    return null;
  }

  /// Lossless direct-stream trim (`-c copy` with clean timestamp reset).
  static Future<String?> trimVideoDirectly({
    required String inputPath,
    required double startSeconds,
    required double endSeconds,
    required int expectedFrames,
    required String outputPath,
    required Function(int) onProgressFrames,
    required Function(String) onLogReceived,
  }) async {
    final duration = endSeconds - startSeconds;
    if (duration <= 0) return null;
    if (!await requestStoragePermission()) return null;

    return _executeStreamJob(
      args: [
        '-y',
        '-ss',
        startSeconds.toStringAsFixed(3),
        '-i',
        inputPath,
        '-t',
        duration.toStringAsFixed(3),
        '-c',
        'copy',
        '-avoid_negative_ts',
        'make_zero',
        outputPath,
      ],
      totalFrames: expectedFrames,
      outputPath: outputPath,
      jobLabel: 'trim',
      onProgressFrames: onProgressFrames,
      onLogReceived: onLogReceived,
    );
  }

  static void cancelCurrentOperation() {
    try {
      FFmpegKit.cancel();
      debugPrint('[VideoService] Cancel signal sent to FFmpegKit.');
    } catch (e) {
      debugPrint('[VideoService] Failed to cancel FFmpeg process: $e');
    }
  }
}
