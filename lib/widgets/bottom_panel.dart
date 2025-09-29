import 'package:flutter/material.dart';

import '../models/http_entry.dart';
import 'package:multi_split_view/multi_split_view.dart';

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
  double firstColumnWidth = 200;
  late final double _windowWidth = MediaQuery.of(context).size.width;

  @override
  Widget build(BuildContext context) {
    return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  child: Text('Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                IconButton(onPressed: widget.onCollapse, icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(color: Colors.white10, height: 1,),
            Expanded(
              child: Row(
                  children: [
                    SizedBox(
                      width: firstColumnWidth,
                      child: RequestPanel(entry: widget.entry),
                    ),
                    // Drag handle
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            firstColumnWidth =
                                (firstColumnWidth + details.delta.dx).clamp(
                                  0,
                                  _windowWidth,
                                );
                          });
                        },
                        child: SizedBox(
                          width: 6, // hit area width
                          child: Center(
                            child: Container(
                              width: 0.5, // visible line width
                              color: const Color.fromARGB(255, 94, 93, 93), // visible line color
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Second column
                    Expanded(
                      child: ResponsePanel(entry: widget.entry),
                    ),
                  ],
                ),
            ),
          ],
        );
  }
}
