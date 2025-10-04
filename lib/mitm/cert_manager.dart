import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'config.dart';

class CertFiles {
  final String crtFile;
  final String keyFile;
  final String combinedPem;
  final String fullchainPem;
  CertFiles(this.crtFile, this.keyFile, this.combinedPem, this.fullchainPem);
}

class CertManager {
  final Map<String, Future<CertFiles>> _inProgress = {};

  Future<CertFiles> ensureLeafCertForHost(
    String host, {
    String? certsDirPath,
    String rootKey = Config.rootKeyFile,
    String rootCert = Config.rootCertFile,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final dirPath = certsDirPath ?? Config.leafCertsDir;
    final safeHost = host.replaceAll(RegExp(r'[^A-Za-z0-9\.\-_]'), '_');
    if (_inProgress.containsKey(safeHost)) return _inProgress[safeHost]!;
    final future = _generateOrGetCached(
      safeHost,
      dirPath,
      rootKey,
      rootCert,
      timeout,
    );
    _inProgress[safeHost] = future;
    future.whenComplete(() => _inProgress.remove(safeHost));
    return future;
  }

  // Thay thế phần tương ứng trong CertManager
  Future<CertFiles> _generateOrGetCached(
    String safeHost,
    String certsDirPath,
    String rootKey,
    String rootCert,
    Duration timeout,
  ) async {
    final crtFile = p.join(certsDirPath, '$safeHost.crt');
    final keyFile = p.join(certsDirPath, '$safeHost.key');
    final combined = p.join(
      certsDirPath,
      '$safeHost.pem',
    ); // optional: cert + key
    final fullchain = p.join(
      certsDirPath,
      '$safeHost.fullchain.pem',
    ); // leaf + root

    if (File(crtFile).existsSync() &&
        File(keyFile).existsSync() &&
        File(fullchain).existsSync()) {
      return CertFiles(crtFile, keyFile, combined, fullchain);
    }

    Directory(certsDirPath).createSync(recursive: true);

    final csrFile = p.join(certsDirPath, '$safeHost.csr.pem');
    final extFile = p.join(certsDirPath, '$safeHost.ext');

    final isIp = _isIpAddress(safeHost);
    // Build a proper ext config with v3_req and alt_names
    final extContent = StringBuffer()
      ..writeln('[ v3_req ]')
      ..writeln('subjectAltName = @alt_names')
      ..writeln('basicConstraints = CA:FALSE')
      ..writeln('keyUsage = digitalSignature, keyEncipherment')
      ..writeln('extendedKeyUsage = serverAuth, clientAuth')
      ..writeln('[ alt_names ]');

    if (isIp) {
      // IPv4 or IPv6 -> use IP.1
      extContent.writeln('IP.1 = $safeHost');
    } else {
      // Allow multiple DNS entries if you want (here only DNS.1)
      extContent.writeln('DNS.1 = $safeHost');
    }

    File(extFile).writeAsStringSync(extContent.toString(), flush: true);

    // 1) Generate private key
    var res = await _runOpenSsl(['genrsa', '-out', keyFile, '2048'], timeout);
    if (res.exitCode != 0) {
      throw Exception('openssl genrsa failed for $safeHost: ${res.stderr}');
    }

    // 2) Generate CSR (no SAN inside CSR; we'll add SAN on signing via extfile)
    final subj = '/CN=$safeHost';
    res = await _runOpenSsl([
      'req',
      '-new',
      '-key',
      keyFile,
      '-out',
      csrFile,
      '-subj',
      subj,
    ], timeout);
    if (res.exitCode != 0) {
      throw Exception('openssl req failed for $safeHost: ${res.stderr}');
    }

    // 3) Sign CSR to create certificate and include extensions from extFile
    // Note: use -extensions v3_req to pick the correct section in extFile
    res = await _runOpenSsl([
      'x509',
      '-req',
      '-in',
      csrFile,
      '-CA',
      rootCert,
      '-CAkey',
      rootKey,
      '-CAcreateserial',
      '-out',
      crtFile,
      '-days',
      '365',
      '-sha256',
      '-extfile',
      extFile,
      '-extensions',
      'v3_req',
    ], timeout);

    if (res.exitCode != 0) {
      throw Exception('openssl x509 sign failed for $safeHost: ${res.stderr}');
    }

    // 4) Create fullchain (leaf + root) — useful for useCertificateChain if needed
    final crtBytes = await File(crtFile).readAsBytes();
    final rootBytes = await File(rootCert).readAsBytes();
    await File(
      fullchain,
    ).writeAsBytes([...crtBytes, ...rootBytes], flush: true);

    // 5) Optionally create combined pem (cert then key or key then cert depending on your needs)
    // Many libs expect cert(s) first, then key; we'll write cert then key here:
    final keyBytes = await File(keyFile).readAsBytes();
    await File(combined).writeAsBytes([...crtBytes, ...keyBytes], flush: true);

    // cleanup csr
    try {
      File(csrFile).deleteSync();
    } catch (_) {}

    print('Generated cert for $safeHost -> $crtFile');
    print('Fullchain created: $fullchain');

    return CertFiles(crtFile, keyFile, combined, fullchain);
  }

  Future<ProcessResult> _runOpenSsl(List<String> args, Duration timeout) async {
    try {
      final pr = await Process.run(
        'openssl',
        args,
        runInShell: true,
      ).timeout(timeout);
      return pr;
    } on TimeoutException {
      throw Exception('openssl call timed out: openssl ${args.join(' ')}');
    } on ProcessException catch (e) {
      throw Exception('Failed to run openssl via bash: ${e.message}');
    }
  }
}

bool _isIpAddress(String host) {
  final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  final ipv6 = RegExp(r'^[0-9a-fA-F:]+$');
  return ipv4.hasMatch(host) || ipv6.hasMatch(host);
}
