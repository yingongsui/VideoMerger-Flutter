<div align="center">

<img src="assets/icon/icon.png" width="96" height="96" alt="VideoMerger Icon" />

# VideoMerger

**一款基于 Flutter + FFmpeg 的 Android 无损直通视频合并工具**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20(arm64--v8a)-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![FFmpeg](https://img.shields.io/badge/Engine-FFmpeg%20Direct--Stream-007808?logo=ffmpeg&logoColor=white)](https://ffmpeg.org)

</div>

---

## 功能特性

- **无损极速合并（Direct-Stream Copy）**
  - 底层调用 FFmpeg `concat` 分离器配合 `-c copy` 参数直接拼接音视频流，**无需重编码**，保留原始画质与音质，合并速度接近磁盘读写上限。
- **双存储多选文件浏览器**
  - 原生支持内部共享存储与外置 SD 卡浏览，自动记忆上次访问目录，支持全选/取消全选、路径面包屑导航以及视频缩略图缓存预览。
  - 支持常见封装格式：`.mp4`、`.mkv`、`.mov`、`.avi`、`.ts`、`.webm`。
- **流信息诊断与兼容性检测**
  - 通过 FFprobe 自动解析每个视频的分辨率、时长、帧率（FPS）、文件大小、视频/音频编码、码率与总帧数。
  - 自动比对队列中视频的编码与分辨率，提前提示 `Stream Aligned` 或不匹配警告。
- **可视化队列与实时进度**
  - 支持拖拽调整合并顺序、自定义输出目录与输出文件名。
  - 合并时实时追踪全局帧进度并高亮当前处理片段，支持随时强停任务与折叠/复制 FFmpeg 终端日志。
- **现代 Material 3 界面与主题适配**
  - 支持 **System（跟随系统）/ Light（浅色）/ Dark（深色）** 三种主题模式并持久化保存。
  - 适配 **Android 13+ Monochrome 单色主题图标**（Material You 动态取色）。

---

## 项目结构

```text
video_merger/
├── lib/
│   ├── main.dart              # 应用入口与全局 Material 3 主题管理
│   ├── merge_page.dart        # 主界面：输出配置、视频队列、进度与日志面板
│   ├── file_tree_picker.dart  # 内外双盘文件/目录选择器（带路径记忆与缩略图缓存）
│   ├── settings_page.dart     # 设置页：主题切换与 About 信息
│   └── video_service.dart     # FFmpeg/FFprobe 封装、元数据解析与兼容性检查
├── assets/icon/
│   ├── icon.png               # 应用主图标
│   └── icon_monochrome.png    # Android 13+ 单色主题图标源文件
├── android/                   # Android 原生配置与矢量 Monochrome 图标
└── test/
    └── widget_test.dart       # 基础 Widget 自动化测试
```

---

## 开发与构建

### 环境要求

- Flutter SDK（Dart `^3.11.5`）
- Android SDK & JDK 17

### 常用命令

```bash
# 安装依赖
flutter pub get

# 静态代码检查
flutter analyze

# 运行测试
flutter test

# 调试运行（连接 Android 真机或模拟器）
flutter run

# 构建 Release APK（已通过 build.gradle.kts 剔除非 arm64 架构）
flutter build apk --release --target-platform android-arm64
```

### Release 签名配置说明

本仓库已通过 `.gitignore` 忽略本地签名文件。如需打包正式签名版 APK，请在 `android/app/` 下准备你的 keystore 文件与 `key.properties`：

```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=your_key_alias
```

---

## 主要依赖

- [`ffmpeg_kit_flutter_new_min`](https://pub.dev/packages/ffmpeg_kit_flutter_new_min) — FFmpeg / FFprobe 精简版音视频处理引擎
- [`permission_handler`](https://pub.dev/packages/permission_handler) — Android 存储权限管理
- [`path_provider`](https://pub.dev/packages/path_provider) — 缓存目录与外置存储路径获取
- [`shared_preferences`](https://pub.dev/packages/shared_preferences) — 主题与上次访问路径持久化

---

## 仓库地址

[https://github.com/yingongsui/VideoMerger-Flutter](https://github.com/yingongsui/VideoMerger-Flutter)
