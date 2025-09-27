import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';

import '../models/http_entry.dart';

typedef OnSelectCallback = void Function(int index);

class TopPanel extends StatelessWidget {
  final List<HttpEntry> entries;
  final int selectedIndex;
  final OnSelectCallback onSelect;
  final Color Function(String) codeColor;

  const TopPanel({required this.entries, required this.selectedIndex, required this.onSelect, required this.codeColor, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: Card(
        color: Colors.grey[850],
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: DataTable2(
            columnSpacing: 0,
            horizontalMargin: 8,
            minWidth: 800,
            // Hide the built-in checkbox column when rows are selectable
            showCheckboxColumn: false,
            columns: const [
              // Method and HTTP Code are compact columns sized to their content.
              DataColumn2(label: Text('Method'), fixedWidth: 80),
              DataColumn2(label: Text('HTTP Code'), fixedWidth: 100),
              DataColumn2(label: Text('Request At'), fixedWidth: 100),
              DataColumn2(label: Text('Response At'), fixedWidth: 100),
              DataColumn2(label: Text('Total Time'), fixedWidth: 100),
              DataColumn(label: Text('URL')),
            ],
            rows: List<DataRow>.generate(entries.length, (i) {
              final e = entries[i];
              final selectedRow = i == selectedIndex;
              return DataRow(
                selected: selectedRow,
                color: WidgetStateProperty.resolveWith<Color?>((states) {
                  if (i % 2 == 0) return Colors.grey[850];
                  return Colors.grey[800];
                }),
                cells: [
                  DataCell(Text(e.method)),
                  // Smaller code badge so the column stays compact.
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: codeColor(e.code),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SizedBox(width: 48, child: Text(e.code, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 12))),
                  )),
                  DataCell(Text('${e.reqAt.hour.toString().padLeft(2, '0')}:${e.reqAt.minute.toString().padLeft(2, '0')}')),
                  DataCell(Text(e.resAt == null ? 'N/A' : '${e.resAt!.hour.toString().padLeft(2, '0')}:${e.resAt!.minute.toString().padLeft(2, '0')}')),
                  DataCell(Text(e.totalTime)),
                  DataCell(SizedBox(width: 600, child: Text(e.url, overflow: TextOverflow.ellipsis))),
                ],
                onSelectChanged: (v) {
                  // Always call onSelect when the row is interacted with so that
                  // clicking the same row again will still trigger showing the
                  // details panel even if it was previously selected.
                  onSelect(i);
                },
              );
            }),
          ),
        ),
      ),
    );
  }
}
