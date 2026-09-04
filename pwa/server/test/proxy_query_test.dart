import 'package:test/test.dart';

/// 論壇轉發唯一有邏輯的地方就是「原始 query 要原封不動帶過去」。
/// 這裡把那個前提釘住——它壞過一次，而且症狀是整頁空白，很難聯想到 query。
void main() {
  group('轉發要保留原始 query', () {
    test('重複的參數不能被吃掉', () {
      // 論壇有些網址會帶重複參數（`&mobile=no&mobile=2`）。用 Map 重建會
      // 只留最後一個，論壇因此回不同模板，解析器就抓不到東西
      //（記錄廣場整頁空白就是這樣來的）。
      final url = Uri.parse('/gm/home.php?mod=space&do=doing&mobile=no&mobile=2');

      // Map 會把重複的 key 壓成一個——這正是不能用它的原因
      expect(url.queryParameters['mobile'], '2');
      expect(url.queryParametersAll['mobile'], ['no', '2']);

      // 原始字串則完整保留，轉發要用的是這個
      expect(url.query, contains('mobile=no'));
      expect(url.query, contains('mobile=2'));
    });
  });
}
