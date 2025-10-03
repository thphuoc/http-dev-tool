import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

import 'cert_manager.dart';
import 'config.dart';
import 'mitm_handler.dart';
import 'proxy_server.dart';

Future<void> mitmMain(List<String> argv) async {
  final parser = ArgParser()
    ..addFlag('help', negatable: false, help: 'Show help');

  final start = parser.addCommand('start');
  start.addOption('port', defaultsTo: '${Config.defaultPort}', help: 'Port to listen on');
  start.addOption('host', defaultsTo: Config.defaultHost, help: 'Host to bind');

  final genCert = parser.addCommand('gen-cert');
  genCert.addFlag('force', negatable: false, help: 'Force regen');

  // Generate root CA .crt from existing rootCA.pem
  final genRootCrt = parser.addCommand('gen-root-crt');
  genRootCrt.addOption('out', help: 'Output .crt path', defaultsTo: '${Config.certsDir}/rootCA.crt');
  genRootCrt.addOption('host', help: 'Proxy host for guidance URL');
  genRootCrt.addOption('port', help: 'Proxy port for guidance URL');

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

  final certManager = CertManager();
  late final ProxyServer proxy;
  final mitmHandler = MitmHandler(
    certManager: certManager,
    getActiveRules: () => proxy.getActiveRules(),
  );
  proxy = ProxyServer(mitmHandler: mitmHandler);

  switch (cmd.name) {
    case 'start':
      final port = int.tryParse(cmd['port'] as String) ?? Config.defaultPort;
      final host = cmd['host'] as String? ?? Config.defaultHost;
      await proxy.startProxy(host, port);
      break;
    case 'gen-cert':
      await _handleGenCert(cmd.rest, force: cmd['force'] as bool, certManager: certManager);
      break;
    case 'gen-root-crt':
      await _handleGenRootCrt(
        outPath: cmd['out'] as String,
        host: cmd['host'] as String?,
        port: cmd['port'] != null ? int.tryParse(cmd['port'] as String) : null,
      );
      break;
    case 'rewrite':
      final sub = cmd.command;
      if (sub == null) { print('rewrite needs a subcommand'); _printRewriteHelp(); return; }
      switch (sub.name) {
        case 'add':
          await _cmdRewriteAdd(sub, proxy);
          break;
        case 'list':
          await proxy.listRules();
          break;
        case 'rm':
          await proxy.removeRule(sub['id'] as String);
          break;
        case 'enable':
          await proxy.toggleRule(sub['id'] as String, true);
          break;
        case 'disable':
          await proxy.toggleRule(sub['id'] as String, false);
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
  print('mini_mitm - simple MITM proxy (modularized)');
  print('');
  print('Usage: mini_mitm <command> [options]');
  print('');
  print('Commands:');
  print('  start           Start proxy (e.g. start -p 8888)');
  print('  gen-cert        Generate leaf cert for a host (args: host)');
  print('  gen-root-crt    Convert rootCA.pem to rootCA.crt and show guidance');
  print('  rewrite add     Add a rewrite rule');
  print('  rewrite list    List rules');
  print('  rewrite rm      Remove rule');
}

void _printRewriteHelp() {
  print('rewrite commands: add / list / rm / enable / disable');
}

Future<void> _handleGenCert(List<String> rest, {bool force = false, required CertManager certManager}) async {
  if (rest.isEmpty) {
    print('gen-cert requires host argument');
    return;
  }
  final host = rest[0];
  final safeHost = host.replaceAll(RegExp(r'[^A-Za-z0-9\.\-_]'), '_');
  final crtFile = '${Config.certsDir}/$safeHost.crt.pem';
  final keyFile = '${Config.certsDir}/$safeHost.key.pem';
  if (!Directory(Config.certsDir).existsSync()) Directory(Config.certsDir).createSync(recursive: true);
  if (!File('${Config.certsDir}/${Config.rootKeyFile}').existsSync() || !File('${Config.certsDir}/${Config.rootCertFile}').existsSync()) {
    stderr.writeln('Missing root CA files in ${Config.certsDir}. Please add ${Config.rootKeyFile} and ${Config.rootCertFile}.');
    return;
  }
  if (File(crtFile).existsSync() && File(keyFile).existsSync() && !force) {
    print('Cert exists for $host: $crtFile');
    return;
  }
  try {
    final files = await certManager.ensureLeafCertForHost(host);
    print('Generated: ${files.crtFile} + ${files.keyFile}');
  } catch (e) {
    stderr.writeln('Generation failed: $e');
  }
}

Future<void> _cmdRewriteAdd(ArgResults args, ProxyServer proxy) async {
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

  await proxy.addRule(host: host, path: path, method: method, matchStatus: matchStatus, status: status, body: body, headers: headers.isEmpty ? null : headers);
}

Future<void> _handleGenRootCrt({required String outPath, String? host, int? port}) async {
  final pemPath = '${Config.certsDir}/${Config.rootCertFile}';
  final pemFile = File(pemPath);
  if (!await pemFile.exists()) {
    stderr.writeln('Missing ${Config.rootCertFile} in ${Config.certsDir}.');
    return;
  }
  try {
    // Prefer DER .crt for better OS compatibility
    final res = await Process.run('openssl', ['x509', '-outform', 'der', '-in', pemPath, '-out', outPath], runInShell: true);
    if (res.exitCode != 0) {
      stderr.writeln('Failed to generate .crt: ${res.stderr}');
      return;
    }
  } catch (e) {
    stderr.writeln('Failed to run openssl: $e');
    return;
  }

  print('Generated root CA CRT: $outPath');
  final url = (host != null && port != null) ? 'http://$host:$port/cert' : null;
  if (url != null) {
    print('You can also download via: $url');
  }
  print('How to trust this certificate:');
  print('- Windows: Double-click .crt -> Install Certificate -> Local Machine -> Trusted Root Certification Authorities.');
  print('- macOS: Keychain Access -> System -> Certificates -> Import .crt, set Trust to Always.');
  print('- iOS: AirDrop/email .crt -> Settings -> Profile Downloaded -> Install, then Settings -> General -> About -> Certificate Trust Settings -> enable.');
  print('- Android (>=7): Install via MDM or as user CA (some apps may not trust user CAs). For emulator: place in system store.');
  print('- Linux: For system-wide trust, add to /usr/local/share/ca-certificates and run update-ca-certificates (Debian/Ubuntu).');
}


