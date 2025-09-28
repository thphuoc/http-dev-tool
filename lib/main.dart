import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';

import 'models/http_entry.dart';
import 'widgets/top_panel.dart';
import 'widgets/bottom_panel.dart';

void main() => runApp(const InspectorApp());

class InspectorApp extends StatelessWidget {
  const InspectorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTTP Inspector',
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  int selectedIndex = 0;
  bool detailsExpanded = false;
  double firstColumnWidth = 200;
  late final MultiSplitViewController msController;

  @override
  void initState() {
    super.initState();
  }

  Color codeColor(String code) {
    if (code == 'N/A') return Colors.grey;
    if (code == "POST") return Colors.orangeAccent;
    if (code == "GET") return Colors.greenAccent.shade400;
    if (code == "DELETE") return Colors.redAccent.shade200;
    if (code == "PUT") return Colors.lightBlueAccent.shade400;
    if (code == "PATCH") return Colors.yellow.shade600;
    if (code == "OPTIONS") return Colors.purpleAccent.shade400;
    if (code == "HEAD") return Colors.deepPurpleAccent.shade400;
    if (code == "CONNECT") return Colors.black87;
    final n = int.tryParse(code) ?? 0;
    if (n >= 200 && n < 300) return Colors.greenAccent.shade400;
    if (n >= 300 && n < 400) return Colors.yellow.shade600;
    if (n >= 400) return Colors.redAccent.shade200;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final top = TopPanel(
      entries: mockEntries,
      selectedIndex: selectedIndex,
      codeColor: codeColor,
      onSelect: (i) {
        setState(() {
          detailsExpanded = selectedIndex == i ? !detailsExpanded : true;
          selectedIndex = i;
        });
      },
    );
    print('selectedIndex=${mockEntries[selectedIndex].responseHeaders.entries.first.key}');
    
    return Scaffold(
      appBar: AppBar(title: const Text('HTTP Inspector')),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          return detailsExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: firstColumnWidth, child: top),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          setState(() {
                            firstColumnWidth =
                                (firstColumnWidth + details.delta.dy).clamp(
                                  80,
                                  600,
                                );
                          });
                        },
                        child: SizedBox(
                          height: 6, // hit area width
                          child: Center(
                            child: Container(
                              height: 0.5, // visible line width
                              color: const Color.fromARGB(
                                255,
                                94,
                                93,
                                93,
                              ), // visible line color
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: BottomPanel(
                        entry: mockEntries[selectedIndex],
                        onCollapse: () {
                          setState(() {
                            detailsExpanded = false;
                          });
                        },
                      ),
                    ),
                  ],
                )
              : Expanded(child: top);
        },
      ),
    );
  }
}
