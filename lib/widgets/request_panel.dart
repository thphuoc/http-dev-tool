import 'package:flutter/material.dart';

import '../models/http_entry.dart';
import 'key_value_table.dart';
import 'code_editor_box.dart';

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

  void _setMode(RequestBodyMode m) => setState(() => mode = m);

  Widget _buildBodyContent() {
    switch (mode) {
      case RequestBodyMode.form:
        return KeyValueTable(map: widget.entry.requestForm);
      case RequestBodyMode.params:
        return KeyValueTable(map: widget.entry.requestParams);
      case RequestBodyMode.json:
      case RequestBodyMode.raw:
        return CodeEditorBox(content: widget.entry.requestBody);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: DefaultTabController(
        length: 2,
        child: LayoutBuilder(builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          const compactThreshold = 120.0;

          Widget tabBarSized = SizedBox(
            height: 36,
            child: const TabBar(
              tabs: [Tab(text: 'Headers'), Tab(text: 'Body')],
              labelPadding: EdgeInsets.symmetric(horizontal: 8),
              indicatorWeight: 2,
            ),
          );

          if (availableHeight.isFinite && availableHeight < compactThreshold) {
            final safeHeight = (availableHeight - 1.0).clamp(0.0, double.infinity);
            return SizedBox(
              height: safeHeight,
              child: Column(
                children: [
                  tabBarSized,
                  const Divider(color: Colors.white10, thickness: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: KeyValueTable(map: widget.entry.requestHeaders),
                          ),
                          const Divider(color: Colors.white10),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                // Radio group
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    SizedBox(
                                      width: 180,
                                      child: RadioListTile<RequestBodyMode>(
                                        title: const Text('Form data'),
                                        value: RequestBodyMode.form,
                                        groupValue: mode,
                                        onChanged: (v) => _setMode(v ?? RequestBodyMode.form),
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 180,
                                      child: RadioListTile<RequestBodyMode>(
                                        title: const Text('Parameters'),
                                        value: RequestBodyMode.params,
                                        groupValue: mode,
                                        onChanged: (v) => _setMode(v ?? RequestBodyMode.params),
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: RadioListTile<RequestBodyMode>(
                                        title: const Text('Json'),
                                        value: RequestBodyMode.json,
                                        groupValue: mode,
                                        onChanged: (v) => _setMode(v ?? RequestBodyMode.json),
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: RadioListTile<RequestBodyMode>(
                                        title: const Text('Raw'),
                                        value: RequestBodyMode.raw,
                                        groupValue: mode,
                                        onChanged: (v) => _setMode(v ?? RequestBodyMode.raw),
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.white10),
                                _buildBodyContent(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              tabBarSized,
              const Divider(color: Colors.white10, thickness: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    // Headers tab
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: KeyValueTable(map: widget.entry.requestHeaders),
                    ),

                    // Body tab with radio group to choose representation
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          // Radio group
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              SizedBox(
                                width: 180,
                                child: RadioListTile<RequestBodyMode>(
                                  title: const Text('Form data'),
                                  value: RequestBodyMode.form,
                                  groupValue: mode,
                                  onChanged: (v) => _setMode(v ?? RequestBodyMode.form),
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              SizedBox(
                                width: 180,
                                child: RadioListTile<RequestBodyMode>(
                                  title: const Text('Parameters'),
                                  value: RequestBodyMode.params,
                                  groupValue: mode,
                                  onChanged: (v) => _setMode(v ?? RequestBodyMode.params),
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: RadioListTile<RequestBodyMode>(
                                  title: const Text('Json'),
                                  value: RequestBodyMode.json,
                                  groupValue: mode,
                                  onChanged: (v) => _setMode(v ?? RequestBodyMode.json),
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: RadioListTile<RequestBodyMode>(
                                  title: const Text('Raw'),
                                  value: RequestBodyMode.raw,
                                  groupValue: mode,
                                  onChanged: (v) => _setMode(v ?? RequestBodyMode.raw),
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              
                            ],
                          ),
                          const Divider(color: Colors.white10),
                          Expanded(child: _buildBodyContent()),
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
}
