import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'ui/books_page.dart';
import 'ui/profile_page.dart';
import 'ui/theme.dart';
import 'ui/today_page.dart';

void main() {
  runApp(const EnglishStudyApp());
}

class EnglishStudyApp extends StatefulWidget {
  const EnglishStudyApp({super.key});

  @override
  State<EnglishStudyApp> createState() => _EnglishStudyAppState();
}

class _EnglishStudyAppState extends State<EnglishStudyApp>
    with WidgetsBindingObserver {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台 / 浏览器切回前台时静默拉取一次，AppState 内部有冷却与并发保护
    if (state == AppLifecycleState.resumed) unawaited(_state.autoSync());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '拾词',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          if (!_state.isReady) {
            return _SplashScreen(error: _state.error);
          }
          return _Shell(state: _state);
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final String? error;
  const _SplashScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        colors: kGradients[0],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('正在加载…'),
              ] else ...[
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text('加载失败：$error', textAlign: TextAlign.center),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  final AppState state;
  const _Shell({required this.state});

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: [
          TodayPage(
            state: widget.state,
            onGoBooks: () => setState(() => _index = 1),
          ),
          BooksPage(state: widget.state),
          ProfilePage(state: widget.state),
        ],
      ),
      bottomNavigationBar: _GlassNavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _GlassNavBar({required this.index, required this.onSelect});

  static const _items = <(IconData, IconData, String)>[
    (Icons.wb_sunny_outlined, Icons.wb_sunny, '今日'),
    (Icons.menu_book_outlined, Icons.menu_book, '词单'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(26),
                      onTap: () => onSelect(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              i == index ? _items[i].$2 : _items[i].$1,
                              size: 22,
                              color: i == index
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _items[i].$3,
                              style: TextStyle(
                                fontSize: 11,
                                color: i == index
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                                fontWeight: i == index
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
