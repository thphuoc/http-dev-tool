import 'package:flutter/material.dart';

class ResizableKeyValueTable extends StatefulWidget {
  final Map<String, String> map;
  const ResizableKeyValueTable({required this.map, super.key});

  @override
  State<ResizableKeyValueTable> createState() => _ResizableKeyValueTableState();
}

class _ResizableKeyValueTableState extends State<ResizableKeyValueTable> {
  double firstColumnWidth = 200;

  @override
  Widget build(BuildContext context) {
    final entries = widget.map.entries.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView.builder(
          itemCount: entries.length,
          shrinkWrap: true,
          itemBuilder: (context, i) {
            final kv = entries[i];
            final bgColor = i.isEven
                ? const Color.fromARGB(255, 63, 63, 63).withAlpha(
                    100,
                  ) // light background for even rows
                : Colors.transparent; // transparent for odd rows
            return IntrinsicHeight(
              child: Container(
                color: bgColor,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // First column
                    SizedBox(
                      width: firstColumnWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          // 👈 here
                          vertical: 8.0,
                          horizontal: 16.0,
                        ),
                        child: Text(kv.key),
                      ),
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
                                  80,
                                  600,
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          // 👈 here
                          vertical: 8.0,
                          horizontal: 16.0,
                        ),
                        child: Text(kv.value),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
