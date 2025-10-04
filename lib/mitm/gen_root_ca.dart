import 'dart:io';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart';

/// Lấy IPv4 local (bỏ loopback). Trả về null nếu không tìm thấy.
Future<String?> getLocalIPv4() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );

  for (final iface in interfaces) {
    for (final addr in iface.addresses) {
      if (!addr.isLoopback && addr.address.isNotEmpty) {
        return addr.address;
      }
    }
  }
  return null;
}

/// Tạo file cấu hình OpenSSL (CN + SAN IP + localhost) và extension v3_ca
String buildOpenSSLConfig(String commonName, String ip) {
  return '''
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[ req_distinguished_name ]
C = VN
ST = HCM
L = HCM
O = MyProxy
OU = ProxyTeam
CN = $commonName

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
subjectAltName = @alt_names

[ alt_names ]
IP.1 = $ip
DNS.1 = localhost
''';
}

/// Thực thi command và trả ProcessResult
Future<ProcessResult> runCmd(String executable, List<String> args,
    {String? workingDirectory}) {
  return Process.run(executable, args, workingDirectory: workingDirectory);
}

Future<void> generateRootCAWithSAN() async {
  stdout.writeln('== Generate Root CA with SAN (IP + localhost) ==');

  // 0. Kiểm tra openssl có trên PATH không
  try {
    final v = await runCmd('openssl', ['version']);
    if (v.exitCode != 0) {
      stderr.writeln('Lỗi: openssl không khả dụng. Hãy cài openssl và đặt vào PATH.');
      stderr.writeln(v.stderr);
      exit(2);
    } else {
      stdout.writeln('Found OpenSSL: ${v.stdout.toString().trim()}');
    }
  } catch (e) {
    stderr.writeln('Lỗi khi gọi openssl: $e');
    exit(2);
  }

  // 1. Lấy IP local
  final ip = await getLocalIPv4();
  if (ip == null) {
    stderr.writeln('Không tìm thấy IPv4 non-loopback. Hãy đảm bảo máy có kết nối mạng.');
    exit(3);
  }
  stdout.writeln('Local IPv4 detected: $ip');

  // 2. Sinh cặp RSA bằng Dart (basic_utils)
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = pair.privateKey as RSAPrivateKey;
  final publicKey = pair.publicKey as RSAPublicKey;

  // 3. Lưu private key ra file (PEM)
  final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
  final keyFile = File('rootCA.key');
  await keyFile.writeAsString(keyPem);
  stdout.writeln('Wrote private key -> ${keyFile.path}');

  // 4. Tạo file cấu hình OpenSSL có SAN và v3_ca
  final commonName = 'My Proxy Root CA';
  final cfgFile = File('rootCA_san.cnf');
  final cfgContent = buildOpenSSLConfig(commonName, ip);
  await cfgFile.writeAsString(cfgContent);
  stdout.writeln('Wrote OpenSSL config -> ${cfgFile.path}');

  // 5. Dùng OpenSSL để tạo self-signed cert có extension v3_ca (đã chứa SAN)
  final crtFilePath = 'rootCA.crt';
  stdout.writeln('Generating self-signed root CA certificate -> $crtFilePath ...');

  // Lệnh openssl: req -x509 -new -key rootCA.key -sha256 -days 3650 -out rootCA.crt -config rootCA_san.cnf -extensions v3_ca
  final res = await runCmd('openssl', [
    'req',
    '-x509',
    '-new',
    '-key',
    keyFile.path,
    '-sha256',
    '-days',
    '3650',
    '-out',
    crtFilePath,
    '-config',
    cfgFile.path,
    '-extensions',
    'v3_ca'
  ]);

  if (res.exitCode != 0) {
    stderr.writeln('Tạo certificate thất bại: ${res.stderr}');
    exit(4);
  }

  stdout.writeln('✅ Created rootCA.crt');

  // 6. In chi tiết cert (tuỳ chọn)
  final detail = await runCmd('openssl', ['x509', '-in', crtFilePath, '-noout', '-text']);
  if (detail.exitCode == 0) {
    stdout.writeln('\n--- Certificate details ---\n${detail.stdout}');
  } else {
    stderr.writeln('Không thể đọc certificate: ${detail.stderr}');
  }

  stdout.writeln('---');
  stdout.writeln('Ghi chú: giữ rootCA.key thật an toàn. Import rootCA.crt vào client để trust.');
}

void main() async {
  await generateRootCAWithSAN();
}
