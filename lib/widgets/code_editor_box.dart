import 'package:flutter/material.dart';

class CodeEditorBox extends StatelessWidget {
  final String content;
  const CodeEditorBox({required this.content, super.key});

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    return Card(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(lines.length, (i) => Text('${i + 1}', style: const TextStyle(color: Colors.white38, fontFamily: 'monospace', fontSize: 12))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
