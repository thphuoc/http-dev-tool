import 'dart:convert';
import 'dart:typed_data';

class HttpMessage {
  final String startLine;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  HttpMessage({required this.startLine, required this.headers, required this.bodyBytes});
}

class HttpParser {
  static HttpMessage? tryParseHttpMessage(List<int> buffer) {
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
    final headerBytes = utf8.encode(s.substring(0, idx + 4));
    final bodyBytes = buffer.sublist(headerBytes.length);
    if (headers.containsKey('content-length')) {
      final cl = int.tryParse(headers['content-length'] ?? '');
      if (cl != null && bodyBytes.length < cl) return null;
      final realBody = bodyBytes.length >= cl! ? bodyBytes.sublist(0, cl) : Uint8List(0);
      return HttpMessage(startLine: startLine, headers: headers, bodyBytes: realBody);
    } else if (headers['transfer-encoding']?.toLowerCase() == 'chunked') {
      final bodyStr = utf8.decode(bodyBytes, allowMalformed: true);
      if (!bodyStr.contains('\r\n0\r\n\r\n')) return null;
      return HttpMessage(startLine: startLine, headers: headers, bodyBytes: bodyBytes);
    } else {
      return HttpMessage(startLine: startLine, headers: headers, bodyBytes: []);
    }
  }

  static String? parseStatusCodeStr(String statusLine) {
    final parts = statusLine.split(' ');
    if (parts.length >= 2) {
      return int.tryParse(parts[1])?.toString();
    }
    return null;
  }

  static int? parseStatusCode(String statusLine) {
    final parts = statusLine.split(' ');
    if (parts.length >= 2) return int.tryParse(parts[1]);
    return null;
  }

  static String extractPathFromRequestStartLine(String startLine) {
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

  static String extractMethodFromRequestStartLine(String startLine) {
    final parts = startLine.split(' ');
    if (parts.isNotEmpty) return parts[0];
    return 'GET';
  }
}

String canonicalHeaderName(String key) {
  return key.split('-').map((p) => p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1))).join('-');
}


