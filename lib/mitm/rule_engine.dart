import 'dart:convert';

import 'http_message.dart';
import 'models.dart';

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
  newHeaders['content-length'] = newBodyBytes.length.toString();
  return MapEntry(newStatus, newBodyBytes);
}


