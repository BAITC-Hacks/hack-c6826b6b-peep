import 'package:flutter/material.dart';

import '../core/api.dart';
import '../widgets/ui.dart';
import 'login.dart';
import 'profile.dart';
import 'directory.dart';
import 'imports.dart';

class Workspace extends StatefulWidget {
  const Workspace({super.key, this.api});
  final CareerApi? api;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  late final CareerApi api;
  Json? user;
  String? message;
  int page = 0;
  int revision = 0;
  bool signingOut = false;
  bool get isHr => user?['role'] == 'hr';
  List<String> get titles => isHr
      ? ['Сотрудники', 'Загрузка данных']
      : ['Мой профиль', 'История развития'];
  List<IconData> get icons => isHr
      ? [Icons.people_outline, Icons.file_upload_outlined]
      : [Icons.space_dashboard_outlined, Icons.history_rounded];

  @override
  void initState() {
    super.initState();
    api = widget.api ?? CareerApi();
    api.onUnauthorized = () {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      if (mounted && user != null) {
        setState(() {
          user = null;
          message = 'Сессия завершилась. Войдите снова, чтобы продолжить.';
        });
      }
    };
  }

  @override
  void dispose() {
    api.onUnauthorized = null;
    if (widget.api == null) api.dispose();
    super.dispose();
  }

  Future<void> logout() async {
    final revocation = api.logout();
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      user = null;
      page = 0;
      message = null;
      signingOut = false;
    });
    try {
      await revocation;
    } catch (_) {
      // Personal data and the old token are already cleared locally.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return LoginPage(
        api: api,
        message: message,
        onLogin: (loggedIn) => setState(() {
          user = loggedIn;
          page = 0;
          message = null;
        }),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      body: QuestBackdrop(
        child: SafeArea(
          child: Row(
            children: [
              if (wide) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 36 : 20,
                        vertical: 17,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xB80C142C),
                        border: Border(bottom: BorderSide(color: line)),
                      ),
                      child: Row(
                        children: [
                          if (wide)
                            Expanded(
                              child: Text(
                                'CAREER QUEST   /   ${titles[page]}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          else
                            const Brand(compact: true),
                          if (!wide) const Spacer(),
                          const Tag('Демо', background: paper, color: muted),
                          const SizedBox(width: 14),
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF333055),
                            child: Text(
                              initials(value(user!['display_name'])),
                              style: const TextStyle(
                                fontSize: 12,
                                color: pink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (wide) ...[
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                value(user!['display_name']),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          if (!wide)
                            IconButton(
                              onPressed: signingOut ? null : logout,
                              tooltip: 'Выйти',
                              icon: const Icon(Icons.logout, size: 20),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: isHr
                          ? (page == 0
                                ? DirectoryPage(
                                    key: ValueKey(revision),
                                    api: api,
                                  )
                                : ImportsPage(
                                    api: api,
                                    onImported: () => setState(() {
                                      revision++;
                                    }),
                                  ))
                          : ProfilePage(
                              key: ValueKey('profile-$page'),
                              api: api,
                              historyOnly: page == 1,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (index) => setState(() => page = index),
              destinations: [
                for (var i = 0; i < titles.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: titles[i]),
              ],
            ),
    );
  }

  Widget _sidebar() => Container(
    width: 250,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101A35), Color(0xFF080F23)],
      ),
      border: Border(right: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.fromLTRB(22, 27, 22, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Brand(light: true),
        const SizedBox(height: 40),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            isHr ? 'ПРОСТРАНСТВО HR' : 'МОЁ РАЗВИТИЕ',
            style: const TextStyle(
              color: muted,
              fontSize: 9,
              letterSpacing: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 17),
        for (var i = 0; i < titles.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Container(
              decoration: BoxDecoration(
                gradient: page == i
                    ? const LinearGradient(
                        colors: [Color(0xFF24366F), Color(0xFF242444)],
                      )
                    : null,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: page == i
                      ? const Color(0xFF4F63A5)
                      : Colors.transparent,
                ),
                boxShadow: page == i
                    ? [
                        BoxShadow(
                          color: blue.withValues(alpha: .09),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(13),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 13),
                  horizontalTitleGap: 11,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  leading: Icon(
                    icons[i],
                    color: page == i ? ink : muted,
                    size: 20,
                  ),
                  title: Text(
                    titles[i],
                    style: TextStyle(
                      color: page == i ? ink : muted,
                      fontSize: 12,
                      fontWeight: page == i ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  onTap: () => setState(() => page = i),
                ),
              ),
            ),
          ),
        const Spacer(),
        if (MediaQuery.sizeOf(context).height >= 690) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 235,
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: line),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/career_landscape.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x1A101830), Color(0xF00D152B)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.auto_awesome_outlined,
                          color: pink,
                          size: 23,
                        ),
                        const Spacer(),
                        Text(
                          isHr
                              ? 'За каждым профилем —\nсвой путь.'
                              : 'Большие возможности\nначинаются с тебя.',
                          style: const TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          isHr
                              ? 'Помогайте людям видеть своё развитие.'
                              : 'Выбери цель своего следующего шага.',
                          style: const TextStyle(
                            color: Color(0xFFD0D8EE),
                            height: 1.6,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 23),
        ],
        const Divider(color: line),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 17, color: muted),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                isHr ? 'HR · демонстрация' : 'Сотрудник · демонстрация',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
            IconButton(
              tooltip: 'Выйти',
              onPressed: signingOut ? null : logout,
              icon: const Icon(Icons.logout, size: 18, color: muted),
            ),
          ],
        ),
      ],
    ),
  );
}
