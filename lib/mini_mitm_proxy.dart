// bin/mini_mitm_proxy.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'dart:typed_data';

// ---------------- CONFIG ----------------
const defaultHost = '127.0.0.1';
const defaultPort = 8888;
const certsDir = 'certs';
const rootKeyFile = 'rootCA.key';
const rootCertFile = 'rootCA.pem';
const rulesFilePath = 'rules.json';

// ---------------- Rule Model & Persistence ----------------
class MatchSpec {
  final String host; // supports wildcard *.example.com or '*'
  final String pathRegex; // regex string, '' => match any
  final String method; // GET|POST|* (case-insensitive)
  final int? status; // optional: match original response status

  MatchSpec({
    this.host = '*',
    this.pathRegex = '',
    this.method = '*',
    this.status,
  });

  factory MatchSpec.fromJson(Map<String, dynamic> j) => MatchSpec(
        host: j['host'] ?? '*',
        pathRegex: j['path_regex'] ?? '',
        method: j['method'] ?? '*',
        status: j.containsKey('status') ? (j['status'] is int ? j['status'] : int.tryParse(j['status'].toString())) : null,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'path_regex': pathRegex,
        'method': method,
        if (status != null) 'status': status,
      };
}

class ActionSpec {
  final int? status; // rewrite status
  final String? body; // replacement body
  final Map<String, String>? headers; // header replacements/additions

  ActionSpec({this.status, this.body, this.headers});

  factory ActionSpec.fromJson(Map<String, dynamic> j) => ActionSpec(
        status: j['status'] != null ? (j['status'] is int ? j['status'] : int.tryParse(j['status'].toString())) : null,
        body: j['body'],
        headers: j['headers'] != null ? Map<String, String>.from(j['headers']) : null,
      );

  Map<String, dynamic> toJson() => {
        if (status != null) 'status': status,
        if (body != null) 'body': body,
        if (headers != null) 'headers': headers,
      };
}

class RewriteRule {
  final String id;
  final MatchSpec match;
  final ActionSpec actions;
  bool enabled;

  RewriteRule({
    required this.id,
    required this.match,
    required this.actions,
    this.enabled = true,
  });

  factory RewriteRule.fromJson(Map<String, dynamic> j) => RewriteRule(
        id: j['id'],
        match: MatchSpec.fromJson(Map<String, dynamic>.from(j['match'])),
        actions: ActionSpec.fromJson(Map<String, dynamic>.from(j['actions'])),
        enabled: j['enabled'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'match': match.toJson(),
        'actions': actions.toJson(),
        'enabled': enabled,
      };
}

class RuleStore {
  final File file;
  RuleStore(String path) : file = File(path);

  Future<List<RewriteRule>> load() async {
    try {
      if (!await file.exists()) return [];
      final txt = await file.readAsString();
      if (txt.trim().isEmpty) return [];
      final arr = jsonDecode(txt) as List<dynamic>;
      return arr.map((e) => RewriteRule.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      stderr.writeln('Failed to load rules: $e');
      return [];
    }
  }

  Future<void> save(List<RewriteRule> rules) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(rules.map((r) => r.toJson()).toList()));
    await tmp.rename(file.path);
  }
}

// ---------------- Cert generation (openssl) with concurrency guard ----------------
final _inProgress = <String, Future<_CertFiles>>{};

class _CertFiles {
  final String crtFile;
  final String keyFile;
  final String combinedPem;
  _CertFiles(this.crtFile, this.keyFile, this.combinedPem);
}

Future<_CertFiles> ensureLeafCertForHost(String host, {required String certsDirPath, String rootKey = rootKeyFile, String rootCert = rootCertFile, Duration timeout = const Duration(seconds: 20)}) {
  // safe file name
  final safeHost = host.replaceAll(RegExp(r'[^A-Za-z0-9\.\-_]'), '_');
  if (_inProgress.containsKey(safeHost)) return _inProgress[safeHost]!;
  final future = _generateOrGetCached(safeHost, certsDirPath, rootKey, rootCert, timeout);
  _inProgress[safeHost] = future;
  future.whenComplete(() => _inProgress.remove(safeHost));
  return future;
}

