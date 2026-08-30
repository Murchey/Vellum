import 'package:flutter/cupertino.dart';

void main() {
  runApp(const VellumApp());
}

class VellumApp extends StatelessWidget {
  const VellumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Vellum',
      debugShowCheckedModeBanner: false,
      theme: VellumTheme.light,
      home: const VellumShell(),
    );
  }
}

abstract final class VellumTheme {
  static const ink = Color(0xFF29251F);
  static const mutedInk = Color(0xFF756D62);
  static const paper = Color(0xFFF5F1E8);
  static const card = Color(0xFFFBF9F4);
  static const terracotta = Color(0xFF9C5B46);
  static const line = Color(0xFFE3DDD1);

  static const light = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: terracotta,
    scaffoldBackgroundColor: paper,
    barBackgroundColor: paper,
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(fontFamily: 'Georgia', color: ink),
      navTitleTextStyle: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      navLargeTitleTextStyle: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 34,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
  );
}

class VellumShell extends StatefulWidget {
  const VellumShell({super.key});

  @override
  State<VellumShell> createState() => _VellumShellState();
}

class _VellumShellState extends State<VellumShell> {
  int _selectedIndex = 0;

  static const _pages = [
    HomePage(),
    LibraryPage(),
    WritingPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: VellumTheme.paper.withValues(alpha: .96),
        border: const Border(top: BorderSide(color: VellumTheme.line)),
        activeColor: VellumTheme.terracotta,
        inactiveColor: VellumTheme.mutedInk,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.book),
            activeIcon: Icon(CupertinoIcons.book_fill),
            label: '阅读',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.square_stack_3d_up),
            activeIcon: Icon(CupertinoIcons.square_stack_3d_up_fill),
            label: '书库',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.pencil),
            activeIcon: Icon(CupertinoIcons.pencil_ellipsis_rectangle),
            label: '写作',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.slider_horizontal_3),
            label: '设置',
          ),
        ],
      ),
      tabBuilder: (context, index) =>
          CupertinoTabView(builder: (_) => _pages[index]),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('VELLUM'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {},
          child: const Icon(CupertinoIcons.search),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            Text('晚上好，读者', style: _titleStyle),
            const SizedBox(height: 6),
            const Text(
              '让故事在今天继续。',
              style: TextStyle(color: VellumTheme.mutedInk),
            ),
            const SizedBox(height: 28),
            const SectionLabel('继续阅读'),
            const SizedBox(height: 12),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(
                context,
              ).push(CupertinoPageRoute(builder: (_) => const ReaderPage())),
              child: const CurrentBookCard(),
            ),
            const SizedBox(height: 30),
            const SectionLabel('最近阅读'),
            const SizedBox(height: 12),
            const RecentBookRow(
              title: '海边的卡夫卡',
              author: '村上春树',
              progress: '读至 42%',
            ),
            const RecentBookRow(
              title: '观看之道',
              author: '约翰·伯格',
              progress: '读至 18%',
            ),
            const RecentBookRow(title: '乡土中国', author: '费孝通', progress: '刚刚加入'),
          ],
        ),
      ),
    );
  }

  static const _titleStyle = TextStyle(
    fontFamily: 'Georgia',
    fontSize: 30,
    fontWeight: FontWeight.w600,
    color: VellumTheme.ink,
  );
}

