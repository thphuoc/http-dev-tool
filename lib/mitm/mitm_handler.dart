import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cert_manager.dart';
import 'http_message.dart';
import 'rule_engine.dart';
import 'models.dart';

class MitmHandler {
  final CertManager certManager;
  final List<RewriteRule> Function() getActiveRules;

  MitmHandler({required this.certManager, required this.getActiveRules});

  Future<void> handle(Socket clientPlain, String host, int port, {List<int>? initialTlsData}) async {
    print('[MITM] Starting TLS handshake for $host:$port');

    CertFiles files;
    try {
      print('[MITM] Generating/loading certificate for $host...');
      files = await certManager.ensureLeafCertForHost(host);
      print('[MITM] Certificate files: crt=${files.crtFile}, key=${files.keyFile}');
    } catch (e, st) {
      stderr.writeln('Cert gen failed for $host: $e\n$st');
      clientPlain.destroy();
      return;
    }

    final ctx = SecurityContext(withTrustedRoots: false);
    try {
      print('[MITM] Loading certificate and key into SecurityContext...');
      // If you produced a fullchain, ensure files.crtFile points to it.
      ctx.useCertificateChain(files.crtFile);
      ctx.usePrivateKey(files.keyFile);
      print('[MITM] SecurityContext loaded successfully');
    } catch (e, st) {
      stderr.writeln('Failed to load cert/key into SecurityContext for $host: $e\n$st');
      clientPlain.destroy();
      return;
    }

    SecureSocket clientTls;
    try {
      print('[MITM] Starting TLS handshake with client (bufferedData length=${initialTlsData?.length ?? 0})...');
      clientTls = await SecureSocket.secureServer(
        clientPlain,
        ctx,
        // pass already-read bytes so handshake can continue
        bufferedData: (initialTlsData == null || initialTlsData.isEmpty) ? null : initialTlsData,
        supportedProtocols: ['tls1.2', 'tls1.3'],
      );
      print('[MITM] TLS handshake with client successful, negotiated=${clientTls.selectedProtocol}');
    } catch (e, st) {
      stderr.writeln('TLS handshake with client failed for $host: $e\n$st');
      stderr.writeln('Certificate file exists: ${File(files.crtFile).existsSync()}');
      stderr.writeln('Key file exists: ${File(files.keyFile).existsSync()}');
      clientPlain.destroy();
      return;
    }

    SecureSocket serverTls;
    try {
      serverTls = await SecureSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      stderr.writeln('Failed connect to upstream TLS $host:$port : $e');
      clientTls.destroy();
      return;
    }

    final upstreamBuffer = <int>[];
    final clientToServerSub = clientTls.listen(
      (data) {
        try {
          serverTls.add(data);
        } catch (_) {}
      },
      onDone: () {
        try {
          serverTls.close();
        } catch (_) {}
      },
      onError: (_) {
        clientTls.destroy();
        serverTls.destroy();
      },
    );

    final serverToClientSub = serverTls.listen(
      (data) {
        upstreamBuffer.addAll(data);
        final parsed = HttpParser.tryParseHttpMessage(upstreamBuffer);
        if (parsed != null) {
          final status = HttpParser.parseStatusCode(parsed.startLine) ?? 200;
          final path = '/';
          final method = 'GET';
          final rule = findMatchingRule(
            getActiveRules(),
            host: host,
            path: path,
            method: method,
            originalStatus: status,
          );
          if (rule != null) {
            final respHeaders = Map<String, String>.from(parsed.headers);
            final applied = applyRuleToResponse(
              rule,
              status,
              parsed.bodyBytes,
              respHeaders,
            );
            final newStatus = applied.key;
            final newBody = applied.value;
            final sb = StringBuffer();
            sb.writeln('HTTP/1.1 $newStatus ');
            respHeaders.forEach((k, v) {
              sb.writeln('${canonicalHeaderName(k)}: $v');
            });
            sb.writeln();
            final headerBytes = utf8.encode(sb.toString());
            clientTls.add(headerBytes);
            clientTls.add(newBody);
          } else {
            clientTls.add(upstreamBuffer);
          }
          upstreamBuffer.clear();
        }
      },
      onDone: () {
        clientTls.destroy();
        serverTls.destroy();
      },
      onError: (e) {
        stderr.writeln('serverTls listen error: $e');
        clientTls.destroy();
        serverTls.destroy();
      },
    );

    await Future.any([
      clientToServerSub.asFuture().catchError((_) {}),
      serverToClientSub.asFuture().catchError((_) {}),
    ]);
  }
}
