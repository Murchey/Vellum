# Vellum

一个以阅读为核心的本地电子书应用：安静的「数字书房」，Cupertino-first，数据只存在本机。

## 功能

### 书库
- 导入 **EPUB / MOBI / TXT**
- 书架 **三列网格**，支持 **搜索**（书名 / 封面文字 / 格式）
- **自定义文件夹**：新建、重命名、删除；长按书籍可移入/移出
- **长按编辑封面**：上传图片，或用自定义文字生成封面
- 索引与正文分文件存储，启动只读轻量索引

### 阅读
- **上下滚动** / **左右翻页** 两种模式
- 进度条可拖动；目录、书签快速跳转
- 字号、行距、字重、背景色、系统/导入 TTF 字体
- 富文本：粗体、斜体、下划线、标题层级、引用、居中
- 选中文字：复制、Bing 查询、DeepL 翻译
- 阅读进度与书签自动保存

### 工具与设置
- **MOBI / EPUB 转 TXT**：独立二级页，可选择保存位置
- 深浅色主题
- 字体管理（导入 / 启用 / 删除）
- 检查 GitHub 更新；**可自定义更新仓库**（`owner/repo` 或完整 URL）
- 存储占用与清理

### 暂不支持
- 写作区（占位）
- DRM 加密电子书
- KF8 / AZW3 专有排版（按经典 MOBI7 解析）

## 目录结构

```
lib/
  main.dart                 入口
  app.dart                  VellumApp + LibraryShell
  vellum.dart               公共导出
  pages/                    首页、书库、设置、转 TXT、封面编辑
  reader/                   阅读页、分页、段落、手势、控制栏
  services/                 MOBI/EPUB/HTML 解析、书库存储、导入
  theme/ util/ widgets/     主题与工具
```

## 开发

### 环境
- Flutter stable（Dart SDK `^3.12.2`）
- Android / Windows 等 Flutter 支持的平台

### 依赖（国内可加速）

```bat
tool\pub_get_mirror.bat
```

脚本只设置当前会话的 `PUB_HOSTED_URL` 与 `FLUTTER_STORAGE_BASE_URL`，不改全局环境。

Android Gradle 依赖已使用阿里云 / 腾讯云镜像配置。

### 常用命令

```bat
flutter pub get
flutter analyze
flutter test
flutter run
```

### 构建

```bat
flutter build apk --release
:: 或
flutter build appbundle --release
```

说明：当前 release 仍使用 debug 签名，便于自测；上架前请配置正式 keystore。

## CI / 发布

| 工作流 | 触发 | 作用 |
|--------|------|------|
| `.github/workflows/build.yml` | 手动 | 测试 + 构建 APK/AAB |
| `.github/workflows/release.yml` | 手动或推送 `v*` tag | 打 tag、构建并发布 GitHub Release |

手动发版：**Actions → Release → Run workflow**，可指定 tag（默认取 `pubspec.yaml` 的 `version`）。

推送 tag：

```bat
git tag v1.0.1
git push origin v1.0.1
```

## 许可

见 [LICENSE](LICENSE)。