class CurrentBookCard extends StatelessWidget {
  const CurrentBookCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VellumTheme.card,
        border: Border.all(color: VellumTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 78,
            height: 108,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF283B35),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              '夜航西飞',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFE7D9B7),
                fontFamily: 'Georgia',
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '夜航西飞',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 21,
                    color: VellumTheme.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  '柏瑞尔·马卡姆',
                  style: TextStyle(color: VellumTheme.mutedInk, fontSize: 13),
                ),
                SizedBox(height: 18),
                Text(
                  '第七章 · 读至 67%',
                  style: TextStyle(
                    color: VellumTheme.terracotta,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                CupertinoSlider(
                  value: .67,
                  onChanged: null,
                  activeColor: VellumTheme.terracotta,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String label;
  const SectionLabel(this.label, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: .8,
      color: VellumTheme.mutedInk,
    ),
  );
}

class RecentBookRow extends StatelessWidget {
  final String title;
  final String author;
  final String progress;
  const RecentBookRow({
    required this.title,
    required this.author,
    required this.progress,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 15),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: VellumTheme.line)),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 56,
          color: VellumTheme.terracotta.withValues(alpha: .75),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 17,
                  color: VellumTheme.ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                author,
                style: const TextStyle(
                  fontSize: 13,
                  color: VellumTheme.mutedInk,
                ),
              ),
            ],
          ),
        ),
        Text(
          progress,
          style: const TextStyle(fontSize: 12, color: VellumTheme.mutedInk),
        ),
      ],
    ),
  );
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('书库'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () {},
        child: const Icon(CupertinoIcons.add),
      ),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '你的藏书',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: VellumTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '0 本书籍 · 支持 EPUB、MOBI、TXT',
            style: TextStyle(color: VellumTheme.mutedInk),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: VellumTheme.card,
              border: Border.all(color: VellumTheme.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              children: [
                Icon(
                  CupertinoIcons.book,
                  size: 38,
                  color: VellumTheme.terracotta,
                ),
                SizedBox(height: 12),
                Text(
                  '从第一本书开始',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 20,
                    color: VellumTheme.ink,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '导入本地电子书，建立属于你的安静书房。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VellumTheme.mutedInk),
                ),
                SizedBox(height: 16),
                CupertinoButton.filled(onPressed: null, child: Text('导入电子书')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class WritingPage extends StatelessWidget {
  const WritingPage({super.key});
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('写作')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '写作工作台',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: VellumTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '把阅读留下的痕迹，慢慢写成自己的文字。',
            style: TextStyle(color: VellumTheme.mutedInk),
          ),
          const SizedBox(height: 28),
          _WritingAction(
            icon: CupertinoIcons.doc_text,
            title: '新建文档',
            subtitle: '开始一篇新的写作',
          ),
          _WritingAction(
            icon: CupertinoIcons.bookmark,
            title: '摘录与批注',
            subtitle: '整理阅读中留下的片段',
          ),
        ],
      ),
    ),
  );
}

class _WritingAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _WritingAction({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: VellumTheme.card,
      border: Border.all(color: VellumTheme.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon, color: VellumTheme.terracotta),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 17,
                color: VellumTheme.ink,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(color: VellumTheme.mutedInk, fontSize: 13),
            ),
          ],
        ),
      ],
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('设置')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '阅读偏好',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: VellumTheme.ink,
            ),
          ),
          const SizedBox(height: 22),
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                title: const Text('阅读主题'),
                additionalInfo: const Text('纸张'),
                trailing: const CupertinoListTileChevron(),
                onTap: () {},
              ),
              CupertinoListTile(
                title: const Text('字体与排版'),
                trailing: const CupertinoListTileChevron(),
                onTap: () {},
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                title: const Text('关于 Vellum'),
                additionalInfo: const Text('0.1.0'),
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ReaderPage extends StatelessWidget {
  const ReaderPage({super.key});
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => Navigator.pop(context),
        child: const Icon(CupertinoIcons.back),
      ),
      middle: const Text('夜航西飞 · 第七章'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () {},
        child: const Icon(CupertinoIcons.ellipsis),
      ),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 48),
        children: [
          const Text(
            '第七章\n云上的世界',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 29,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: VellumTheme.ink,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            '飞机穿过清晨的薄雾，世界在机翼下方缓慢展开。远处的山脉像沉睡的兽，河流则在阳光里闪着细碎的光。',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 19,
              height: 1.9,
              color: VellumTheme.ink,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '我总觉得，飞行真正改变的并不是距离，而是观看事物的方式。当我们从地面升起，熟悉的一切便获得了新的比例。',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 19,
              height: 1.9,
              color: VellumTheme.ink,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '此刻没有什么需要被立刻抵达。天空足够辽阔，容得下一个人安静地读完这一页。',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 19,
              height: 1.9,
              color: VellumTheme.ink,
            ),
          ),
          const SizedBox(height: 42),
          Center(
            child: Text(
              '— 67% —',
              style: TextStyle(
                color: VellumTheme.mutedInk,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
