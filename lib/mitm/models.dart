import 'dart:convert';

class MatchSpec {
  final String host; // supports wildcard *.example.com or '*'
  final String pathRegex; // regex string, '' => match any
  final String method; // GET|POST|* (case-insensitive)
  final int? status; // optional: match original response status

  MatchSpec({
    this.host = '*',
    this.pathRegex = '',
    this.method = '*',
    this.status,
  });

  factory MatchSpec.fromJson(Map<String, dynamic> j) => MatchSpec(
        host: j['host'] ?? '*',
        pathRegex: j['path_regex'] ?? '',
        method: j['method'] ?? '*',
        status: j.containsKey('status')
            ? (j['status'] is int
                ? j['status']
                : int.tryParse(j['status'].toString()))
            : null,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'path_regex': pathRegex,
        'method': method,
        if (status != null) 'status': status,
      };
}

class ActionSpec {
  final int? status; // rewrite status
  final String? body; // replacement body
  final Map<String, String>? headers; // header replacements/additions

  ActionSpec({this.status, this.body, this.headers});

  factory ActionSpec.fromJson(Map<String, dynamic> j) => ActionSpec(
        status: j['status'] != null
            ? (j['status'] is int
                ? j['status']
                : int.tryParse(j['status'].toString()))
            : null,
        body: j['body'],
        headers: j['headers'] != null
            ? Map<String, String>.from(j['headers'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (status != null) 'status': status,
        if (body != null) 'body': body,
        if (headers != null) 'headers': headers,
      };
}

class RewriteRule {
  final String id;
  final MatchSpec match;
  final ActionSpec actions;
  bool enabled;

  RewriteRule({
    required this.id,
    required this.match,
    required this.actions,
    this.enabled = true,
  });

  factory RewriteRule.fromJson(Map<String, dynamic> j) => RewriteRule(
        id: j['id'],
        match: MatchSpec.fromJson(Map<String, dynamic>.from(j['match'])),
        actions: ActionSpec.fromJson(
            Map<String, dynamic>.from(j['actions'])),
        enabled: j['enabled'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'match': match.toJson(),
        'actions': actions.toJson(),
        'enabled': enabled,
      };
}