Future<_CertFiles> _generateOrGetCached(String safeHost, String certsDirPath, String rootKey, String rootCert, Duration timeout) async {
  final crtFile = p.join(certsDirPath, '$safeHost.crt.pem');
  final keyFile = p.join(certsDirPath, '$safeHost.key.pem');
  final combined = p.join(certsDirPath, '$safeHost.pem');

  if (File(crtFile).existsSync() && File(keyFile).existsSync()) {
    return _CertFiles(crtFile, keyFile, combined);
  }

  // ensure dir exists
  Directory(certsDirPath).createSync(recursive: true);

  final csrFile = p.join(certsDirPath, '$safeHost.csr.pem');
  final extFile = p.join(certsDirPath, '$safeHost.ext');

  final isIp = _isIpAddress(safeHost);
  final sanLine = isIp ? 'subjectAltName = IP:$safeHost' : 'subjectAltName = DNS:$safeHost';
  final extContent = '''
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectKeyIdentifier = hash
$sanLine
''';
  File(extFile).writeAsStringSync(extContent, flush: true);

  // 1) gen key
  var res = await _runOpenSsl(['genrsa', '-out', keyFile, '2048'], timeout);
  if (res.exitCode != 0) {
    throw Exception('openssl genrsa failed for $safeHost: ${res.stderr}');
  }

  // 2) csr
  final subj = '/CN=$safeHost';
  res = await _runOpenSsl(['req', '-new', '-key', keyFile, '-out', csrFile, '-subj', subj], timeout);
  if (res.exitCode != 0) {
    throw Exception('openssl req failed for $safeHost: ${res.stderr}');
  }

  // 3) sign
  res = await _runOpenSsl([
    'x509',
    '-req',
    '-in',
    csrFile,
    '-CA',
    p.join(certsDirPath, rootCert),
    '-CAkey',
    p.join(certsDirPath, rootKey),
    '-CAcreateserial',
    '-out',
    crtFile,
    '-days',
    '365',
    '-sha256',
    '-extfile',
    extFile
  ], timeout);

  if (res.exitCode != 0) {
    throw Exception('openssl x509 sign failed for $safeHost: ${res.stderr}');
  }

  // combine
  final keyBytes = await File(keyFile).readAsBytes();
  final crtBytes = await File(crtFile).readAsBytes();
  await File(combined).writeAsBytes([...keyBytes, ...crtBytes], flush: true);

  // cleanup csr
  try {
    File(csrFile).deleteSync();
  } catch (_) {}

  print('Generated cert for $safeHost -> $crtFile');
  return _CertFiles(crtFile, keyFile, combined);
}

Future<ProcessResult> _runOpenSsl(List<String> args, Duration timeout) async {
  try {
    final pr = await Process.run('openssl', args, runInShell: true).timeout(timeout);
    return pr;
  } on TimeoutException {
    throw Exception('openssl call timed out: openssl ${args.join(' ')}');
  } on ProcessException catch (e) {
    throw Exception('Failed to run openssl: ${e.message}');
  }
}

bool _isIpAddress(String host) {
  final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  final ipv6 = RegExp(r'^[0-9a-fA-F:]+$');
  return ipv4.hasMatch(host) || ipv6.hasMatch(host);
}

// ---------------- Simple HTTP helpers (naive parser) ----------------
class HttpMessage {
  final String startLine;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  HttpMessage({required this.startLine, required this.headers, required this.bodyBytes});
}

