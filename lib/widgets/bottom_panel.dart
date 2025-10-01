import 'package:flutter/material.dart';
import 'package:httpdevtool/widgets/splitter_panel.dart';

import '../models/http_entry.dart';

import 'request_panel.dart';
import 'response_panel.dart';

class BottomPanel extends StatefulWidget {
  final HttpEntry entry;
  final VoidCallback onCollapse;

  const BottomPanel({required this.entry, required this.onCollapse, super.key});

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: Text(
                'Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: widget.onCollapse,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: SplitterPanel(
            firstChild: RequestPanel(entry: widget.entry),
            secondChild: ResponsePanel(entry: widget.entry),
            isVertical: false,
          ),
        ),
      ],
    );
  }
}
