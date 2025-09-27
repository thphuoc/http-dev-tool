import 'package:flutter/material.dart';
import 'dart:math' as math;

class KeyValueTable extends StatelessWidget {
  final Map<String, String> map;
  const KeyValueTable({required this.map, super.key});

  @override
  Widget build(BuildContext context) {
    final entries = map.entries.toList();
    return Card(
      color: Colors.grey[850],
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Headers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // Use LayoutBuilder to choose a safe height for the list so that
            // the widget adapts when it's placed in very small containers.
            LayoutBuilder(builder: (context, constraints) {
              final maxListHeight = math.max(0.0, constraints.maxHeight - 48.0);
              final listHeight = math.min(140.0, maxListHeight);
              return SizedBox(
                height: listHeight > 0 ? listHeight : 0,
                child: ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                  itemBuilder: (context, i) {
                    final kv = entries[i];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 200, child: Text(kv.key, style: const TextStyle(color: Colors.white70))),
                        Expanded(child: SelectableText(kv.value)),
                      ],
                    );
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
