import 'package:flutter/material.dart';
import 'package:httpdevtool/widgets/splitter_panel.dart';
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
  double firstColumnHeight = 200;
  late final windowHeight = MediaQuery.of(context).size.height;

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
    final bottom = BottomPanel(
                        entry: mockEntries[selectedIndex],
                        onCollapse: () {
                          setState(() {
                            detailsExpanded = false;
                          });
                        },
                      );
    return Scaffold(
      appBar: AppBar(title: const Text('HTTP Inspector')),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          
          return SplitterPanel(
            firstChild: top,
            secondChild: bottom,
            isHideSecondChild: !detailsExpanded,
            isVertical: true,
          );
        },
      ),
    );
  }
}
