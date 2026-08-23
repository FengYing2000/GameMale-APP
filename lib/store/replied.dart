import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/http.dart';

/// 「我回過這帖沒有」的即時查詢。
///
/// 論壇沒有現成的清單可問，但帶 `authorid=<自己>` 打開帖子時，
/// 如果自己在這帖沒有任何發言，論壇會回一頁「未定义操作」的錯誤（約 4.7 KB）。
/// 有回過就正常回內容。這是論壇原生行為，油猴腳本也是靠這招。
///
/// 一頁二三十個主題就是二三十個請求，所以限制併發並排隊慢慢送。
/// 結果只放在記憶體：登出換帳號就整份丟掉，不會像存本機那樣留著別人的紀錄。
class RepliedStore extends ChangeNotifier {
  RepliedStore({this.concurrency = 3, this.gap = const Duration(milliseconds: 250)});

  final int concurrency;
  final Duration gap;

  bool enabled = false;
  int? _uid;

  final _state = <int, bool>{};
  final _pending = <int>{};
  final _queue = <int>[];
  int _running = 0;
  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);

  /// null = 還不知道
  bool? statusOf(int tid) => _state[tid];

  bool get hasAny => _state.isNotEmpty;

  /// 登入狀態改變時呼叫。換人或登出就把結果清掉 —— 這是「誰回過」的資料，
  /// 留著上一個帳號的答案只會誤導
  void setUser(int? uid) {
    if (_uid == uid) return;
    _uid = uid;
    _reset();
  }

  void setEnabled(bool v) {
    if (enabled == v) return;
    enabled = v;
    if (!v) _reset();
    notifyListeners();
  }

  void _reset() {
    _state.clear();
    _pending.clear();
    _queue.clear();
    notifyListeners();
  }

  /// 丟一批主題進來排隊。已經知道答案或正在查的會自動跳過
  void check(Iterable<int> tids) {
    if (!enabled || _uid == null) return;
    var added = false;
    for (final tid in tids) {
      if (_state.containsKey(tid) || _pending.contains(tid)) continue;
      _pending.add(tid);
      _queue.add(tid);
      added = true;
    }
    if (added) unawaited(_pump());
  }

  Future<void> _pump() async {
    while (_running < concurrency && _queue.isNotEmpty) {
      final tid = _queue.removeAt(0);
      _running++;
      unawaited(_run(tid));
    }
  }

  Future<void> _run(int tid) async {
    try {
      final wait = gap - DateTime.now().difference(_lastStart);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastStart = DateTime.now();

      final html = await Api.instance
          .get('forum.php?mod=viewthread&tid=$tid&authorid=$_uid');
      // 繁簡兩種都要認，論壇會照使用者語言給
      final none = html.contains('未定义操作') ||
          html.contains('未定義操作') ||
          html.contains('ERROR:');
      _state[tid] = !none;
      notifyListeners();
    } catch (_) {
      // 查不到就當作不知道，下次再問；不要誤標成「沒回過」
    } finally {
      _pending.remove(tid);
      _running--;
      unawaited(_pump());
    }
  }

  /// 剛回完帖，直接標起來，不用再問一次
  void markReplied(int tid) {
    if (_state[tid] == true) return;
    _state[tid] = true;
    notifyListeners();
  }
}
