<div align="center">

<img src="assets/icon/icon.png" width="96" height="96" alt="VideoToolKit Icon" />

# VideoToolKit

**Lossless Direct-Stream Video Trimmer & Merger for Android (Flutter + FFmpeg)**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20(arm64--v8a)-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![FFmpeg](https://img.shields.io/badge/Engine-FFmpeg%20Direct--Stream-007808?logo=ffmpeg&logoColor=white)](https://ffmpeg.org)

[English](#english) · [日本語](#日本語) · [中文](#中文)

</div>

---

## English

### Features
- **Lossless Direct-Stream Trim & Merge (`-c copy`)**:
  - **1 Video → Trim Mode**: Coarse time `RangeSlider` + live Start/End frame previews; context-aware fine controls snap **Start** to exact keyframes (`Prev KF` / `Snap KF` / `Next KF` + `Auto-Snap`) and step **End** by frame (`-10f` / `-1f` / `+1f` / `+10f`).
  - **2+ Videos → Merge Mode**: Concatenates clips via FFmpeg's `concat` demuxer without re-encoding, preserving original quality at disk I/O speed.
- **Dual-Volume File Browser & Custom Extensions**: Supports internal shared storage and external SD cards with separate memory & quick-jump recent history (last 3 folders) for source videos and target directory, cached thumbnails, and customizable video file extensions in Settings.
- **Deep Stream Diagnostics & Compatibility Check**: Inspects resolution, duration, FPS, size, codec/profile, pixel format, timebase, bitrate, audio sample rate, and channel layout via FFprobe, warning before merging if any parameter risks timeline or playback issues.
- **Customizable UI & Android 13+ Themed Icon**: Material 3 **System / Light / Dark** themes, customizable progress bar styles (`Sweep` / `Line` / `Dual`) and accent colors (default Dodger Blue) with live Settings preview, compact floating toast notifications, and a pixel-matched **Monochrome adaptive icon**.

### Project Structure
```text
video_merger/
├── lib/
│   ├── main.dart              # App entry & Material 3 theme/preference state
│   ├── merge_page.dart        # Main workspace: Waiting / Trim / Merge modes & console
│   ├── trim_panel.dart        # Coarse time + Start keyframe + End frame trim editor
│   ├── file_tree_picker.dart  # Dual-volume browser with separate memory & 3-folder history
│   ├── settings_page.dart     # Theme, progress style/color preview, custom extensions & About
│   ├── progress_style.dart    # Smooth animated card/global progress widgets & color presets
│   ├── floating_toast.dart    # Compact Overlay pill notifications
│   └── video_service.dart     # Serialized FFmpeg/FFprobe engine, keyframes & compatibility
├── assets/icon/
│   ├── icon.png               # Primary app icon
│   └── icon_monochrome.png    # Android 13+ monochrome icon source
├── android/                   # Android native config (com.yin.videotoolkit) & DPI icons
└── test/widget_test.dart      # Unit & widget tests
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
- [`shared_preferences`](https://pub.dev/packages/shared_preferences) — Settings & folder history persistence

---

## 日本語

### 主な機能
- **無劣化ダイレクトトリム＆結合（`-c copy`）**：
  - **1 本選択 → Trim モード**：時間軸スライダーによる粗調整と開始/終了フレームのリアルタイムプレビュー。開始点は**キーフレーム吸着**（`Prev KF` / `Snap KF` / `Next KF` + `Auto-Snap`）、終了点は**フレーム単位微調整**（`-10f` / `-1f` / `+1f` / `+10f`）に対応。
  - **複数選択 → Merge モード**：FFmpeg の `concat` により再エンコードなしで高速・無劣化結合。
- **内部ストレージ・SD カード対応＆拡張子カスタマイズ**：元動画フォルダと保存先フォルダを個別に記憶し、直近 3 件の履歴フォルダへワンタップ移動可能。設定から任意の拡張子を動画として追加できます。
- **詳細ストリーム診断＆互換性チェック**：解像度・再生時間・FPS・コーデック/プロファイル・ピクセルフォーマット・Timebase・音声サンプルレート/チャンネルを解析し、タイムライン異常の原因となる不一致を事前に警告します。
- **Material 3 ＆ 進捗バーカスタマイズ**：システム連動/ライト/ダークテーマ、進捗バースタイル（`Sweep` / `Line` / `Dual`）とメインカラー選択（プレビュー付き）、フローティング通知、Android 13+ モノクロテーマアイコンに対応。

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
- **无损直通裁剪与合并（`-c copy`）**：
  - **选择 1 个视频 → `Trim` 模式**：时间轴粗选 + 起止帧实时预览；**起点按关键帧吸附**（`Prev KF` / `Snap KF` / `Next KF` + `Auto-Snap`），**终点按帧微调**（`-10f` / `-1f` / `+1f` / `+10f`）。
  - **选择 2 个及以上视频 → `Merge` 模式**：基于 FFmpeg `concat` 无损拼接音视频流，无需重编码，速度接近磁盘读写上限。
- **双存储文件浏览器与自定义扩展名**：支持内部存储与外置 SD 卡，原视频目录与目标输出目录独立记忆并支持最近 3 个历史目录一键跳转；支持在设置中添加自定义视频扩展名。
- **深度流信息诊断与兼容性检测**：通过 FFprobe 解析分辨率、时长、FPS、编码与 Profile、像素格式、时间基（Timebase）、码率、音频采样率与声道布局，卡片直接展示并提前预警不匹配项。
- **Material 3 界面与个性化定制**：支持跟随系统/浅色/深色主题、进度条样式（`Sweep` / `Line` / `Dual`）与主色调自定义（默认道奇蓝，设置页实时预览）、轻量悬浮提示以及 Android 13+ Monochrome 单色主题图标。

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
[https://github.com/yingongsui/VideoToolKit-Flutter](https://github.com/yingongsui/VideoToolKit-Flutter)
