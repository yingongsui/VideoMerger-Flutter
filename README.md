<div align="center">

<img src="assets/icon/icon.png" width="96" height="96" alt="VideoMerger Icon" />

# VideoMerger

**Lossless Direct-Stream Video Merger for Android (Flutter + FFmpeg)**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20(arm64--v8a)-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![FFmpeg](https://img.shields.io/badge/Engine-FFmpeg%20Direct--Stream-007808?logo=ffmpeg&logoColor=white)](https://ffmpeg.org)

[English](#english) · [日本語](#日本語) · [中文](#中文)

</div>

---

## English

### Features
- **Lossless Direct-Stream Concatenation (`-c copy`)**: Combines multiple video files using FFmpeg's `concat` demuxer without re-encoding, preserving original video/audio quality at disk I/O speed.
- **Dual-Volume File Browser**: Supports both internal shared storage and external SD cards with persistent last-folder memory, breadcrumb navigation, select-all toggle, and cached video thumbnails (`.mp4`, `.mkv`, `.mov`, `.avi`, `.ts`, `.webm`).
- **Stream Diagnostics & Compatibility Check**: Inspects resolution, duration, FPS, file size, video/audio codecs, bitrate, and frame count via FFprobe, and automatically warns about codec/resolution mismatches before merging.
- **Queue Management & Live Console**: Drag-to-reorder clips, custom output directory & filename, real-time frame progress tracking, instant cancel, and collapsible/copyable FFmpeg runtime logs.
- **Material 3 & Android 13+ Themed Icon**: Supports **System / Light / Dark** themes (defaults to System) and includes a pixel-matched **Monochrome adaptive icon** for Material You.

### Project Structure
```text
video_merger/
├── lib/
│   ├── main.dart              # App entry & Material 3 theme management
│   ├── merge_page.dart        # Main UI: output config, video queue, progress & console
│   ├── file_tree_picker.dart  # Dual-volume file/folder picker with path memory & thumb cache
│   ├── settings_page.dart     # Settings: Theme selector & About
│   └── video_service.dart     # FFmpeg/FFprobe wrapper, metadata & stream compatibility check
├── assets/icon/
│   ├── icon.png               # Primary app icon
│   └── icon_monochrome.png    # Android 13+ monochrome icon source
├── android/                   # Android native config & multi-DPI monochrome icons
└── test/widget_test.dart      # Widget tests
```

### Build & Run
```bash
flutter pub get
flutter analyze
flutter test
flutter run

# Build lean arm64-v8a Release APK
flutter build apk --release --target-platform android-arm64
```

> **Release Signing**: Local signing files are ignored by `.gitignore`. Place your keystore and `key.properties` (`storePassword`, `keyPassword`, `keyAlias`) under `android/app/` to build signed release APKs.

### Main Dependencies
- [`ffmpeg_kit_flutter_new_min`](https://pub.dev/packages/ffmpeg_kit_flutter_new_min) — Minimal FFmpeg / FFprobe engine
- [`permission_handler`](https://pub.dev/packages/permission_handler) — Android storage permissions
- [`path_provider`](https://pub.dev/packages/path_provider) — Cache & external storage paths
- [`shared_preferences`](https://pub.dev/packages/shared_preferences) — Theme & last-directory persistence

---

## 日本語

### 主な機能
- **無劣化ダイレクト結合（`-c copy`）**：FFmpeg の `concat` デマルチプレクサを使用し、再エンコードなしで複数の動画を高速・無劣化で結合します。
- **内部ストレージ・SD カード対応ファイルブラウザ**：前回のフォルダ位置を記憶し、パンくず表示、一括選択、サムネイルキャッシュに対応（`.mp4` / `.mkv` / `.mov` / `.avi` / `.ts` / `.webm`）。
- **ストリーム診断＆互換性チェック**：FFprobe で解像度・再生時間・FPS・サイズ・映像/音声コーデック・ビットレート・総フレーム数を自動解析し、結合前にコーデックや解像度の不一致を警告します。
- **キュー管理＆リアルタイムログ**：ドラッグ＆ドロップでの並び替え、出力先フォルダ・ファイル名の変更、フレーム単位の進捗表示、強制停止、折りたたみ・コピー可能な FFmpeg コンソールログを搭載。
- **Material 3 ＆ Android 13+ モノクロアイコン**：**システム連動 / ライト / ダーク**テーマ（デフォルトはシステム連動）に対応し、Material You 向けの **Monochrome テーマアイコン** を備えています。

### 開発・ビルド手順
```bash
flutter pub get
flutter analyze
flutter test
flutter run

# arm64-v8a 向け軽量 Release APK をビルド
flutter build apk --release --target-platform android-arm64
```

> **リリース署名について**：署名ファイルは `.gitignore` で除外されています。署名済み APK をビルドする場合は、`android/app/` に keystore と `key.properties`（`storePassword` / `keyPassword` / `keyAlias`）を配置してください。

---

## 中文

### 功能特性
- **无损极速合并（`-c copy`）**：基于 FFmpeg `concat` 分离器直接拼接音视频流，**无需重编码**，完整保留原始画质与音质，速度接近磁盘读写上限。
- **双存储多选文件浏览器**：支持内部共享存储与外置 SD 卡浏览，自动记忆上次访问目录，支持全选/取消全选、路径面包屑导航与视频缩略图缓存（`.mp4` / `.mkv` / `.mov` / `.avi` / `.ts` / `.webm`）。
- **流信息诊断与兼容性检测**：通过 FFprobe 自动解析分辨率、时长、FPS、体积、音视频编码、码率与总帧数，并在合并前自动提示编码或分辨率不匹配警告。
- **可视化队列与实时控制台**：支持拖拽排序、自定义输出目录与输出文件名、实时帧进度条、随时强停，以及可折叠/一键复制的 FFmpeg 日志面板。
- **Material 3 与 Android 13+ 单色图标**：支持 **System（默认）/ Light / Dark** 三种主题模式并持久化保存，完整适配 Material You **Monochrome 单色主题图标**。

### 开发与构建
```bash
flutter pub get
flutter analyze
flutter test
flutter run

# 构建精简版 arm64-v8a Release APK
flutter build apk --release --target-platform android-arm64
```

> **Release 签名说明**：本地签名文件已通过 `.gitignore` 忽略。如需打包正式签名版 APK，请在 `android/app/` 下放置你的 keystore 文件与 `key.properties`（包含 `storePassword`、`keyPassword`、`keyAlias`）。

---

## Repository
[https://github.com/yingongsui/VideoMerger-Flutter](https://github.com/yingongsui/VideoMerger-Flutter)
