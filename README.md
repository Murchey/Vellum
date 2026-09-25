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
- 翻页效果：覆盖 / 平移 / 无动画；点击左右翻页、中间唤出控件
- 进度条可拖动；目录、书签、**划线笔记** 快速跳转
- 字号、行距、字重、**亮度**、**护眼**、背景色、系统/导入 TTF 字体
- 富文本：粗体、斜体、下划线、标题层级、引用、居中
- 选中文字：**划线**、复制、Bing 查询、DeepL 翻译、笔记（划线/笔记都可在正文中以高亮显示）
- 页脚显示 **当前章节 + 本章进度 + 剩余阅读时间**、全书进度与电量
- **屏幕常亮**、**音量键翻页**（可在阅读设置里开关）
- 顶栏一键加/取消书签；下拉阅读页面也可加书签
- 阅读进度与书签自动保存
- 目录阅读进度按章节独立保存：没有历史断点的章节从章节首页进入，跳出后返回可恢复该章离开位置

### 写作
- 本地文稿列表：新建、导入（`.md` / `.txt` / `.markdown`）、长按删除
- 编辑时自动保存、导出到所选位置，底部实时统计 **字数 / 词数**
- **Markdown 本地预览**：编辑区一键切到渲染视图（标题、粗体、斜体、列表、引用、链接文字），
  完全在本机用阅读页的排版管线渲染，不联网、不加载远程图片

### 工具与设置
- **MOBI / EPUB 转 TXT**：独立二级页，可选择保存位置
- 深浅色主题
- 字体管理（导入 / 启用 / 删除）
- **应用内更新**：进入 APP 自动检测（可在设置里关闭），发现新版本后按机型架构选择安装包，应用内下载并调起系统安装器；更新仓库可自定义（`owner/repo` 或完整 URL）
- 存储占用与清理

### 暂不支持
- 预览里的代码块按普通段落渲染（不保留缩进与等宽字体）
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
flutter build apk --release --split-per-abi
:: 或
flutter build appbundle --release
```

说明：当前 release 仍使用 debug 签名，便于自测；上架前请配置正式 keystore。

### 更新包命名

应用内更新按机型架构区分安装包，文件名必须是 `Vellum-V<版本>-<abi>.apk`：

| 文件名 | 适用 |
|--------|------|
| `Vellum-V1.0.3-arm64-v8a.apk` | 绝大多数手机（推荐） |
| `Vellum-V1.0.3-armeabi-v7a.apk` | 较老的 32 位机型 |
| `Vellum-V1.0.3-x86_64.apk` | x86 平板 / 模拟器 |
| `Vellum-V1.0.3-universal.apk` | 无法识别架构时的回退包 |

应用会读取设备的 `SUPPORTED_ABIS`，把匹配的包排到最前并标「推荐」；装错架构系统会提示「应用未安装」。

## CI / 发布

| 工作流 | 触发 | 作用 |
|--------|------|------|
| `.github/workflows/build.yml` | 手动 | 测试 + 构建 APK/AAB |
| `.github/workflows/release.yml` | 手动或推送 `v*` tag | 打 tag、按 ABI 构建并发布 GitHub Release |

Release 会产出 3 个按 ABI 拆分的 APK（`--split-per-abi`）加 1 个 universal 包，并统一重命名为上表的名字。

手动发版：**Actions → Release → Run workflow**，可指定 tag（默认取 `pubspec.yaml` 的 `version`）。

推送 tag：

```bat
git tag v1.0.1
git push origin v1.0.1
```

## 许可

见 [LICENSE](LICENSE)。
