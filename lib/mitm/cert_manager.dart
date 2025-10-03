import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'config.dart';

class CertFiles {
  final String crtFile;
  final String keyFile;
  final String combinedPem;
  CertFiles(this.crtFile, this.keyFile, this.combinedPem);
}

class CertManager {
  final Map<String, Future<CertFiles>> _inProgress = {};

  Future<CertFiles> ensureLeafCertForHost(String host, {String? certsDirPath, String rootKey = Config.rootKeyFile, String rootCert = Config.rootCertFile, Duration timeout = const Duration(seconds: 20)}) {
    final dirPath = certsDirPath ?? Config.certsDir;
    final safeHost = host.replaceAll(RegExp(r'[^A-Za-z0-9\.\-_]'), '_');
    if (_inProgress.containsKey(safeHost)) return _inProgress[safeHost]!;
    final future = _generateOrGetCached(safeHost, dirPath, rootKey, rootCert, timeout);
    _inProgress[safeHost] = future;
    future.whenComplete(() => _inProgress.remove(safeHost));
    return future;
  }

  Future<CertFiles> _generateOrGetCached(String safeHost, String certsDirPath, String rootKey, String rootCert, Duration timeout) async {
    final crtFile = p.join(certsDirPath, '$safeHost.crt.pem');
    final keyFile = p.join(certsDirPath, '$safeHost.key.pem');
    final combined = p.join(certsDirPath, '$safeHost.pem');

    if (File(crtFile).existsSync() && File(keyFile).existsSync()) {
      return CertFiles(crtFile, keyFile, combined);
    }

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

    var res = await _runOpenSsl(['genrsa', '-out', keyFile, '2048'], timeout);
    if (res.exitCode != 0) {
      throw Exception('openssl genrsa failed for $safeHost: ${res.stderr}');
    }

    final subj = '/CN=$safeHost';
    res = await _runOpenSsl(['req', '-new', '-key', keyFile, '-out', csrFile, '-subj', subj], timeout);
    if (res.exitCode != 0) {
      throw Exception('openssl req failed for $safeHost: ${res.stderr}');
    }

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

    final keyBytes = await File(keyFile).readAsBytes();
    final crtBytes = await File(crtFile).readAsBytes();
    await File(combined).writeAsBytes([...keyBytes, ...crtBytes], flush: true);

    try {
      File(csrFile).deleteSync();
    } catch (_) {}

    print('Generated cert for $safeHost -> $crtFile');
    return CertFiles(crtFile, keyFile, combined);
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
}

bool _isIpAddress(String host) {
  final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  final ipv6 = RegExp(r'^[0-9a-fA-F:]+$');
  return ipv4.hasMatch(host) || ipv6.hasMatch(host);
}


