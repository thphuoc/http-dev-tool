// Central configuration for the MITM proxy

class Config {
  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 8888;

  static const String certsDir = '.';
  static const String leafCertsDir = './certs';
  static const String rootKeyFile = './rootCA.key';
  static const String rootCertFile = './rootCA.crt';
  static const String CER_COUNTRY = 'VN';
  static const String CER_STATE = 'HCM';
  static const String CER_LOCATION = 'HCM';
  static const String CER_ORGANIZATION = 'MyProxy';
  static const String CER_COMMON_NAME = 'rootCA';

  static const String rulesFilePath = 'rules.json';
}


