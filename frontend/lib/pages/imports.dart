import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../widgets/ui.dart';

class ImportsPage extends StatefulWidget {
  const ImportsPage({super.key, required this.api, required this.onImported});
  final CareerApi api;
  final VoidCallback onImported;
  @override
  State<ImportsPage> createState() => _ImportsPageState();
}

class _ImportsPageState extends State<ImportsPage> {
  UploadFile? employees;
  UploadFile? history;
  String policy = 'reject';
  bool busy = false;
  String? error;
  Json? preview;
  Json? result;

  void invalidate() {
    preview = null;
    result = null;
    error = null;
  }

  Future<void> pick(bool isEmployees) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: [isEmployees ? 'json' : 'csv'],
      );
      if (file == null || !mounted) return;
      setState(invalidate);
      final length = await file.length();
      if (length != null && length > 5 * 1024 * 1024) {
        if (mounted) {
          setState(
            () => error =
                'Файл больше 5 МБ. Разделите данные на несколько файлов.',
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        invalidate();
        if (isEmployees) {
          employees = UploadFile(file.name, bytes);
        } else {
          history = UploadFile(file.name, bytes);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Не удалось открыть файл. Выберите его ещё раз.',
        );
      }
    }
  }

  Future<void> validate() async {
    setState(() {
      busy = true;
      error = null;
      preview = null;
      result = null;
    });
    try {
      final response = await widget.api.previewImport(
        employees: employees,
        history: history,
        policy: policy,
      );
      if (mounted) setState(() => preview = response);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> commit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await widget.api.request(
        'POST',
        '/api/hr/import/commit',
        {'preview_id': preview!['preview_id']},
      );
      if (mounted) {
        setState(() {
          result = response;
          preview = null;
        });
        widget.onImported();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          if (e is ApiException && e.statusCode == 409) preview = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 36 : 20),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Загрузка данных',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.9,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Добавьте профили и историю, чтобы продолжить работу с новыми сотрудниками.',
                style: TextStyle(color: muted, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 27),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _step(
                    '1',
                    'Выберите файлы',
                    preview == null && result == null,
                  ),
                  _step('2', 'Проверьте изменения', preview != null),
                  _step('3', 'Подтвердите загрузку', result != null),
                ],
              ),
              const SizedBox(height: 25),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      'Какие данные добавить?',
                      subtitle: 'Один или два файла, до 5 МБ каждый. Используйте исходную схему датасета.',
                    ),
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, box) => box.maxWidth >= 680
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _fileCard(true)),
                                const SizedBox(width: 20),
                                Expanded(child: _fileCard(false)),
                              ],
                            )
                          : Column(
                              children: [
                                _fileCard(true),
                                const SizedBox(height: 16),
                                _fileCard(false),
                              ],
                            ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 18),
                    const Text(
                      'Если ID уже существует',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Полностью совпадающие записи пропускаются при любом варианте.',
                      style: TextStyle(color: muted, height: 1.5, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: policy,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Правило для отличающихся записей',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'reject',
                          child: Text(
                            'Остановить загрузку при конфликте',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'replace',
                          child: Text(
                            'Заменить существующие записи',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (choice) => setState(() {
                              policy = choice!;
                              invalidate();
                            }),
                    ),
                    if (policy == 'replace') ...[
                      const SizedBox(height: 14),
                      const Notice(
                        'После подтверждения записи с совпадающими ID будут обновлены значениями из файлов. Сначала проверьте количество изменений.',
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: busy || (employees == null && history == null)
                          ? null
                          : validate,
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: Text(
                        busy && preview == null
                            ? 'Проверяем…'
                            : 'Проверить файлы',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (error != null) ...[
                Notice(error!, error: true),
                const SizedBox(height: 18),
              ],
              if (preview != null) _summary(preview!, false),
              if (result != null) _summary(result!, true),
              const SizedBox(height: 20),
              const Notice(
                'Загрузка применяется целиком после подтверждения. Если файл содержит ошибку или неверную ссылку на сотрудника либо мероприятие, данные не изменятся.',
              ),
              const SizedBox(height: 22),
              const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Требования к файлам',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                childrenPadding: EdgeInsets.fromLTRB(0, 0, 0, 14),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Профили: JSON с массивом employees в исходной структуре.\nИстория: CSV с заголовком record_id, employee_id, event_id, date, due_date, status, completion_pct, score, feedback_rating, assigned_by.\n\nДля истории нового сотрудника загрузите его профиль в той же операции. Навыки, роли и мероприятия должны существовать в каталоге. Файлы должны быть в кодировке UTF-8.',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(String number, String label, bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      gradient: active
          ? const LinearGradient(colors: [Color(0xFF302B57), Color(0xFF252E51)])
          : null,
      color: active ? null : const Color(0xFF111B32),
      border: Border.all(color: active ? const Color(0xFF77649B) : line),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: active ? green : const Color(0xFF2A3455),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: active ? const Color(0xFF22172F) : muted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? ink : muted,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _fileCard(bool isEmployees) {
    final file = isEmployees ? employees : history;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: file == null
              ? const [Color(0xFF131F3D), Color(0xFF1B2040)]
              : const [Color(0xFF26264B), Color(0xFF352742)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: file == null ? line : green),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEmployees ? Icons.badge_outlined : Icons.history_edu_outlined,
                color: green,
                size: 25,
              ),
              const Spacer(),
              Tag(
                isEmployees ? 'JSON' : 'CSV',
                background: const Color(0xFF29365C),
                color: const Color(0xFFB4CCFF),
              ),
            ],
          ),
          const SizedBox(height: 19),
          Text(
            isEmployees ? 'Профили сотрудников' : 'История активностей',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 9),
          Text(
            isEmployees
                ? 'Роли, навыки, карьерные цели'
                : 'Участие, завершения, результаты',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          if (file != null) ...[
            Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: green,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => pick(isEmployees),
                icon: Icon(
                  file == null ? Icons.add : Icons.swap_horiz,
                  size: 17,
                ),
                label: Text(
                  file == null ? 'Выбрать файл' : 'Заменить файл',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (file != null)
                IconButton(
                  tooltip: 'Убрать файл',
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          if (isEmployees) {
                            employees = null;
                          } else {
                            history = null;
                          }
                          invalidate();
                        }),
                  icon: const Icon(Icons.close, color: muted, size: 17),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(Json data, bool committed) {
    final summary = Json.from(data['summary']);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            committed ? 'Данные загружены' : 'Всё готово к загрузке',
            subtitle: committed
                ? 'Изменения сохранены. Профили доступны в разделе «Сотрудники».'
                : 'Проверьте изменения. Пока ничего не сохранено.',
            action: Icon(
              committed ? Icons.check_circle_outline : Icons.task_alt,
              color: green,
              size: 29,
            ),
          ),
          const SizedBox(height: 20),
          for (final entry in {
            'employees': 'Профили сотрудников',
            'activities': 'Записи истории',
          }.entries) ...[
            Text(
              entry.value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Tag('Новых: ${summary[entry.key]['added']}'),
                Tag(
                  'Обновлений: ${summary[entry.key]['updated']}',
                  color: const Color(0xFFC7AEFF),
                  background: const Color(0xFF302649),
                ),
                Tag(
                  'Без изменений: ${summary[entry.key]['unchanged']}',
                  color: muted,
                  background: paper,
                ),
              ],
            ),
            const SizedBox(height: 22),
          ],
          for (final warning in data['warnings'] as List? ?? []) ...[
            Notice(warning.toString()),
            const SizedBox(height: 12),
          ],
          if (!committed) ...[
            Text(
              'Подтверждение доступно до ${_expiry(data['expires_at'])}. При изменении данных понадобится повторная проверка.',
              style: const TextStyle(color: muted, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : commit,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(busy ? 'Сохраняем…' : 'Подтвердить загрузку'),
            ),
          ],
        ],
      ),
    );
  }

  String _expiry(dynamic date) {
    final parsed = date is num
        ? DateTime.fromMillisecondsSinceEpoch(date.toInt() * 1000).toLocal()
        : DateTime.tryParse(value(date))?.toLocal();
    return parsed == null
        ? value(date)
        : '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }
}
