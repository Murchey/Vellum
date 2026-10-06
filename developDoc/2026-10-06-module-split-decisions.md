# VELLUM 超长文件模块化决策

## 范围

本次只拆分当时超过 1000 行的三个文件：阅读页、阅读控制面板和写作页。`mobi_decoder.dart` 等 800～999 行文件暂不扩大范围，避免把行为稳定的解析器重构与 UI 模块化混在一起。

## 模块边界

- `reader_page.dart` 保留为兼容入口，页面编排实现位于 `reader_page_state.dart`。
- `reader_page_state.dart` 只保留生命周期、控制器持有和公开调试入口；分页/跳转位于 `reader_page_state_pagination.dart`，触控、翻页和 TTS 句子交互位于 `reader_page_state_gestures.dart`，正文、叠加层和翻页动画组合位于 `reader_page_state_surface_rendering.dart`。
- 阅读页的数据控制器（进度、笔记、计时、纸张和渐进分页）继续独立存在，页面 State 通过显式 getter 和回调连接视图；所有新实现文件均低于 1000 行。
- `reader_control_panels.dart` 保留为 barrel 文件，目录搜索、阅读设置和共享面板控件分别位于独立文件。
- 目录面板进一步按依赖方向拆为 `reader_directory_panel.dart` 兼容入口、`reader_directory_panel_state.dart` 状态与搜索逻辑、`reader_directory_panel_rendering.dart` 主目录布局以及 `reader_directory_panel_search_view.dart` 搜索结果和笔记列表。
- `writing_page.dart` 保留为 barrel 文件，文稿列表、编辑器和排版面板分别位于独立文件。

控制器不持有 `BuildContext`，只处理数据、异步任务和业务规则；Flutter 页面 State 负责生命周期、上下文和刷新。未引入第三方状态管理或 `part` 文件。

## 兼容性与数据

现有公开入口、构造函数、`vellum.dart` 导出和测试 import 路径继续有效。阅读状态 JSON、书籍 JSON、笔记、备份格式和 Android 原生接口均不变。原有分页锚定阈值、异步世代取消、章节恢复语义、写作自动保存和 Markdown 预览行为保持不变。

## 验证约束

模块化以行为零变化为验收标准，重点覆盖深层分页跳转、字体重新排版、目录搜索、笔记高亮、书写自动保存和预览切换。验证结束后清理 APK、截图、构建目录和临时文件，不执行 Git 操作，也不修改其他工程或 GitHub 内容。
