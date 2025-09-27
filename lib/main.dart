import 'package:flutter/material.dart';
// data_table_2 is used inside TopPanel; main.dart no longer needs to import it directly.
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
      title: 'HTTP Inspector - Mock',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueGrey[900],
        scaffoldBackgroundColor: Colors.grey[900],
      ),
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
  bool capturing = false;
  bool detailsExpanded = false;

  late final TabController bottomTabController;
  late final MultiSplitViewController msController;

  @override
  void initState() {
    super.initState();
    bottomTabController = TabController(length: 2, vsync: this);
    // Use a very small positive flex for collapsed areas instead of 0.0 to avoid
    // potential layout edge-cases in MultiSplitView when areas have zero size.
    msController = MultiSplitViewController(areas: [
      Area(flex: 1, builder: (c, a) => const SizedBox.shrink()),
      Area(flex: 0.01, builder: (c, a) => const SizedBox.shrink()),
    ]);
  }

  @override
  void dispose() {
    bottomTabController.dispose();
    msController.dispose();
    super.dispose();
  }

  Color codeColor(String code) {
    if (code == 'N/A') return Colors.grey;
    if(code == "POST") return Colors.orangeAccent;
    if(code == "GET") return Colors.greenAccent.shade400;
    if(code == "DELETE") return Colors.redAccent.shade200;
    if(code == "PUT") return Colors.lightBlueAccent.shade400;
    if(code == "PATCH") return Colors.yellow.shade600;
    if(code == "OPTIONS") return Colors.purpleAccent.shade400;
    if(code == "HEAD") return Colors.deepPurpleAccent.shade400;
    if(code == "CONNECT") return Colors.black87;
    final n = int.tryParse(code) ?? 0;
    if (n >= 200 && n < 300) return Colors.greenAccent.shade400;
    if (n >= 300 && n < 400) return Colors.yellow.shade600;
    if (n >= 400) return Colors.redAccent.shade200;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final selected = mockEntries[selectedIndex];
    return Scaffold(
      appBar: AppBar(
        title: const Text('HTTP Inspector (Mock)'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.settings, color: Colors.white70),
            label: const Text('Settings', style: TextStyle(color: Colors.white70)),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.clear, color: Colors.white70),
            label: const Text('Clear', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => setState(() => capturing = !capturing),
            icon: Icon(capturing ? Icons.stop : Icons.play_arrow),
            label: Text(capturing ? 'Stop Capture' : 'Start Capture'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Builder(builder: (context) {
          // Update controller areas with builders for each pane. Using the
          // Area.builder lets MultiSplitView render the widgets for each area.
          msController.areas = [
            Area(
              flex: 1,
              builder: (ctx, area) => TopPanel(
                entries: mockEntries,
                selectedIndex: selectedIndex,
                codeColor: codeColor,
                onSelect: (i) => setState(() {
                  selectedIndex = i;
                  detailsExpanded = true;
                }),
              ),
            ),
            Area(
              // Use a tiny positive flex when collapsed instead of 0.0. When
              // detailsExpanded is false the builder returns SizedBox.shrink().
              flex: detailsExpanded ? 0.35 : 0.01,
              builder: (ctx, area) => detailsExpanded
                  ? BottomPanel(entry: selected, onCollapse: () => setState(() => detailsExpanded = false))
                  : const SizedBox.shrink(),
            ),
          ];

          return MultiSplitView(
            controller: msController,
            axis: Axis.vertical,
            dividerBuilder: (axis, index, resizable, dragging, highlighted, themeData) =>
                const Divider(color: Colors.white10),
          );
        }),
      ),
    );
  }
}
