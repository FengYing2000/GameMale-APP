import 'package:flutter/material.dart';

import '../../theme.dart';

/// 載入中 / 錯誤 / 空清單三種狀態共用
class StateBox extends StatelessWidget {
  const StateBox({
    super.key,
    this.loading = false,
    this.error,
    this.empty = false,
    this.emptyText = '這裡什麼都沒有',
    this.onRetry,
  });

  final bool loading;
  final String? error;
  final bool empty;
  final String emptyText;
  final VoidCallback? onRetry;

  /// 沒有任何狀態要顯示時回傳 null，讓呼叫端決定要不要放進版面
  static Widget? maybe({
    required bool loading,
    String? error,
    bool empty = false,
    String emptyText = '這裡什麼都沒有',
    VoidCallback? onRetry,
  }) {
    if (!loading && error == null && !empty) return null;
    return StateBox(
      loading: loading,
      error: error,
      empty: empty,
      emptyText: emptyText,
      onRetry: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 70),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 28),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 38, color: faint(context)),
            const SizedBox(height: 10),
            Text(error!, textAlign: TextAlign.center, style: TextStyle(color: subtle(context))),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('重試')),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Center(
        child: Text(emptyText, style: TextStyle(color: faint(context), fontSize: 14)),
      ),
    );
  }
}
