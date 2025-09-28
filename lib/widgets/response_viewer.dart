import 'package:flutter/material.dart';

class ResponseViewer extends StatefulWidget {
  final String content; // nội dung JSON string hoặc text

  const ResponseViewer({super.key, required this.content});

  @override
  State<ResponseViewer> createState() => _ResponseViewerState();
}

class _ResponseViewerState extends State<ResponseViewer> {
  bool _isEditMode = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + switch
        Row(
          children: [
            const Text('Rewrite'),
            Switch(
              value: _isEditMode,
              onChanged: (val) {
                setState(() {
                  _isEditMode = val;
                });
              },
            ),
          ],
        ),
        const Divider(height: 1),

        // Nội dung
        Expanded(child: _buildViewMode()),
      ],
    );
  }

  Widget _buildViewMode() {
    final lineCount = widget.content.split('\n').length;

    return Row(
      children: [
        // line number
        Container(
          width: 40,
          color: Colors.black,
          child: ListView.builder(
            itemCount: lineCount,
            itemBuilder: (context, index) {
              return Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              );
            },
          ),
        ),
        // json view
        Expanded(
          child: _isEditMode
              ? TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(8),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  onChanged: (_) {
                    setState(() {}); // update line numbers
                  },
                )
              : SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(widget.content, style: const TextStyle(fontFamily: 'monospace', fontSize: 13),),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
