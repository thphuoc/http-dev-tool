import 'package:flutter/material.dart';

class SplitterPanel extends StatefulWidget {
  final Widget firstChild;
  final Widget secondChild;
  final bool isVertical; // true for vertical split, false for horizontal
  final double initialFirstFraction; // initial fraction of the first child
  final double splitterThickness; // thickness of the splitter
  final Color splitterColor; // color of the splitter
  final bool isHideFirstChild;
  final bool isHideSecondChild;

  const SplitterPanel({
    required this.firstChild,
    required this.secondChild,
    this.isHideFirstChild = false,
    this.isHideSecondChild = false,
    this.isVertical = true,
    this.initialFirstFraction = 0.5,
    this.splitterThickness = 3.0,
    this.splitterColor = const Color.fromARGB(96, 245, 243, 210),
    super.key,
  });

  @override
  State<SplitterPanel> createState() => _SplitterPanelState();
}

class _SplitterPanelState extends State<SplitterPanel> {
  late double firstFraction;
  bool _hovering = false;
  bool _resizing = false;
  late double windowHeight = MediaQuery.of(context).size.height;
  late double windowWidth = MediaQuery.of(context).size.width;

  @override
  void initState() {
    super.initState();
    firstFraction = widget.initialFirstFraction.clamp(0.1, 0.9);
  }

  Color _splitterColor() {
    if (_resizing) {
      return Colors.blueAccent;
    } else if (_hovering) {
      return const Color.fromARGB(255, 35, 117, 248);
    } else {
      return widget.splitterColor;
    }
  }

  Widget _buildVertical() {
    return Column(
      children: [
        Expanded(
          flex: (firstFraction * 1000).toInt(),
          child: widget.firstChild,
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => setState(() => _resizing = true),
            onVerticalDragUpdate: (details) {
              setState(() {
                firstFraction += details.delta.dy / context.size!.height;
                firstFraction = firstFraction.clamp(0.0, 1);
              });
            },
            onVerticalDragEnd: (_) => setState(() => _resizing = false),
            child: Container(
              height: widget.splitterThickness,
              color: _splitterColor(),
            ),
          ),
        ),
        Expanded(
          flex: ((1 - firstFraction) * 1000).toInt(),
          child: widget.secondChild,
        ),
      ],
    );
  }

  Widget _buildHorizontal() {
    return Row(
      children: [
        Expanded(
          flex: (firstFraction * 1000).toInt(),
          child: widget.firstChild,
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() => _resizing = true),
            onHorizontalDragUpdate: (details) {
              setState(() {
                firstFraction += details.delta.dx / context.size!.width;
                firstFraction = firstFraction.clamp(0.1, 0.9);
              });
            },
            onHorizontalDragEnd: (_) => setState(() => _resizing = false),
            child: Container(
              width: widget.splitterThickness,
              color: _splitterColor(),
            ),
          ),
        ),
        Expanded(
          flex: ((1 - firstFraction) * 1000).toInt(),
          child: widget.secondChild,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return widget.isVertical
            ? widget.isHideFirstChild
                  ? Expanded(child: widget.secondChild)
                  : widget.isHideSecondChild
                  ? Expanded(child: widget.firstChild)
                  : _buildVertical()
            : widget.isHideFirstChild
            ? Expanded(child: widget.secondChild)
            : widget.isHideSecondChild
            ? Expanded(child: widget.firstChild)
            : _buildHorizontal();
      },
    );
  }
}
