import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/ui.dart';
import '../../store/gate.dart';
import '../../theme.dart';
import '../widgets/state_box.dart';

/// 更新日誌：讀控制台登記的每個版本與更新內容
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  List<Map<String, Object?>>? _list;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final list = await context.read<GateStore>().changelog();
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) setState(() => _err = tr('讀不到更新日誌，請稍後再試'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<GateStore>();
    final list = _list;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('更新日誌'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          children: [
            if (list == null)
              ?StateBox.maybe(loading: _err == null, error: _err, onRetry: _load)
            else if (list.isEmpty)
              StateBox(empty: true, emptyText: tr('還沒有更新日誌'))
            else
              for (final r in list)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('${r['version']}',
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            if ((r['build'] as num?)?.toInt() == gate.build) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: .14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(tr('目前版本'),
                                    style: TextStyle(fontSize: 11.5, color: scheme.primary)),
                              ),
                            ],
                            const Spacer(),
                            Text(_day('${r['date'] ?? ''}'),
                                style: TextStyle(fontSize: 12.5, color: faint(context))),
                          ],
                        ),
                        if ('${r['notes'] ?? ''}'.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          for (final line in '${r['notes']}'.trim().split('\n'))
                            if (line.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 9, right: 8),
                                      child: Container(
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: subtle(context),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        line.trim().replaceFirst(RegExp(r'^[-*•・]\s*'), ''),
                                        style: const TextStyle(fontSize: 14.5, height: 1.55),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _day(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.year}/${d.month}/${d.day}';
  }
}
