import 'dart:convert';
import 'dart:io';

/// Test POST request via HTTP(S) proxy.
///
/// - proxyHost: địa chỉ proxy (ví dụ "192.168.0.102")
/// - proxyPort: port proxy (ví dụ 8888)
/// - rootCaPemPath: (optional) đường dẫn tới root CA PEM nếu proxy là MITM và bạn muốn tin CA đó
Future<void> testPostViaProxy({
  required String proxyHost,
  required int proxyPort,
  String? rootCaPemPath,
}) async {
  // Build SecurityContext: nếu có rootCA.pem thì dùng nó, ngược lại dùng default system roots.
  SecurityContext? ctx;
  if (rootCaPemPath != null) {
    ctx = SecurityContext(withTrustedRoots: false); // start with empty trust store
    try {
      ctx.setTrustedCertificates(rootCaPemPath);
      print('Trusted root CA loaded from: $rootCaPemPath');
    } catch (e) {
      stderr.writeln('Failed to load root CA from $rootCaPemPath: $e');
      return;
    }
  } else {
    // use default system trust store (ctx == null -> HttpClient uses default)
    ctx = null;
  }

  final client = HttpClient(context: ctx);
  // Route all requests through proxyHost:proxyPort
  client.findProxy = (Uri uri) {
    // For all protocols (http/https) use the proxy
    return 'PROXY $proxyHost:$proxyPort;';
  };

  // If you want to accept any certificate (insecure), uncomment the following.
  // Better: use rootCaPemPath to trust your proxy's CA.
  // client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;

  final url =
      Uri.parse('https://5a51bfb150dffb001256e08f.mockapi.io/testing/people');

  try {
    print('Connecting via proxy $proxyHost:$proxyPort to $url');

    final request = await client.postUrl(url);

    // Set headers
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    // Example JSON body
    final body = jsonEncode({
      'name': 'Nguyen Van A',
      'age': 30,
      'email': 'nguyenvana@example.com',
    });

    request.contentLength = utf8.encode(body).length;
    request.write(body);

    // Send request and wait response
    final response = await request.close();

    print('Response status: ${response.statusCode} ${response.reasonPhrase}');
    final respBody = await response.transform(utf8.decoder).join();
    print('Response body:\n$respBody');
  } catch (e, st) {
    stderr.writeln('Request failed: $e\n$st');
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  // Example usage:
  const proxyHost = '127.0.0.1';
  const proxyPort = 8888;

  // If your proxy is MITM and you have rootCA.crt, pass its path here (PEM).
  // Otherwise set to null to use system trust store.
  const rootCaPath = './rootCA.crt'; // e.g. 'C:\\path\\to\\rootCA.crt' or '/home/user/rootCA.crt'

  await testPostViaProxy(
    proxyHost: proxyHost,
    proxyPort: proxyPort,
    rootCaPemPath: rootCaPath,
  );
}
