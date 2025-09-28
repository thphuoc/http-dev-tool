import 'dart:math';

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

final List<HttpEntry> mockEntries = List.generate(30, (i) {
  final success = i % 5 != 0;
  final code = success ? (200 + i % 20).toString() : (400 + i % 20).toString();
  final now = DateTime.now().subtract(Duration(minutes: i * 3));
  final random = Random();
  // generate 25+ headers, params, form fields
  final headers = Map.fromEntries(
    List.generate(25, (j) => MapEntry('Response Header-${random.nextInt(100)}', 'Value-$j')),
  );
  final headersRequest = Map.fromEntries(
    List.generate(0, (j) => MapEntry('Response Header-${random.nextInt(100)}', 'Value-$j')),
  );

  final params = Map.fromEntries(
    List.generate(25, (j) => MapEntry('param$j', 'value$j')),
  );

  final form = Map.fromEntries(
    List.generate(25, (j) => MapEntry('field$j', 'formValue$j')),
  );

  const String jsonString = """
{
  "id": 1,
  "oldId": null,
  "active": true,
  "name": "John Doe",
  "email": "johndoe@example.com",
  "phone": "+1-202-555-0123",
  "address": {
    "street": "123 Main St",
    "city": "Anytown",
    "state": "CA",
    "zip": "12345"
  },
  "aliases": [],
  "orders": [
    {
      "id": 1001,
      "items": [
        {
          "id": "A001",
          "name": "Widget A",
          "quantity": 2,
          "price": 9.99
        },
        {
          "id": "B002",
          "name": "Widget B",
          "quantity": 1,
          "price": 14.99
        }
      ],
      "total": 34.97,
      "status": "shipped"
    },
    {
      "id": 1002,
      "items": [
        {
          "id": "C003",
          "name": "Widget C",
          "quantity": 3,
          "price": 4.99,
          "hiddenField": "This field will be hidden"
        }
      ],
      "total": 14.97,
      "status": "pending"
    }
  ],
  "hiddenField": "This field will be hidden as well"
}
""";

  return HttpEntry(
    method: i % 3 == 0 ? 'POST' : i % 3 == 1 ? 'GET' : 'PUT',
    code: i % 7 == 0 ? 'N/A' : code,
    reqAt: now,
    resAt: i % 7 == 0 ? null : now.add(Duration(milliseconds: 200 + i * 50)),
    totalTime: i % 7 == 0 ? 'N/A' : '${(200 + i * 50) ~/ 1000}s',
    url: 'https://example.com/api/resource/${i + 1}?q=test&page=${i + 1}',
    requestHeaders: headersRequest,
    requestBody: '{"id": ${i + 1}, "name": "Item $i"}',
    requestForm: form,
    requestParams: params,
    responseHeaders: headers,
    responseBody: jsonString,
  );
});

