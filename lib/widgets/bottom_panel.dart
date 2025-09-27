import 'package:flutter/material.dart';

import '../models/http_entry.dart';
import 'package:multi_split_view/multi_split_view.dart';

import 'request_panel.dart';
import 'response_panel.dart';

class BottomPanel extends StatelessWidget {
  final HttpEntry entry;
  final VoidCallback onCollapse;

  const BottomPanel({required this.entry, required this.onCollapse, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Card(
        color: Colors.grey[850],
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                IconButton(onPressed: onCollapse, icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: MultiSplitView(
                axis: Axis.horizontal,
                // two equally sized areas by default; user can resize
                initialAreas: [
                  Area(flex: 1, builder: (ctx, area) => RequestPanel(entry: entry)),
                  Area(flex: 1, builder: (ctx, area) => ResponsePanel(entry: entry)),
                ],
                dividerBuilder: (axis, index, resizable, dragging, highlighted, themeData) =>
                    const VerticalDivider(width: 1, thickness: 1, color: Colors.white10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
