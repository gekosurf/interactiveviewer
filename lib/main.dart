import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

void main() {
  debugPaintPointersEnabled = true; // Enables visualization

  runApp(const MaterialApp(home: MapStackView()));
}

class MapStackView extends StatefulWidget {
  const MapStackView({super.key});

  @override
  State<MapStackView> createState() => _MapStackViewState();
}

enum PieceType { knight, queen }

class ChessPiece {
  final String id;
  final Offset position;
  final PieceType type;

  ChessPiece({required this.id, required this.position, required this.type});
}

class _MapStackViewState extends State<MapStackView> with SingleTickerProviderStateMixin {
  final List<ChessPiece> _pieces = [];
  final TransformationController _transformController = TransformationController();
  late AnimationController _tiltController;
  late Animation<double> _tiltAnimation;

  bool _is3D = false;
  ChessPiece? _draggingPiece;
  Offset _dragOffset = Offset.zero;
  PieceType _selectedType = PieceType.knight;

  static const int gridSize = 8;
  static const double cellSize = 100.0;
  static const double boardSize = gridSize * cellSize;

  @override
  void initState() {
    super.initState();
    _tiltController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    _tiltAnimation = CurvedAnimation(parent: _tiltController, curve: Curves.easeInOutCubic)
      ..addListener(() {
        _updateTransformation(_tiltAnimation.value);
        setState(() {});
      });
    _updateTransformation(0.0);
  }

