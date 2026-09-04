import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/http.dart';
import '../i18n/ui.dart';
import '../platform_bindings.dart';
import 'notifications.dart';

/// iOS 這個名字必須同時寫進 Info.plist 的 BGTaskSchedulerPermittedIdentifiers，
/// 不然 BGTaskScheduler 會直接拒絕排程。
const backgroundTaskName = 'gm.badges';

const _kLastNotice = 'gm.bg.notice';
const _kLastPm = 'gm.bg.pm';

/// 背景輪詢的進入點。必須是頂層函式並標 vm:entry-point，
/// 否則 release 模式會被 tree shaking 掉。
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await checkBadgesInBackground();
    } catch (_) {
      // 背景失敗就安靜結束，下一輪再試
    }
    return true;
  });
}

/// 背景檢查有沒有新提醒／新私訊，有就發本地通知。
///
/// 只用 [api.fetchBadges]（讀頁首的未讀數），**不能改用 fetchNotice** ——
/// 那會把提醒標成已讀，等於一邊查一邊清掉。
Future<void> checkBadgesInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 背景是另一個 isolate，cookie jar 與語言表都要自己備妥。
  // gm_api 是純 Dart 的，path_provider/rootBundle 得先接上去，
  // 而且 main() 做的注入不會跨 isolate。
  await installFlutterBindings();
  await Api.instance.init();
  try {
    await UiLang.instance.load();
  } catch (_) {
    // 載不到就用繁體原文
  }

  final b = await api.fetchBadges();

  // 私訊數**不能用頁首那個**。頁首的私訊數是一個「新訊息提示」，使用者
  // 只要瞄一眼訊息列表，論壇就把它清成 0——可是對話本身還是未讀的。
  // 只看頁首的話，實際有好幾則沒讀卻永遠推不出通知。每則對話自己的
  // 未讀數才是真的，跟 App 裡紅點用的是同一個來源。
  var pm = b.pm;
  var pmName = '';
  var pmPreview = '';
  try {
    final list = await api.fetchPmList();
    pm = list.items.fold(0, (sum, i) => sum + i.unread);
    // 列表本來就依時間排序，第一則未讀的就是最新那則
    for (final it in list.items) {
      if (it.unread > 0) {
        pmName = it.name;
        pmPreview = it.last;
        break;
      }
    }
  } catch (_) {
    // 抓不到就退回頁首那個數字，至少不會完全沒有通知
  }

  final prefs = await SharedPreferences.getInstance();
  final lastNotice = prefs.getInt(_kLastNotice) ?? 0;
  final lastPm = prefs.getInt(_kLastPm) ?? 0;

  // 只在「變多」時通知：讀過而變少不用吵，維持原數也不用重複吵
  if (b.notice > lastNotice) {
    // 講得出「是哪一類」。要顯示提醒的**內容**就得去開提醒頁，而那會把
    // 該分類標成已讀，紅點會跟著消失。分類名稱從頁首就讀得到，沒有副作用。
    await Notifications.show(
      id: Notifications.idNotice,
      title: noticeTitle(b.views),
      body: '${tr('您有')} ${b.notice} ${tr('則未讀提醒')}',
    );
  }
  if (pm > lastPm) {
    // 標題＝［分類］寄件者，內文＝訊息本身，跟網頁版推播同一套格式
    final n = pmNotification(name: pmName, preview: pmPreview, unread: pm);
    await Notifications.show(
      id: Notifications.idPm,
      title: n.title,
      body: n.body,
    );
  }

  await prefs.setInt(_kLastNotice, b.notice);
  await prefs.setInt(_kLastPm, pm);
}

/// 提醒通知的標題：講得出「是哪一類」。
///
/// 要顯示提醒的**內容**就得去開提醒頁，而那會把該分類標成已讀，紅點會
/// 跟著消失。分類名稱從頁首就讀得到，沒有這個副作用。
/// 跟網頁版的伺服器推播共用同一組分類名稱（[api.noticeKindLabel]）。
String noticeTitle(Map<String, int> views) {
  final kinds = views.entries
      .where((e) => e.value > 0)
      .map((e) => tr(api.noticeKindLabel(e.key)))
      .toList();
  return kinds.isEmpty ? tr('[論壇提醒]') : '[${kinds.join('、')}]';
}

/// 私訊通知的標題與內文：標題＝［分類］寄件者，內文＝訊息本身。
///
/// iOS 會自己在標題底下補上「from GameMale」，所以標題不用再放 App 名字。
/// 抓不到內容時退回未讀則數。
({String title, String body}) pmNotification({
  required String name,
  required String preview,
  required int unread,
}) {
  final hasName = name.isNotEmpty;
  return (
    title: hasName ? '${tr('[私人消息]')} $name' : tr('[私人消息]'),
    body: hasName && preview.isNotEmpty
        ? preview
        : '${tr('您有')} $unread ${tr('則未讀消息')}',
  );
}

/// 前景每次對紅點時也把基準寫回去，免得回到背景又通知一次同樣的東西
Future<void> syncBadgeBaseline({required int notice, required int pm}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastNotice, notice);
  await prefs.setInt(_kLastPm, pm);
}

/// 打開背景檢查。iOS 由系統決定何時喚醒（強制關閉 App 就完全不會跑），
/// Android 會照 WorkManager 的週期跑，最短 15 分鐘。
Future<void> enableBackgroundBadges() async {
  // 網頁版的背景檢查是伺服器在做，不需要（也沒有）workmanager
  if (kIsWeb) return;
  await Workmanager().initialize(backgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundTaskName,
    backgroundTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

Future<void> disableBackgroundBadges() async {
  // 網頁版的背景檢查是伺服器在做，不需要（也沒有）workmanager
  if (kIsWeb) return;
  await Workmanager().cancelByUniqueName(backgroundTaskName);
}