HttpMessage? tryParseHttpMessage(List<int> buffer) {
  // Attempt to parse headers by looking for \r\n\r\n
  final s = utf8.decode(buffer, allowMalformed: true);
  final idx = s.indexOf('\r\n\r\n');
  if (idx < 0) return null;
  final headPart = s.substring(0, idx);
  final lines = headPart.split('\r\n');
  if (lines.isEmpty) return null;
  final startLine = lines[0];
  final headers = <String, String>{};
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    final pidx = line.indexOf(':');
    if (pidx > 0) {
      final k = line.substring(0, pidx).trim();
      final v = line.substring(pidx + 1).trim();
      headers[k.toLowerCase()] = v;
    }
  }
  // Determine how many bytes the header actually consumed
  final headerBytes = utf8.encode(s.substring(0, idx + 4));
  final bodyBytes = buffer.sublist(headerBytes.length);
  // For simplicity: if Content-Length present, ensure full body is available
  if (headers.containsKey('content-length')) {
    final cl = int.tryParse(headers['content-length'] ?? '');
    if (cl != null && bodyBytes.length < cl) return null; // wait for more
    // If there are more than cl bytes, trim extras (leave extras for next message)
    final realBody = bodyBytes.length >= cl! ? bodyBytes.sublist(0, cl) : Uint8List(0);
    return HttpMessage(startLine: startLine, headers: headers, bodyBytes: realBody);
  } else if (headers['transfer-encoding']?.toLowerCase() == 'chunked') {
    // naive: if chunked, try to find terminating chunk "0\r\n\r\n"
    final bodyStr = utf8.decode(bodyBytes, allowMalformed: true);
    if (!bodyStr.contains('\r\n0\r\n\r\n')) return null;
    return HttpMessage(startLine: startLine, headers: headers, bodyBytes: bodyBytes);
  } else {
    // No content-length and not chunked -> assume no body
    return HttpMessage(startLine: startLine, headers: headers, bodyBytes: []);
  }
}

// ---------------- Rule matching & application ----------------
bool _hostMatches(String pattern, String host) {
  if (pattern == '*' || pattern.isEmpty) return true;
  if (pattern.startsWith('*.')) {
    final p = pattern.substring(2);
    return host == p || host.endsWith('.' + p);
  }
  return host == pattern;
}

RewriteRule? findMatchingRule(List<RewriteRule> rules, {
  required String host,
  required String path,
  required String method,
  required int originalStatus,
}) {
  for (final rule in rules) {
    if (!rule.enabled) continue;
    if (!_hostMatches(rule.match.host, host)) continue;
    if (rule.match.method != '*' && rule.match.method.toUpperCase() != method.toUpperCase()) continue;
    if (rule.match.pathRegex.isNotEmpty) {
      final re = RegExp(rule.match.pathRegex);
      if (!re.hasMatch(path)) continue;
    }
    if (rule.match.status != null && rule.match.status != originalStatus) continue;
    return rule;
  }
  return null;
}

MapEntry<int, List<int>> applyRuleToResponse(RewriteRule rule, int originalStatus, List<int> originalBody, Map<String, String> responseHeaders) {
  final newStatus = rule.actions.status ?? originalStatus;
  final newBodyBytes = rule.actions.body != null ? utf8.encode(rule.actions.body!) : originalBody;
  final newHeaders = {...responseHeaders};
  if (rule.actions.headers != null) {
    newHeaders.addAll(rule.actions.headers!);
  }
  // Update content-length
  newHeaders['content-length'] = newBodyBytes.length.toString();
  // Note: we do not support chunked rewriting here; we rewrite as single payload.
  return MapEntry(newStatus, newBodyBytes);
}

// ---------------- Proxy core ----------------
late RuleStore _ruleStore;
List<RewriteRule> _activeRules = [];
StreamSubscription<FileSystemEvent>? _rulesWatcherSub;

Future<void> _loadRulesAndWatch() async {
  _activeRules = await _ruleStore.load();
  // watch file for changes
  try {
    _rulesWatcherSub?.cancel();
    _rulesWatcherSub = File(rulesFilePath).watch().listen((event) async {
      // debounce simple
      await Future.delayed(const Duration(milliseconds: 200));
      _activeRules = await _ruleStore.load();
      print('Rules reloaded (${_activeRules.length})');
    });
  } catch (e) {
    // ignore if cannot watch
  }
}

