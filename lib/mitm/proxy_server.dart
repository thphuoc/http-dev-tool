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

class ProxyServer {
  late final RuleStore _ruleStore;
  List<RewriteRule> _activeRules = [];
  StreamSubscription<FileSystemEvent>? _rulesWatcherSub;
  final MitmHandler mitmHandler;

  ProxyServer({required this.mitmHandler}) {
    _ruleStore = RuleStore(Config.rulesFilePath);
  }

  List<RewriteRule> getActiveRules() => _activeRules;

  Future<void> _loadRulesAndWatch() async {
    _activeRules = await _ruleStore.load();
    try {
      _rulesWatcherSub?.cancel();
      _rulesWatcherSub = File(Config.rulesFilePath).watch().listen((event) async {
        await Future.delayed(const Duration(milliseconds: 200));
        _activeRules = await _ruleStore.load();
        print('Rules reloaded (${_activeRules.length})');
      });
    } catch (_) {}
  }

  Future<void> startProxy(String host, int port) async {
    if (!Directory(Config.certsDir).existsSync()) {
      stderr.writeln('certs dir "${Config.certsDir}" missing. Create it and put ${Config.rootKeyFile} & ${Config.rootCertFile}.');
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
      try { client.destroy(); } catch (_) {}
    });
  }

  Future<void> _handleClientAsync(Socket client) async {
    client.setOption(SocketOption.tcpNoDelay, true);
    final buffer = <int>[];
    final completer = Completer<void>();
    StreamSubscription? sub;
    sub = client.listen((data) async {
      buffer.addAll(data);
      final s = utf8.decode(buffer, allowMalformed: true);
      if (s.contains('\r\n\r\n')) {
        await sub?.cancel();
        await _processInitialRequest(client, buffer);
        completer.complete();
      }
    }, onDone: () {
      if (!completer.isCompleted) completer.complete();
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    });
    return completer.future;
  }

  Future<void> _processInitialRequest(Socket client, List<int> initialBuffer) async {
    final headerStr = utf8.decode(initialBuffer, allowMalformed: true);
    final firstLine = headerStr.split('\r\n')[0];
    if (firstLine.startsWith('CONNECT')) {
      final parts = firstLine.split(' ');
      if (parts.length < 2) { client.destroy(); return; }
      final hostPort = parts[1];
      final hp = hostPort.split(':');
      final host = hp[0];
      final port = hp.length > 1 ? int.tryParse(hp[1]) ?? 443 : 443;
      print('[CONNECT] $host:$port');
      client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      await client.flush();
      await mitmHandler.handle(client, host, port);
    } else {
      final msg = HttpParser.tryParseHttpMessage(initialBuffer);
      if (msg == null) { client.destroy(); return; }
      final hostHeader = msg.headers['host'];
      if (hostHeader == null) { client.destroy(); return; }
      final host = hostHeader.split(':').first;
      final port = hostHeader.contains(':') ? int.tryParse(hostHeader.split(':').last) ?? 80 : 80;
      Socket upstream;
      try {
        upstream = await Socket.connect(host, port);
      } catch (e) {
        stderr.writeln('Failed connect to upstream $host:$port : $e');
        client.destroy();
        return;
      }
      upstream.add(initialBuffer);
      final respBuffer = <int>[];
      await upstream.listen((d) { respBuffer.addAll(d); }, onDone: () async {
        final respMsg = HttpParser.tryParseHttpMessage(respBuffer);
        if (respMsg == null) {
          client.add(respBuffer);
          client.destroy();
          upstream.destroy();
          return;
        }
        final statusCode = HttpParser.parseStatusCode(respMsg.startLine) ?? 200;
        final path = HttpParser.extractPathFromRequestStartLine(msg.startLine);
        final method = HttpParser.extractMethodFromRequestStartLine(msg.startLine);
        final rule = findMatchingRule(_activeRules, host: host, path: path, method: method, originalStatus: statusCode);
        if (rule != null) {
          final currentHeaders = Map<String, String>.from(respMsg.headers);
          final applied = applyRuleToResponse(rule, statusCode, respMsg.bodyBytes, currentHeaders);
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
      }, onError: (e) {
        stderr.writeln('Upstream listen error: $e');
        client.destroy();
        upstream.destroy();
      }).asFuture();
    }
  }

  // --------------- CLI helpers moved from main ---------------
  String _genId() => '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(100000)}';

  Future<void> addRule({required String host, required String path, required String method, int? matchStatus, int? status, String? body, Map<String, String>? headers}) async {
    final rules = await _ruleStore.load();
    final id = _genId();
    final rule = RewriteRule(
      id: id,
      match: MatchSpec(host: host, pathRegex: path, method: method, status: matchStatus),
      actions: ActionSpec(status: status, body: body, headers: headers == null || headers.isEmpty ? null : headers),
      enabled: true,
    );
    rules.add(rule);
    await _ruleStore.save(rules);
    _activeRules = rules;
    print('Added rule id=$id');
  }

  Future<void> listRules() async {
    final rules = await _ruleStore.load();
    if (rules.isEmpty) { print('No rules'); return; }
    for (final r in rules) {
      print('${r.id} ${r.enabled ? '[ENABLED]' : '[DISABLED]'}');
      print('  match: host=${r.match.host} path=${r.match.pathRegex} method=${r.match.method} status=${r.match.status}');
      print('  actions: status=${r.actions.status} body=${r.actions.body != null ? "<present>" : "null"} headers=${r.actions.headers}');
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
    if (idx < 0) { print('No such rule $id'); return; }
    rules[idx].enabled = enable;
    await _ruleStore.save(rules);
    _activeRules = rules;
    print('${enable ? "Enabled" : "Disabled"} $id');
  }
}


