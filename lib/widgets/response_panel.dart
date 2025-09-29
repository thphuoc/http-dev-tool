import 'package:flutter/material.dart';

import '../models/http_entry.dart';
import 'resizable_key_value_table.dart';
import 'package:httpdevtool/widgets/response_viewer.dart';

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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: LayoutBuilder(
        builder: (context, constraints) {

          // Normal layout
          return Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: 'Headers', height: 30),
                  Tab(text: 'Body', height: 30)
                ],
                tabAlignment: TabAlignment.start,
                isScrollable: true,
                indicatorSize: TabBarIndicatorSize.tab,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    //Headers tab
                    ResizableKeyValueTable(map: widget.entry.responseHeaders),
                    //Json
                    Expanded(
                      child: ResponseViewer(content: widget.entry.responseBody),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
