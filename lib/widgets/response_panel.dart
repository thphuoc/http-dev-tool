import 'package:flutter/material.dart';

import '../models/http_entry.dart';
import 'key_value_table.dart';
import 'code_editor_box.dart';

enum ResponseBodyView { json, raw }

class ResponsePanel extends StatefulWidget {
  final HttpEntry entry;
  const ResponsePanel({required this.entry, super.key});

  @override
  State<ResponsePanel> createState() => _ResponsePanelState();
}

class _ResponsePanelState extends State<ResponsePanel> {
  late ResponseBodyView view;

  @override
  void initState() {
    super.initState();
    final body = widget.entry.responseBody.trim();
    if (body.startsWith('{') || body.startsWith('[')) {
      view = ResponseBodyView.json;
    } else {
      view = ResponseBodyView.raw;
    }
  }

  void _setView(ResponseBodyView v) => setState(() => view = v);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: DefaultTabController(
        length: 2,
        child: LayoutBuilder(builder: (context, constraints) {
          // If the available height is very small, avoid using Expanded/TabBarView
          // which can cause RenderFlex overflow. Render a compact scrollable
          // view instead.
          final availableHeight = constraints.maxHeight;
          final compactThreshold = 120.0;

          if (availableHeight.isFinite && availableHeight < compactThreshold) {
            // Compact layout: size the whole area to the available height so the
            // inner Column never overflows. Use Expanded for the scrollable
            // content so the TabBar + Divider take their intrinsic height.
            // Subtract a tiny epsilon to avoid fractional pixel overflows that
            // can occur when TabBar/Divider use fractional heights.
            final safeHeight = (availableHeight - 1.0).clamp(0.0, double.infinity);
            return SizedBox(
              height: safeHeight,
              child: Column(
                children: [
                  // Use a fixed height for the TabBar to avoid fractional pixel
                  // overflows when the available height is very small.
                  SizedBox(
                    height: 36,
                    child: const TabBar(
                      tabs: [Tab(text: 'Headers'), Tab(text: 'Body')],
                      labelPadding: EdgeInsets.symmetric(horizontal: 8),
                      indicatorWeight: 2,
                    ),
                  ),
                  const Divider(color: Colors.white10, thickness: 1),
                  // Fill remaining space with a scrollable view
                  Expanded(
                    child: SingleChildScrollView(
                      child: _compactTabContent(),
                    ),
                  ),
                ],
              ),
            );
          }

          // Normal layout
          return Column(
            children: [
              SizedBox(
                height: 36,
                child: const TabBar(
                  tabs: [Tab(text: 'Headers'), Tab(text: 'Body')],
                  labelPadding: EdgeInsets.symmetric(horizontal: 8),
                  indicatorWeight: 2,
                ),
              ),
              const Divider(color: Colors.white10, thickness: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    // Headers tab
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: KeyValueTable(map: widget.entry.responseHeaders),
                    ),

                    // Body tab with two-option view (Json / Raw)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<ResponseBodyView>(
                                  title: const Text('Json'),
                                  value: ResponseBodyView.json,
                                  groupValue: view,
                                  onChanged: (v) => _setView(v ?? ResponseBodyView.json),
                                  dense: true,
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<ResponseBodyView>(
                                  title: const Text('Raw'),
                                  value: ResponseBodyView.raw,
                                  groupValue: view,
                                  onChanged: (v) => _setView(v ?? ResponseBodyView.raw),
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10),
                          Expanded(child: CodeEditorBox(content: widget.entry.responseBody)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _compactTabContent() {
    // Build a simplified stacked layout for small heights. We reuse the
    // current view for body and headers; Tab switching won't be interactive in
    // the compact fallback, but this avoids layout overflow.
    return Column(
      children: [
        // Show headers first
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: KeyValueTable(map: widget.entry.responseHeaders),
        ),
        const Divider(color: Colors.white10),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: CodeEditorBox(content: widget.entry.responseBody),
        ),
      ],
    );
  }
}
