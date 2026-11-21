import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoMetadata {
  final String resolution;
  final String fps;
  final String bitrate;
  final int totalFrames;
  final String duration;
  final double durationSeconds;
  final String size;
  final int sizeBytes;
  final String videoCodec;
  final String audioCodec;

  const VideoMetadata({
    this.resolution = 'Unknown',
    this.fps = 'Unknown',
    this.bitrate = 'Unknown',
    this.totalFrames = 0,
    this.duration = 'Unknown',
    this.durationSeconds = 0.0,
    this.size = 'Unknown',
    this.sizeBytes = 0,
    this.videoCodec = 'Unknown',
    this.audioCodec = 'No Audio',
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
  static const List<String> supportedExtensions = [
    '.mp4',
    '.mkv',
    '.mov',
    '.avi',
    '.ts',
    '.webm',
  ];

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

    final hasDiffVideoCodec = loaded.any(
      (m) =>
          m.videoCodec != 'Unknown' &&
          first.videoCodec != 'Unknown' &&
          m.videoCodec != first.videoCodec,
    );
    if (hasDiffVideoCodec) {
      warnings.add('Video codec mismatch');
    }

    final hasDiffResolution = loaded.any(
      (m) =>
          m.resolution != 'Unknown' &&
          first.resolution != 'Unknown' &&
          m.resolution != first.resolution,
    );
    if (hasDiffResolution) {
      warnings.add('Resolution mismatch');
    }

    final hasDiffAudioCodec = loaded.any(
      (m) => m.audioCodec != first.audioCodec,
    );
    if (hasDiffAudioCodec) {
      warnings.add('Audio codec mismatch');
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

      // Try seeking to 1s first for a meaningful frame
      var session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss',
        '00:00:01',
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

      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          await File(thumbPath).exists()) {
        return thumbPath;
      }

      // Fallback to first frame for videos shorter than 1 second
      session = await FFmpegKit.executeWithArguments([
        '-y',
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

      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          await File(thumbPath).exists()) {
        return thumbPath;
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
      final session = await FFprobeKit.getMediaInformation(videoPath);
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
        String aCodec = 'No Audio';
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
          }
        }

        final int totalFrames =
            (durationSec > 0 && fpsValue > 0) ? (durationSec * fpsValue).round() : 0;

        return VideoMetadata(
          resolution: resolution,
          fps: fpsStr,
          bitrate: bitrate,
          totalFrames: totalFrames,
          duration: durationStr,
          durationSeconds: durationSec,
          size: sizeStr,
          sizeBytes: sizeBytes,
          videoCodec: vCodec,
          audioCodec: aCodec,
        );
      }
    } catch (e) {
      debugPrint('[VideoService] FFprobe failed for $videoPath: $e');
    }

    return VideoMetadata(size: sizeStr, sizeBytes: sizeBytes);
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

    debugPrint('[VideoService] Starting FFmpeg concat -> $outputPath');
    final session = await FFmpegKit.executeWithArguments([
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
    ]);
    final returnCode = await session.getReturnCode();

    FFmpegKitConfig.enableStatisticsCallback(null);
    FFmpegKitConfig.enableLogCallback(null);

    try {
      if (await listFile.exists()) await listFile.delete();
    } catch (_) {}

    if (ReturnCode.isSuccess(returnCode)) {
      onProgressFrames(totalFrames);
      return outputPath;
    } else {
      debugPrint('[VideoService] FFmpeg concat failed with code: $returnCode');
      return null;
    }
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