Future<void> startProxy(String host, int port) async {
  if (!Directory(certsDir).existsSync()) {
    stderr.writeln('certs dir "$certsDir" missing. Create it and put rootCA.key & rootCA.pem.');
    exit(2);
  }
  print('Starting proxy on $host:$port ...');
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
  // Read until header end to identify CONNECT or normal HTTP
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
    // CONNECT flow -> MITM
    final parts = firstLine.split(' ');
    if (parts.length < 2) {
      client.destroy();
      return;
    }
    final hostPort = parts[1];
    final hp = hostPort.split(':');
    final host = hp[0];
    final port = hp.length > 1 ? int.tryParse(hp[1]) ?? 443 : 443;
    print('[CONNECT] $host:$port');

    // respond 200
    client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    await client.flush();

    // perform server-side TLS handshake with generated cert
    _performMitm(client, host, port);
  } else {
    // Plain HTTP request: forward to upstream, parse response and apply rewrite if any
    // We'll parse request headers to get Host header and full request bytes
    final msg = tryParseHttpMessage(initialBuffer);
    if (msg == null) {
      // Could not parse — just close
      client.destroy();
      return;
    }
    final hostHeader = msg.headers['host'];
    if (hostHeader == null) { client.destroy(); return; }
    final host = hostHeader.split(':').first;
    final port = hostHeader.contains(':') ? int.tryParse(hostHeader.split(':').last) ?? 80 : 80;
    // Connect upstream
    Socket upstream;
    try {
      upstream = await Socket.connect(host, port);
    } catch (e) {
      stderr.writeln('Failed connect to upstream $host:$port : $e');
      client.destroy();
      return;
    }

    // forward request (we already have the initialBuffer)
    upstream.add(initialBuffer);
    // collect response fully (naive)
    final respBuffer = <int>[];
    await upstream.listen((d) { respBuffer.addAll(d); }, onDone: () async {
      // parse response
      final respMsg = tryParseHttpMessage(respBuffer);
      if (respMsg == null) {
        // forward raw
        client.add(respBuffer);
        client.destroy();
        upstream.destroy();
        return;
      }

      // Parse status code from start line (e.g. HTTP/1.1 200 OK)
      final statusCode = _parseStatusCodeInt(respMsg.startLine) ?? 200;
      final path = _extractPathFromRequestStartLine(msg.startLine);
      final method = _extractMethodFromRequestStartLine(msg.startLine);
      final rule = findMatchingRule(_activeRules, host: host, path: path, method: method, originalStatus: statusCode);
      if (rule != null) {
        // apply rule
        final currentHeaders = Map<String, String>.from(respMsg.headers);
        final applied = applyRuleToResponse(rule, statusCode, respMsg.bodyBytes, currentHeaders);
        final newStatus = applied.key;
        final newBodyBytes = applied.value;
        // build response
        final sb = StringBuffer();
        sb.writeln('HTTP/1.1 $newStatus ${_statusReason(newStatus)}');
        currentHeaders.forEach((k, v) {
          sb.writeln('${_canonicalHeaderName(k)}: $v');
        });
        sb.writeln();
        client.add(utf8.encode(sb.toString()));
        client.add(newBodyBytes);
      } else {
        // pass-through
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

String? _parseStatusCode(String statusLine) {
  final parts = statusLine.split(' ');
  if (parts.length >= 2) {
    return int.tryParse(parts[1])?.toString();
  }
  return null;
}

int? _parseStatusCodeInt(String statusLine) {
  final parts = statusLine.split(' ');
  if (parts.length >= 2) return int.tryParse(parts[1]);
  return null;
}

String _statusReason(int status) {
  // minimal mapping
  final map = {
    200: 'OK',
    201: 'Created',
    302: 'Found',
    400: 'Bad Request',
    401: 'Unauthorized',
    403: 'Forbidden',
    404: 'Not Found',
    500: 'Internal Server Error'
  };
  return map[status] ?? '';
}

String _extractPathFromRequestStartLine(String startLine) {
  // e.g. GET /path HTTP/1.1
  final parts = startLine.split(' ');
  if (parts.length >= 2) {
    final uri = parts[1];
    try {
      final u = Uri.parse(uri);
      return u.path;
    } catch (_) {
      return uri;
    }
  }
  return '/';
}

String _extractMethodFromRequestStartLine(String startLine) {
  final parts = startLine.split(' ');
  if (parts.isNotEmpty) return parts[0];
  return 'GET';
}

String _canonicalHeaderName(String key) {
  // naive: capitalize first letter and after hyphen
  return key.split('-').map((p) => p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1))).join('-');
}

// ---------------- MITM: wrap client into SecureSocket using generated leaf cert ----------------
Future<void> _performMitm(Socket clientPlain, String host, int port) async {
  // generate cert files for host
  _CertFiles files;
  try {
    files = await ensureLeafCertForHost(host, certsDirPath: certsDir);
  } catch (e, st) {
    stderr.writeln('Cert gen failed for $host: $e\n$st');
    clientPlain.destroy();
    return;
  }

  // prepare SecurityContext for server-side handshake (present leaf cert to client)
  final ctx = SecurityContext(withTrustedRoots: false);
  try {
    ctx.useCertificateChain(files.crtFile);
    ctx.usePrivateKey(files.keyFile);
  } catch (e) {
    stderr.writeln('Failed to load cert/key into SecurityContext for $host: $e');
    clientPlain.destroy();
    return;
  }

  SecureSocket clientTls;
  try {
    clientTls = await SecureSocket.secure(
      clientPlain,
      context: ctx,
    );
  } catch (e) {
    stderr.writeln('TLS handshake with client failed for $host: $e');
    clientPlain.destroy();
    return;
  }

  // connect to upstream server with TLS
  SecureSocket serverTls;
  try {
    serverTls = await SecureSocket.connect(host, port, timeout: const Duration(seconds: 10));
  } catch (e) {
    stderr.writeln('Failed connect to upstream TLS $host:$port : $e');
    clientTls.destroy();
    return;
  }

  // now we have secure clientTls <-> proxy <-> serverTls
  // For simplicity: we buffer full responses and apply rewrite if matches; request rewriting not implemented here but can be added similarly
  final upstreamBuffer = <int>[];
  final clientToServerSub = clientTls.listen((data) {
    try {
      serverTls.add(data);
    } catch (_) {}
  }, onDone: () {
    try {
      serverTls.close();
    } catch (_) {}
  }, onError: (_) {
    clientTls.destroy();
    serverTls.destroy();
  });

  final serverToClientSub = serverTls.listen((data) {
    upstreamBuffer.addAll(data);
    // naive attempt: if we can parse a full HTTP response, process
    final parsed = tryParseHttpMessage(upstreamBuffer);
    if (parsed != null) {
      // parse status code
      final status = _parseStatusCodeInt(parsed.startLine) ?? 200;
      // we need the original request to know path+method; we don't parse it here because we didn't buffer it.
      // For simplicity in MITM mode, do best-effort: extract path from TLS SNI? Not available.
      // Instead we attempt to parse request line from clientTls? Too late.
      // Simpler: apply rules that match host + status (if match.pathRegex empty or unknown)
      // If you require path-level matches in MITM mode, you must buffer request and extract path before forwarding.
      final path = '/';
      final method = 'GET';
      final rule = findMatchingRule(_activeRules, host: host, path: path, method: method, originalStatus: status);
      if (rule != null) {
        final respHeaders = Map<String, String>.from(parsed.headers);
        final applied = applyRuleToResponse(rule, status, parsed.bodyBytes, respHeaders);
        final newStatus = applied.key;
        final newBody = applied.value;
        final sb = StringBuffer();
        sb.writeln('HTTP/1.1 $newStatus ${_statusReason(newStatus)}');
        respHeaders.forEach((k, v) {
          sb.writeln('${_canonicalHeaderName(k)}: $v');
        });
        sb.writeln();
        final headerBytes = utf8.encode(sb.toString());
        clientTls.add(headerBytes);
        clientTls.add(newBody);
      } else {
        clientTls.add(upstreamBuffer);
      }
      upstreamBuffer.clear();
    } else {
      // no full response yet; wait
    }
  }, onDone: () {
    clientTls.destroy();
    serverTls.destroy();
  }, onError: (e) {
    stderr.writeln('serverTls listen error: $e');
    clientTls.destroy();
    serverTls.destroy();
  });

  // keep subscriptions alive
  await Future.any([
    clientToServerSub.asFuture().catchError((_) {}),
    serverToClientSub.asFuture().catchError((_) {}),
  ]);
}

// ---------------- CLI wiring ----------------
String _genId() => '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(100000)}';

Future<void> main(List<String> argv) async {
  _ruleStore = RuleStore(rulesFilePath);
  await _loadRulesAndWatch();

  final parser = ArgParser()
    ..addFlag('help', negatable: false, help: 'Show help');

  final start = parser.addCommand('start');
  start.addOption('port', defaultsTo: '$defaultPort', help: 'Port to listen on');
  start.addOption('host', defaultsTo: defaultHost, help: 'Host to bind');

  final genCert = parser.addCommand('gen-cert');
  genCert.addFlag('force', negatable: false, help: 'Force regen');

  final rewrite = parser.addCommand('rewrite');
  final rewriteAdd = rewrite.addCommand('add');
  rewriteAdd.addOption('match-host', abbr: 'h', help: 'Host pattern (e.g. example.com or *.example.com)', defaultsTo: '*');
  rewriteAdd.addOption('match-path', help: 'Path regex (e.g. ^/api/)', defaultsTo: '');
  rewriteAdd.addOption('match-method', abbr: 'm', help: 'HTTP method (GET/POST/*)', defaultsTo: '*');
  rewriteAdd.addOption('match-status', abbr: 's', help: 'Original response status to match (e.g. 200)');
  rewriteAdd.addOption('status', abbr: 'c', help: 'Status code to rewrite to (e.g. 401)');
  rewriteAdd.addOption('body', abbr: 'b', help: 'Body replacement (string or @file)');
  rewriteAdd.addMultiOption('header', help: 'Header replacement Name:Value', splitCommas: false);

  rewrite.addCommand('list');
  final rm = rewrite.addCommand('rm');
  rm.addOption('id', abbr: 'i', help: 'Rule id');

  final en = rewrite.addCommand('enable'); en.addOption('id', abbr: 'i', help: 'Rule id');
  final dis = rewrite.addCommand('disable'); dis.addOption('id', abbr: 'i', help: 'Rule id');

  ArgResults results;
  try {
    results = parser.parse(argv);
  } catch (e) {
    print('Invalid args: $e\n');
    _printHelp();
    exit(64);
  }

  if (results['help'] == true) { _printHelp(); return; }
  final cmd = results.command;
  if (cmd == null) { _printHelp(); return; }

  switch (cmd.name) {
    case 'start':
      final port = int.tryParse(cmd['port'] as String) ?? defaultPort;
      final host = cmd['host'] as String? ?? defaultHost;
      await startProxy(host, port);
      break;

    case 'gen-cert':
      await _handleGenCert(cmd.rest, force: cmd['force'] as bool);
      break;

    case 'rewrite':
      final sub = cmd.command;
      if (sub == null) { print('rewrite needs a subcommand'); _printRewriteHelp(); return; }
      switch (sub.name) {
        case 'add':
          await _cmdRewriteAdd(sub);
          break;
        case 'list':
          await _cmdRewriteList();
          break;
        case 'rm':
          await _cmdRewriteRm(sub['id'] as String?);
          break;
        case 'enable':
          await _cmdToggleRule(sub['id'] as String?, true);
          break;
        case 'disable':
          await _cmdToggleRule(sub['id'] as String?, false);
          break;
        default:
          _printRewriteHelp();
      }
      break;

    default:
      _printHelp();
  }
}

void _printHelp() {
  print('mini_mitm - simple MITM proxy (pure-dart prototype)');
  print('');
  print('Usage: mini_mitm <command> [options]');
  print('');
  print('Commands:');
  print('  start           Start proxy (e.g. start -p 8888)');
  print('  gen-cert        Generate leaf cert for a host (args: host)');
  print('  rewrite add     Add a rewrite rule');
  print('  rewrite list    List rules');
  print('  rewrite rm      Remove rule');
  print('');
  print('Examples:');
  print('  dart run bin/mini_mitm_proxy.dart start -p 8888');
  print('  dart run bin/mini_mitm_proxy.dart gen-cert example.com');
  print('  dart run bin/mini_mitm_proxy.dart rewrite add --match-host example.com --match-path "^/api" --match-status 200 --status 401 --body "Hello"');
}

void _printRewriteHelp() {
  print('rewrite commands: add / list / rm / enable / disable');
}

// ---------------- CLI handlers for cert & rules ----------------
Future<void> _handleGenCert(List<String> rest, {bool force = false}) async {
  if (rest.isEmpty) {
    print('gen-cert requires host argument');
    return;
  }
  final host = rest[0];
  final safeHost = host.replaceAll(RegExp(r'[^A-Za-z0-9\.\-_]'), '_');
  final crtFile = p.join(certsDir, '$safeHost.crt.pem');
  final keyFile = p.join(certsDir, '$safeHost.key.pem');
  if (!Directory(certsDir).existsSync()) Directory(certsDir).createSync(recursive: true);
  if (!File(p.join(certsDir, rootKeyFile)).existsSync() || !File(p.join(certsDir, rootCertFile)).existsSync()) {
    stderr.writeln('Missing root CA files in $certsDir. Please add $rootKeyFile and $rootCertFile.');
    return;
  }
  if (File(crtFile).existsSync() && File(keyFile).existsSync() && !force) {
    print('Cert exists for $host: $crtFile');
    return;
  }
  try {
    final files = await ensureLeafCertForHost(host, certsDirPath: certsDir);
    print('Generated: ${files.crtFile} + ${files.keyFile}');
  } catch (e) {
    stderr.writeln('Generation failed: $e');
  }
}

Future<void> _cmdRewriteAdd(ArgResults args) async {
  final host = args['match-host'] as String? ?? '*';
  final path = args['match-path'] as String? ?? '';
  final method = (args['match-method'] as String? ?? '*').toUpperCase();
  final matchStatusStr = args['match-status'] as String?;
  final matchStatus = matchStatusStr != null ? int.tryParse(matchStatusStr) : null;
  final statusStr = args['status'] as String?;
  final status = statusStr != null ? int.tryParse(statusStr) : null;
  var body = args['body'] as String?;
  if (body != null && body.startsWith('@')) {
    final filePath = body.substring(1);
    try {
      body = await File(filePath).readAsString();
    } catch (e) {
      stderr.writeln('Failed to read body file $filePath: $e');
      return;
    }
  }
  final headerList = args['header'] as List<String>? ?? [];
  final headers = <String, String>{};
  for (final h in headerList) {
    final idx = h.indexOf(':');
    if (idx > 0) {
      headers[h.substring(0, idx).trim().toLowerCase()] = h.substring(idx + 1).trim();
    }
  }

  final rules = await _ruleStore.load();
  final id = _genId();
  final rule = RewriteRule(
    id: id,
    match: MatchSpec(host: host, pathRegex: path, method: method, status: matchStatus),
    actions: ActionSpec(status: status, body: body, headers: headers.isEmpty ? null : headers),
    enabled: true,
  );
  rules.add(rule);
  await _ruleStore.save(rules);
  _activeRules = rules;
  print('Added rule id=$id');
}

Future<void> _cmdRewriteList() async {
  final rules = await _ruleStore.load();
  if (rules.isEmpty) { print('No rules'); return; }
  for (final r in rules) {
    print('${r.id} ${r.enabled ? '[ENABLED]' : '[DISABLED]'}');
    print('  match: host=${r.match.host} path=${r.match.pathRegex} method=${r.match.method} status=${r.match.status}');
    print('  actions: status=${r.actions.status} body=${r.actions.body != null ? "<present>" : "null"} headers=${r.actions.headers}');
  }
}

Future<void> _cmdRewriteRm(String? id) async {
  if (id == null) { print('rm requires -i id'); return; }
  final rules = await _ruleStore.load();
  final before = rules.length;
  rules.removeWhere((r) => r.id == id);
  await _ruleStore.save(rules);
  _activeRules = rules;
  print('Removed $before -> ${rules.length}');
}

Future<void> _cmdToggleRule(String? id, bool enable) async {
  if (id == null) { print('${enable ? "enable" : "disable"} requires -i id'); return; }
  final rules = await _ruleStore.load();
  final idx = rules.indexWhere((x) => x.id == id);
  if (idx < 0) { print('No such rule $id'); return; }
  rules[idx].enabled = enable;
  await _ruleStore.save(rules);
  _activeRules = rules;
  print('${enable ? "Enabled" : "Disabled"} $id');
}
