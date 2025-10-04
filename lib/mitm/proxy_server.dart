import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'config.dart';
import 'http_message.dart';
import 'mitm_handler.dart';
import 'models.dart';
import 'rule_engine.dart';
import 'rule_store.dart';
import 'gen_root_ca.dart';

class ProxyServer {
  late final RuleStore _ruleStore;
  List<RewriteRule> _activeRules = [];
  StreamSubscription<FileSystemEvent>? _rulesWatcherSub;
  final MitmHandler mitmHandler;
  String _listenHost = '0.0.0.0';
  int _listenPort = Config.defaultPort;

  ProxyServer({required this.mitmHandler}) {
    _ruleStore = RuleStore(Config.rulesFilePath);
  }

  List<RewriteRule> getActiveRules() => _activeRules;

  Future<void> _loadRulesAndWatch() async {
    _activeRules = await _ruleStore.load();
    try {
      _rulesWatcherSub?.cancel();
      _rulesWatcherSub = File(Config.rulesFilePath).watch().listen((
        event,
      ) async {
        await Future.delayed(const Duration(milliseconds: 200));
        _activeRules = await _ruleStore.load();
        print('Rules reloaded (${_activeRules.length})');
      });
    } catch (_) {}
  }

  Future<void> startProxy(String host, int port) async {
    _listenHost = host;
    _listenPort = port;
    if (!Directory(Config.certsDir).existsSync()) {
      stderr.writeln(
        'certs dir "${Config.certsDir}" missing. Create it and put ${Config.rootKeyFile} & ${Config.rootCertFile}.',
      );
      exit(2);
    }
    print('Starting proxy on $host:$port ...');
    await _loadRulesAndWatch();
    final server = await ServerSocket.bind(host, port);
    print('Proxy listening on $host:$port');
    await for (final client in server) {
      _handleClient(client);
    }
  }

  void _handleClient(Socket client) {
    _handleClientAsync(client).catchError((e, st) {
      stderr.writeln('Client handler error: $e\n$st');
      try {
        client.destroy();
      } catch (_) {}
    });
  }

