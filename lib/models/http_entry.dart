class HttpEntry {
  final String method;
  final String code;
  final DateTime reqAt;
  final DateTime? resAt;
  final String totalTime;
  final String url;
  final Map<String, String> requestHeaders;
  final String requestBody;
  final Map<String, String> requestForm;
  final Map<String, String> requestParams;
  final Map<String, String> responseHeaders;
  final String responseBody;

  HttpEntry({
    required this.method,
    required this.code,
    required this.reqAt,
    required this.resAt,
    required this.totalTime,
    required this.url,
    required this.requestHeaders,
    required this.requestBody,
    required this.requestForm,
    required this.requestParams,
    required this.responseHeaders,
    required this.responseBody,
  });
}

final List<HttpEntry> mockEntries = List.generate(15, (i) {
  final success = i % 5 != 0;
  final code = success ? (200 + i % 20).toString() : (400 + i % 20).toString();
  final now = DateTime.now().subtract(Duration(minutes: i * 3));
  return HttpEntry(
    method: i % 3 == 0 ? 'POST' : 'GET',
    code: i % 7 == 0 ? 'N/A' : code,
    reqAt: now,
    resAt: i % 7 == 0 ? null : now.add(Duration(milliseconds: 200 + i * 50)),
    totalTime: i % 7 == 0 ? 'N/A' : '${(200 + i * 50) ~/ 1000}s',
    url: 'https://example.com/api/resource/${i + 1}?q=test',
    requestHeaders: {'Accept': 'application/json', 'User-Agent': 'MockClient/1.0'},
    requestBody: '{"id": ${i + 1}, "name": "Item $i"}',
    requestForm: {'field1': 'value1', 'field2': 'value2'},
    requestParams: {'q': 'test', 'page': '1'},
    responseHeaders: {'Content-Type': 'application/json'},
    responseBody: '{"ok": ${success ? 'true' : 'false'}, "count": ${i * 3}}',
  );
});
