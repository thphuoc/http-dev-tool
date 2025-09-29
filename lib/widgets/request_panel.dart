import 'package:flutter/material.dart';
import 'package:httpdevtool/widgets/resizable_key_value_table.dart';

import '../models/http_entry.dart';
import 'package:httpdevtool/widgets/response_viewer.dart';

enum RequestBodyMode { form, json, raw, params }

class RequestPanel extends StatefulWidget {
  final HttpEntry entry;
  const RequestPanel({required this.entry, super.key});

  @override
  State<RequestPanel> createState() => _RequestPanelState();
}

class _RequestPanelState extends State<RequestPanel> {
  late RequestBodyMode mode;

  @override
  void initState() {
    super.initState();
    final body = widget.entry.requestBody.trim();
    if (widget.entry.requestForm.isNotEmpty) {
      mode = RequestBodyMode.form;
    } else if (body.startsWith('{') || body.startsWith('[')) {
      mode = RequestBodyMode.json;
    } else {
      mode = RequestBodyMode.raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'Headers', height: 30),
              Tab(text: 'Parameters', height: 30),
              Tab(text: 'Form data', height: 30),
              Tab(text: 'Body', height: 30),
            ],
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            indicatorSize: TabBarIndicatorSize.tab,
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Headers tab
                ResizableKeyValueTable(map: widget.entry.requestHeaders),
                // Parameters tab
                ResizableKeyValueTable(map: widget.entry.requestParams),
                // Form data tab
                ResizableKeyValueTable(map: widget.entry.requestForm),
                // Json tab
                ResponseViewer(content: widget.entry.requestBody),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
