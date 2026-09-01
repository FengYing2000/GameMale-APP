import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import 'external_link.dart';
import 'toast.dart';

/// 附件內容。這站的付費附件幾乎都是 .txt，裡面是網盤連結與提取碼，
/// 交給瀏覽器只會看到亂碼（伺服器沒帶 charset），所以自己抓下來顯示。
Future<void> showAttachmentText(BuildContext context, Attachment a) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _Sheet(attachment: a),
  );
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.attachment});
  final Attachment attachment;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  String? _text;
  String? _err;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final t = await api.fetchAttachmentText(widget.attachment.url);
      if (mounted) setState(() => _text = t);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  /// 內容裡的網址挑出來，讓人直接點
  List<String> get _links => _text == null
      ? const []
      : RegExp(r'https?://[^\s一-鿿）)]+')
          .allMatches(_text!)
          .map((m) => m.group(0)!)
          .toSet()
          .toList();

  /// iOS 沒有「下載資料夾」可以丟，所以寫進 App 的暫存目錄再交給
  /// 系統分享單 —— 使用者要存到檔案 App、傳給別人都從那裡走
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await api.fetchAttachmentBytes(widget.attachment.url);
      final dir = await getTemporaryDirectory();
      // 檔名可能有斜線之類的字元，掃乾淨免得寫不進去
      final safe = widget.attachment.name
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/$safe');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await SharePlus.instance
          .share(ShareParams(files: [XFile(file.path)], title: safe));
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '${tr('存檔失敗：')}${e.message}');
    } catch (e) {
      if (mounted) toast(context, '${tr('存檔失敗：')}$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _text;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.attachment.name,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, height: 1.4)),
            if (widget.attachment.info.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(widget.attachment.info,
                  style: TextStyle(fontSize: 11.5, color: faint(context))),
            ],
            const SizedBox(height: 14),
            if (_err != null)
              Row(
                children: [
                  Expanded(
                    child: Text(_err!,
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.error)),
                  ),
                  TextButton(onPressed: _load, child: Text(tr('重試'))),
                ],
              )
            else if (t == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              Container(
                width: double.infinity,
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * .4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(t,
                      style: const TextStyle(fontSize: 13.5, height: 1.7)),
                ),
              ),
              const SizedBox(height: 12),
              if (_links.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final l in _links)
                      ActionChip(
                        avatar: const Icon(LucideIcons.externalLink, size: 15),
                        label: Text(Uri.tryParse(l)?.host ?? l,
                            style: const TextStyle(fontSize: 12.5)),
                        onPressed: () => confirmExternal(context, l),
                      ),
                  ],
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: t));
                        toast(context, tr('已複製內容'), kind: ToastKind.ok);
                      },
                      icon: const Icon(LucideIcons.copy, size: 17),
                      label: Text(tr('複製全部')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(LucideIcons.save, size: 17),
                      label: Text(_saving ? tr('存檔中…') : tr('存成檔案')),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