  // helper: find index of CRLFCRLF (byte-wise)
  int _indexOfCrlfCrlf(List<int> bytes) {
    final pattern = <int>[13, 10, 13, 10]; // \r\n\r\n
    if (bytes.length < pattern.length) return -1;
    for (var i = 0; i <= bytes.length - pattern.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  Future<void> _handleClientAsync(Socket client) async {
    client.setOption(SocketOption.tcpNoDelay, true);

    final buffer = <int>[];
    final completer = Completer<void>();
    StreamSubscription<List<int>>? sub;

    sub = client.listen(
      (data) async {
        print('Received ${data.length} bytes');
        // append incoming bytes
        buffer.addAll(data);
        final decoced = utf8.decode(buffer, allowMalformed: true);
        print('decoded: $decoced');

        // check end of headers
        final idx = _indexOfCrlfCrlf(buffer);
        print('idx crlf: $idx');
        if (idx >= 0) {
          // found end of headers
          // compute header bytes and remainder bytes
          final headerEnd = idx + 4;
          final headerBytes = buffer.sublist(0, headerEnd);
          final decodedHeader = utf8.decode(headerBytes, allowMalformed: true);
          final tslBytes = buffer.sublist(headerEnd);
          print('decodedHeader: $decodedHeader');
          print('tslBytes= $tslBytes');
          // cancel subscription (stop consuming socket)
          //await sub?.cancel();

          // process initial request and pass remainder (may be empty)
          await _processInitialRequest(client, headerBytes, tslBytes);

          if (!completer.isCompleted) completer.complete();
        } else {
          // safety: if headers too large, abort
          if (buffer.length > 64 * 1024) {
            stderr.writeln('Header too large, closing');
            await sub?.cancel();
            try {
              client.destroy();
            } catch (_) {}
            if (!completer.isCompleted) completer.complete();
          }
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  // updated to accept remainder bytes that were read after the headers
  Future<void> _processInitialRequest(
    Socket client,
    List<int> initialHeaderBytes,
    List<int> tslBytes,
  ) async {
    final headerStr = utf8.decode(initialHeaderBytes, allowMalformed: true);
    final firstLine = headerStr.split('\r\n')[0];

    if (firstLine.startsWith('CONNECT')) {
      // --------------------- HTTPS CONNECT branch ---------------------
      final parts = firstLine.split(' ');
      if (parts.length < 2) {
        client.destroy();
        return;
      }

      final hostPort = parts[1];
      final hp = hostPort.split(':');
      final host = hp[0];
      final port = hp.length > 1 ? int.tryParse(hp[1]) ?? 443 : 443;
      if (tslBytes.isEmpty) {
        print('<-- HTTP/1.1 200 Connection Established');
        // 1️⃣ Gửi phản hồi 200 Connection Established
        client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        await client.flush();
      } else {
        // 4️⃣ Chuyển sang xử lý MITM (bắt đầu handshake TLS với client)
        await mitmHandler.handle(
          client,
          host,
          port,
          initialTlsData: tslBytes,
        );
      }

      // 2️⃣ Đợi client bắt đầu gửi handshake TLS (ClientHello)
      // Nếu client im lặng quá lâu, ta timeout
      // if (initialTlsData == null || initialTlsData.isEmpty) {
      //   stderr.writeln('No TLS data received from client after CONNECT.');
      //   client.destroy();
      //   return;
      // }

      // 3️⃣ In ra 5 byte đầu tiên để kiểm tra TLS handshake
      //print('TLS first bytes: ${initialTlsData.take(5).toList()}');
    } else {
      // --------------------- HTTP (non-CONNECT) branch ---------------------
      final msg = HttpParser.tryParseHttpMessage(initialHeaderBytes);
      if (msg == null) {
        client.destroy();
        return;
      }
      final hostHeader = msg.headers['host'];
      if (hostHeader == null) {
        client.destroy();
        return;
      }

      final host = hostHeader.split(':').first;
      final port = hostHeader.contains(':')
          ? int.tryParse(hostHeader.split(':').last) ?? 80
          : 80;
      final path = HttpParser.extractPathFromRequestStartLine(msg.startLine);

      final method = HttpParser.extractMethodFromRequestStartLine(
        msg.startLine,
      );
      final requestUrl = 'http://$hostHeader$path';
      print('[REQUEST] $method $requestUrl');

      if (msg.bodyBytes.isNotEmpty) {
        final bodyStr = utf8.decode(msg.bodyBytes, allowMalformed: true);
        print(
          '[REQUEST BODY] ${bodyStr.length > 500 ? '${bodyStr.substring(0, 500)}...' : bodyStr}',
        );
      }

      // Nếu request tới proxy local, trả về CA file
      if (_shouldServeLocal(host, port)) {
        await _serveLocalEndpoint(client, path);
        return;
      }

      // Tiếp tục forward request HTTP bình thường
      Socket upstream;
      try {
        upstream = await Socket.connect(host, port);
      } catch (e) {
        stderr.writeln('Failed connect to upstream $host:$port : $e');
        client.destroy();
        return;
      }

      upstream.add(initialHeaderBytes);

      final respBuffer = <int>[];
      await upstream
          .listen(
            (d) {
              respBuffer.addAll(d);
            },
            onDone: () async {
              final respMsg = HttpParser.tryParseHttpMessage(respBuffer);
              if (respMsg == null) {
                client.add(respBuffer);
                client.destroy();
                upstream.destroy();
                return;
              }

              final statusCode =
                  HttpParser.parseStatusCode(respMsg.startLine) ?? 200;
              final rule = findMatchingRule(
                _activeRules,
                host: host,
                path: path,
                method: method,
                originalStatus: statusCode,
              );

              if (rule != null) {
                final currentHeaders = Map<String, String>.from(
                  respMsg.headers,
                );
                final applied = applyRuleToResponse(
                  rule,
                  statusCode,
                  respMsg.bodyBytes,
                  currentHeaders,
                );
                final newStatus = applied.key;
                final newBodyBytes = applied.value;
                final sb = StringBuffer();
                sb.writeln('HTTP/1.1 $newStatus ');
                currentHeaders.forEach((k, v) {
                  sb.writeln('${canonicalHeaderName(k)}: $v');
                });
                sb.writeln();
                client.add(utf8.encode(sb.toString()));
                client.add(newBodyBytes);
              } else {
                client.add(respBuffer);
              }

              client.destroy();
              upstream.destroy();
            },
            onError: (e) {
              stderr.writeln('Upstream listen error: $e');
              client.destroy();
              upstream.destroy();
            },
          )
          .asFuture();
    }
  }

  // --------------- CLI helpers moved from main ---------------
  String _genId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(100000)}';

  bool _shouldServeLocal(String host, int port) {
    if (port != _listenPort) return false;
    if (_listenHost == '0.0.0.0' || _listenHost == '::') return true;
    if (host == _listenHost) return true;
    if (host == 'localhost' || host == '127.0.0.1')
      return _listenHost == '127.0.0.1' || _listenHost == 'localhost';
    return false;
  }

  Future<void> _serveLocalEndpoint(Socket client, String path) async {
    if (path == '/' || path.isEmpty) {
      final html =
          '<html><head><title>MITM Proxy</title></head><body>'
          '<h1>MITM Proxy</h1>'
          '<p>Nhấn vào liên kết để tải Root CA:</p>'
          '<p><a href="/cert">Download Root CA (CRT)</a></p>'
          '</body></html>';
      final body = utf8.encode(html);
      final headers =
          'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n';
      client.add(utf8.encode(headers));
      client.add(body);
      await client.flush();
      client.destroy();
      return;
    }

    if (path == '/cert' || path == '/rootCA.crt') {
      final crtPath = Config.rootCertFile;
      var crtFile = File(crtPath);
      if (!await crtFile.exists()) {
        // Try to generate from PEM if available
        generateRootCAWithSAN();
      }
      if (!await crtFile.exists()) {
        final notFound =
            'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n';
        client.add(utf8.encode(notFound));
        await client.flush();
        client.destroy();
        return;
      }
      final bytes = await crtFile.readAsBytes();
      final headers =
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: application/x-x509-ca-cert\r\n'
          'Content-Disposition: attachment; filename="rootCA.crt"\r\n'
          'Content-Length: ${bytes.length}\r\n'
          'Connection: close\r\n\r\n';
      client.add(utf8.encode(headers));
      client.add(bytes);
      await client.flush();
      client.destroy();
      return;
    }

    final notFound =
        'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n';
    client.add(utf8.encode(notFound));
    await client.flush();
    client.destroy();
  }

  Future<void> addRule({
    required String host,
    required String path,
    required String method,
    int? matchStatus,
    int? status,
    String? body,
    Map<String, String>? headers,
  }) async {
    final rules = await _ruleStore.load();
    final id = _genId();
    final rule = RewriteRule(
      id: id,
      match: MatchSpec(
        host: host,
        pathRegex: path,
        method: method,
        status: matchStatus,
      ),
      actions: ActionSpec(
        status: status,
        body: body,
        headers: headers == null || headers.isEmpty ? null : headers,
      ),
      enabled: true,
    );
    rules.add(rule);
    await _ruleStore.save(rules);
    _activeRules = rules;
    print('Added rule id=$id');
  }

  Future<void> listRules() async {
    final rules = await _ruleStore.load();
    if (rules.isEmpty) {
      print('No rules');
      return;
    }
    for (final r in rules) {
      print('${r.id} ${r.enabled ? '[ENABLED]' : '[DISABLED]'}');
      print(
        '  match: host=${r.match.host} path=${r.match.pathRegex} method=${r.match.method} status=${r.match.status}',
      );
      print(
        '  actions: status=${r.actions.status} body=${r.actions.body != null ? "<present>" : "null"} headers=${r.actions.headers}',
      );
    }
  }

  Future<void> removeRule(String id) async {
    final rules = await _ruleStore.load();
    final before = rules.length;
    rules.removeWhere((r) => r.id == id);
    await _ruleStore.save(rules);
    _activeRules = rules;
    print('Removed $before -> ${rules.length}');
  }

  Future<void> toggleRule(String id, bool enable) async {
    final rules = await _ruleStore.load();
    final idx = rules.indexWhere((x) => x.id == id);
    if (idx < 0) {
      print('No such rule $id');
      return;
    }
    rules[idx].enabled = enable;
    await _ruleStore.save(rules);
    _activeRules = rules;
    print('${enable ? "Enabled" : "Disabled"} $id');
  }
}
