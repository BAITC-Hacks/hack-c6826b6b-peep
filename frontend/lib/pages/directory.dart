import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../widgets/ui.dart';
import 'profile.dart';

class DirectoryPage extends StatefulWidget {
  const DirectoryPage({super.key, required this.api});
  final CareerApi api;
  @override
  State<DirectoryPage> createState() => _DirectoryPageState();
}

class _DirectoryPageState extends State<DirectoryPage> {
  final search = TextEditingController();
  Timer? debounce;
  int requestNumber = 0;
  int total = 0;
  List<Json> employees = [];
  bool busy = true;
  String? error;
  String? selectedId;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final request = ++requestNumber;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.get(
        '/api/hr/employees?q=${Uri.encodeQueryComponent(search.text.trim())}',
      );
      if (mounted && request == requestNumber) {
        setState(() {
          employees = records(result['employees']);
          total = result['total'] as int;
        });
      }
    } catch (e) {
      if (mounted && request == requestNumber) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && request == requestNumber) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (selectedId != null) {
      return ProfilePage(
        api: widget.api,
        employeeId: selectedId,
        onBack: () => setState(() => selectedId = null),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 36 : 20),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Люди и их направления',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.9,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Понимайте опыт сотрудника, прежде чем обсуждать следующий шаг.',
                style: TextStyle(color: muted, height: 1.6, fontSize: 14),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF172F53),
                      Color(0xFF282349),
                      Color(0xFF392740),
                    ],
                  ),
                  border: Border.all(color: const Color(0xFF4C497A)),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x223A46D7), blurRadius: 30),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF285988), Color(0xFF524386)],
                        ),
                        border: Border.all(color: const Color(0xFF6776AF)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.diversity_3_outlined,
                        color: lime,
                        size: 29,
                      ),
                    ),
                    const SizedBox(width: 22),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Развитие начинается с диалога',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 9),
                          Text(
                            'Откройте профиль: навыки, карьерная цель и история активностей помогут подготовиться к встрече.',
                            style: TextStyle(
                              color: Color(0xFFBAC8E3),
                              fontSize: 13,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      'Сотрудники',
                      subtitle: 'Профили и история развития',
                      action: Tag('$total', color: muted, background: paper),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      key: const Key('employee-search'),
                      controller: search,
                      decoration: InputDecoration(
                        hintText: 'Имя, отдел, роль или ID',
                        prefixIcon: const Icon(Icons.search, size: 21),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Очистить поиск',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  debounce?.cancel();
                                  search.clear();
                                  load();
                                },
                              ),
                      ),
                      onChanged: (_) {
                        setState(() {});
                        debounce?.cancel();
                        debounce = Timer(
                          const Duration(milliseconds: 300),
                          load,
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    if (busy) const LinearProgressIndicator(minHeight: 2),
                    if (error != null)
                      Notice(
                        error!,
                        error: true,
                        action: TextButton(
                          onPressed: load,
                          child: const Text('Повторить'),
                        ),
                      ),
                    if (!busy && employees.isEmpty && error == null)
                      const EmptyState(
                        'Сотрудники не найдены',
                        'Попробуйте другое имя или загрузите новые профили.',
                        icon: Icons.person_search_outlined,
                      ),
                    for (var i = 0; i < employees.length; i++) ...[
                      _employee(employees[i], wide),
                      if (i < employees.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _employee(Json employee, bool wide) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => setState(() => selectedId = employee['employee_id'] as String),
    hoverColor: const Color(0x204F66C3),
    splashColor: const Color(0x225966B8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF343B6C), Color(0xFF412D56)],
              ),
              border: Border.all(color: const Color(0xFF645580)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              initials(value(employee['full_name'])),
              style: const TextStyle(
                color: green,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value(employee['full_name']),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${value(employee['role'])} · ${value(employee['grade'])}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: muted,
                    height: 1.5,
                  ),
                ),
                if (!wide) ...[
                  const SizedBox(height: 7),
                  Text(
                    value(employee['department']),
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ],
            ),
          ),
          if (wide) ...[
            Expanded(
              flex: 3,
              child: Text(
                value(employee['department']),
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            const SizedBox(width: 15),
            Tag(
              employee['has_goal'] == true ? 'Цель выбрана' : 'Без цели',
              color: employee['has_goal'] == true ? green : muted,
              background: employee['has_goal'] == true ? mint : paper,
            ),
            const SizedBox(width: 18),
          ],
          const Icon(Icons.chevron_right_rounded, color: muted, size: 20),
        ],
      ),
    ),
  );
}