  @override
  void dispose() {
    _tiltController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _updateTransformation(double t) {
    final Matrix4 matrix = Matrix4.identity();
    if (t > 0) {
      // Create a centered perspective transformation
      final double center = boardSize / 2;
      matrix.translate(center, center);

      final Matrix4 perspective = Matrix4.identity()
        ..setEntry(3, 2, 0.001 * t) // Perspective grows with t
        ..rotateX(-1.1 * t); // Rotation grows with t
      matrix.multiply(perspective);

      matrix.translate(-center, -center);
    }
    _transformController.value = matrix;
  }

  void _handlePieceDragStart(ChessPiece piece, DragStartDetails details) {
    debugPrint("LOG: Piece drag start! Grabbing piece ${piece.id}");

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPoint = renderBox.globalToLocal(details.globalPosition);
    final Offset scenePoint = _transformController.toScene(localPoint);

    setState(() {
      _draggingPiece = piece;
      _dragOffset = piece.position - scenePoint;
    });
  }

  void _handlePieceDragUpdate(DragUpdateDetails details) {
    if (_draggingPiece == null) return;

    // Use toScene to convert the pointer's local position (relative to the viewer)
    // to the board's scene coordinates.
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPoint = renderBox.globalToLocal(details.globalPosition);
    final Offset scenePoint = _transformController.toScene(localPoint);

    setState(() {
      final index = _pieces.indexWhere((p) => p.id == _draggingPiece!.id);
      if (index != -1) {
        // Drag to the current scene point + initial offset
        _pieces[index] = ChessPiece(id: _draggingPiece!.id, position: scenePoint + _dragOffset, type: _draggingPiece!.type);
      }
    });
  }

  void _handlePieceDragEnd(DragEndDetails details) {
    if (_draggingPiece != null) {
      debugPrint("LOG: Piece drag end - Snapping to grid");
      setState(() {
        final index = _pieces.indexWhere((p) => p.id == _draggingPiece!.id);
        if (index != -1) {
          final p = _pieces[index];
          final double x = (p.position.dx ~/ cellSize) * cellSize + cellSize / 2;
          final double y = (p.position.dy ~/ cellSize) * cellSize + cellSize / 2;
          _pieces[index] = ChessPiece(id: p.id, position: Offset(x.clamp(cellSize / 2, boardSize - cellSize / 2), y.clamp(cellSize / 2, boardSize - cellSize / 2)), type: p.type);
        }
        _draggingPiece = null;
      });
    }
  }

  void _handleTap(TapUpDetails details) {
    // If we're dragging, ignore taps (though pan will likely intercept)
    if (_draggingPiece != null) return;

    // GestureDetector is inside InteractiveViewer, so localPosition is already scene-relative
    final Offset scenePoint = details.localPosition;
    final double x = (scenePoint.dx ~/ cellSize) * cellSize + cellSize / 2;
    final double y = (scenePoint.dy ~/ cellSize) * cellSize + cellSize / 2;

    if (x >= 0 && x <= boardSize && y >= 0 && y <= boardSize) {
      debugPrint("LOG: Tap to add piece at $x, $y");
      setState(() {
        _pieces.add(ChessPiece(id: DateTime.now().millisecondsSinceEpoch.toString(), position: Offset(x, y), type: _selectedType));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("3D Tactical Chess Map"),
        actions: [
          Row(
            children: [
              const Text("Piece: "),
              DropdownButton<PieceType>(
                value: _selectedType,
                dropdownColor: Colors.grey[800],
                style: const TextStyle(color: Colors.white),
                onChanged: (PieceType? newValue) {
                  if (newValue != null) setState(() => _selectedType = newValue);
                },
                items: PieceType.values.map<DropdownMenuItem<PieceType>>((PieceType value) {
                  return DropdownMenuItem<PieceType>(value: value, child: Text(value.name.toUpperCase()));
                }).toList(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.white),
                tooltip: "Clear All Pieces",
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Clear Board?"),
                      content: const Text("This will remove all pieces."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                        TextButton(
                          onPressed: () {
                            setState(() => _pieces.clear());
                            Navigator.pop(context);
                          },
                          child: const Text("Clear"),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
            ],
          ),
        ],
      ),
      backgroundColor: Colors.grey[900],
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _is3D = !_is3D;
            if (_is3D) {
              _tiltController.forward();
            } else {
              _tiltController.reverse();
            }
          });
        },
        child: Icon(_is3D ? Icons.map : Icons.view_in_ar),
      ),
      body: Center(
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.1,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          constrained: false,
          panEnabled: _draggingPiece == null,
          scaleEnabled: _draggingPiece == null,
          onInteractionStart: (details) {
            debugPrint("LOG: InteractiveViewer onInteractionStart");
          },
          onInteractionUpdate: (details) {
            if (details.pointerCount > 1) {
              debugPrint("LOG: InteractiveViewer onInteractionUpdate (Scaling/Multi-touch)");
            }
          },
          onInteractionEnd: (details) {
            debugPrint("LOG: InteractiveViewer onInteractionEnd");
          },
          child: GestureDetector(onTapUp: _handleTap, child: _buildContent()),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. Board Background
        CustomPaint(size: const Size(boardSize, boardSize), painter: ChessBoardPainter()),
        // 2. Pieces (Sorted for depth)
        ...(() {
          final sortedPieces = List<ChessPiece>.from(_pieces)
            ..sort((a, b) {
              int rowA = a.position.dy ~/ cellSize;
              int rowB = b.position.dy ~/ cellSize;
              if (rowA != rowB) return rowA.compareTo(rowB);
              return a.id.compareTo(b.id);
            });

          return sortedPieces.map((piece) {
            final offset = piece.position;
            final assetPath = piece.type == PieceType.knight ? 'assets/knight.png' : 'assets/queen.png';
            const double size = 80;

            final isDragging = _draggingPiece?.id == piece.id;
            final t = _tiltAnimation.value;

            // Visual corrections interpolated
            final double correctionX = -10.0 * t;
            final double correctionY = 15.0 * t;

            final double leftPos = offset.dx - (size / 2) + correctionX;

            // Interpolate topPos between centered (2D) and baseline-aligned (3D)
            final double centeredTop = offset.dy - (size / 2);
            final double baselineTop = offset.dy - (isDragging ? size + 20 : size) + correctionY;
            final double topPos = centeredTop + (baselineTop - centeredTop) * t;

            return Positioned(
              left: leftPos,
              top: topPos,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.lerp(Alignment.center, Alignment.bottomCenter, t)!,
                children: [
                  // Shadow
                  if (!isDragging)
                    Transform.translate(
                      // Interpolate shadow position from offset to base
                      offset: Offset(0, (size / 2.5) * (1 - t)),
                      child: Opacity(
                        opacity: 0.3 + (0.2 * t), // Slightly stronger shadow in 3D
                        child: Container(
                          width: size * (1.0 + 0.2 * t),
                          height: size * (0.3 + 0.1 * t),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10 * t, spreadRadius: 2 * t)],
                          ),
                        ),
                      ),
                    ),
                  // Piece
                  Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()..rotateX(1.1 * t),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) => _handlePieceDragStart(piece, details),
                      onPanUpdate: _handlePieceDragUpdate,
                      onPanEnd: _handlePieceDragEnd,
                      child: Container(
                        width: size,
                        height: size,
                        alignment: Alignment.bottomCenter,
                        color: Colors.transparent,
                        child: Opacity(
                          opacity: isDragging ? 0.7 : 1.0,
                          child: Material(
                            elevation: isDragging ? 20 : 0,
                            color: Colors.transparent,
                            child: Image.asset(assetPath, width: size, height: size, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList();
        })(),
      ],
    );
  }
}

class ChessBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const int gridSize = 8;
    final double cellSize = size.width / gridSize;
    final Paint lightPaint = Paint()..color = const Color(0xFFEBECD0);
    final Paint darkPaint = Paint()..color = const Color(0xFF779556);

    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        final rect = Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize);
        canvas.drawRect(rect, (row + col) % 2 == 0 ? lightPaint : darkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
