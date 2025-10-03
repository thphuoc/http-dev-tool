import 'dart:convert';
import 'dart:io';

import 'models.dart';

class RuleStore {
  final File file;
  RuleStore(String path) : file = File(path);

  Future<List<RewriteRule>> load() async {
    try {
      if (!await file.exists()) return [];
      final txt = await file.readAsString();
      if (txt.trim().isEmpty) return [];
      final arr = jsonDecode(txt) as List<dynamic>;
      return arr
          .map((e) => RewriteRule.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      stderr.writeln('Failed to load rules: $e');
      return [];
    }
  }

  Future<void> save(List<RewriteRule> rules) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ')
        .convert(rules.map((r) => r.toJson()).toList()));
    await tmp.rename(file.path);
  }
}


