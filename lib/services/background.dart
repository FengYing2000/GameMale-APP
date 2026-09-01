import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/discuz.dart' as api;
import '../api/http.dart';
import '../i18n/ui.dart';
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
  // 背景是另一個 isolate，cookie jar 與語言表都要自己備妥
  await Api.instance.init();
  try {
    await UiLang.instance.load();
  } catch (_) {
    // 載不到就用繁體原文
  }

  final b = await api.fetchBadges();
  final prefs = await SharedPreferences.getInstance();
  final lastNotice = prefs.getInt(_kLastNotice) ?? 0;
  final lastPm = prefs.getInt(_kLastPm) ?? 0;

  // 只在「變多」時通知：讀過而變少不用吵，維持原數也不用重複吵
  if (b.notice > lastNotice) {
    await Notifications.show(
      id: Notifications.idNotice,
      title: tr('有新提醒'),
      body: '${tr('你有')} ${b.notice} ${tr('則未讀提醒')}',
    );
  }
  if (b.pm > lastPm) {
    await Notifications.show(
      id: Notifications.idPm,
      title: tr('有新私訊'),
      body: '${tr('你有')} ${b.pm} ${tr('則未讀私訊')}',
    );
  }

  await prefs.setInt(_kLastNotice, b.notice);
  await prefs.setInt(_kLastPm, b.pm);
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
  await Workmanager().cancelByUniqueName(backgroundTaskName);
}
