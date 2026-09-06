# Vellum

一个以阅读为核心、兼顾写作的本地电子书应用。

## 当前框架

- Cupertino-first UI，采用“安静的数字书房”视觉方向
- 阅读、书库、写作、设置四个基础区域
- 支持 EPUB / MOBI / TXT 的产品入口预留
- 阅读主题、字体排版和导入流程将在后续迭代接入

## 国内镜像

Android Gradle 插件、Google Maven 与公共 Maven 依赖已切换到阿里云镜像；Gradle Wrapper 使用已验证可提供 Gradle 9.1.0 的腾讯云镜像。
Dart/Flutter 依赖使用腾讯云镜像脚本：

```bat
tool\\pub_get_mirror.bat
```

脚本显式设置 `PUB_HOSTED_URL` 与 `FLUTTER_STORAGE_BASE_URL`，不会修改开发机的全局环境变量。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
