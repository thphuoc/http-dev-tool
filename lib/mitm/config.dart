// Central configuration for the MITM proxy

class Config {
  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 8888;

  static const String certsDir = 'certs';
  static const String rootKeyFile = 'rootCA.key';
  static const String rootCertFile = 'rootCA.pem';

  static const String rulesFilePath = 'rules.json';
}


