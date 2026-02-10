import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- DATA MODELS ---

class MapItem {
  final String id;
  final IconData icon;
  final Color defaultColor;
  final String label;

  const MapItem({required this.id, required this.icon, required this.defaultColor, required this.label});
}

class PlacedItem {
  final String uniqueId;
  final String mapItemId;
  Offset position;
  int quantity;
  Color color;

  PlacedItem({required this.uniqueId, required this.mapItemId, required this.position, this.quantity = 1, required this.color});

  Map<String, dynamic> toJson() => {'uniqueId': uniqueId, 'mapItemId': mapItemId, 'dx': position.dx, 'dy': position.dy, 'quantity': quantity, 'color': color.value};

  factory PlacedItem.fromJson(Map<String, dynamic> json) {
    return PlacedItem(uniqueId: json['uniqueId'], mapItemId: json['mapItemId'], position: Offset(json['dx'], json['dy']), quantity: json['quantity'] ?? 1, color: Color(json['color']));
  }
}

void main() {
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: TacticalMapPage()));
}

class TacticalMapPage extends StatefulWidget {
  const TacticalMapPage({super.key});

  @override
  State<TacticalMapPage> createState() => _TacticalMapPageState();
}

class _TacticalMapPageState extends State<TacticalMapPage> {
  final TransformationController _transformController = TransformationController();
  final GlobalKey _mapStackKey = GlobalKey();

  double _currentScale = 1.0;
  bool _isDraggingMapPin = false;

  // --- NEW GRID STATE ---
  bool _showDensityGrid = true;
  double _gridSize = 50.0; // Default Grid Size
  bool _snapToGrid = true; // Toggle Snapping

  final List<MapItem> _availableTypes = [
    MapItem(id: '1', icon: Icons.local_fire_department, defaultColor: Colors.orange, label: 'Fire'),
    MapItem(id: '2', icon: Icons.water_drop, defaultColor: Colors.blue, label: 'Water'),
    MapItem(id: '3', icon: Icons.flash_on, defaultColor: Colors.yellow, label: 'Power'),
    MapItem(id: '4', icon: Icons.security, defaultColor: Colors.grey, label: 'Guard'),
    MapItem(id: '5', icon: Icons.medical_services, defaultColor: Colors.red, label: 'Medic'),
  ];

  List<PlacedItem> _placedItems = [];
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  static const double _mapWidth = 1000;
  static const double _mapHeight = 800;
  static const double _iconSize = 40;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformationChange);
    _loadMapState();
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformationChange);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformationChange() {
    setState(() {
      _currentScale = _transformController.value.getMaxScaleOnAxis();
    });
  }

  // --- SNAP LOGIC ---

  Offset _getSnappedPosition(Offset actualPosition) {
    if (!_snapToGrid) return actualPosition;

    // Calculate the column and row (0-indexed)
    final int col = (actualPosition.dx / _gridSize).floor();
    final int row = (actualPosition.dy / _gridSize).floor();

    // Calculate center of that cell
    final double centerX = (col * _gridSize) + (_gridSize / 2);
    final double centerY = (row * _gridSize) + (_gridSize / 2);

    return Offset(centerX, centerY);
  }

  // --- MEMENTO & PERSISTENCE ---

  String _serializeState() => jsonEncode(_placedItems.map((e) => e.toJson()).toList());

  void _deserializeState(String jsonString) {
    final List<dynamic> decoded = jsonDecode(jsonString);
    setState(() {
      _placedItems = decoded.map((e) => PlacedItem.fromJson(e)).toList();
    });
  }

  void _recordHistory() {
    setState(() {
      _undoStack.add(_serializeState());
      _redoStack.clear();
    });
    if (_undoStack.length > 50) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(_serializeState());
      _deserializeState(_undoStack.removeLast());
    });
    _saveToPrefs();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_serializeState());
      _deserializeState(_redoStack.removeLast());
    });
    _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tactical_map_data', _serializeState());
  }

  Future<void> _loadMapState() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('tactical_map_data');
    if (data != null) _deserializeState(data);
  }

  // --- INTERACTIONS ---

  void _onDropFromMenu(DragTargetDetails<Object> details) {
    if (details.data is! MapItem) return;
    _recordHistory();
    final itemType = details.data as MapItem;

    // 1. Get exact drop coordinate
    final RenderBox renderBox = _mapStackKey.currentContext!.findRenderObject() as RenderBox;
    final Offset localPos = renderBox.globalToLocal(details.offset);

    // 2. Apply Snap
    final Offset snappedPos = _getSnappedPosition(localPos);

    setState(() {
      // Use spread operator to force list update (better for CustomPainter triggers)
      _placedItems = [..._placedItems, PlacedItem(uniqueId: DateTime.now().millisecondsSinceEpoch.toString(), mapItemId: itemType.id, position: snappedPos, color: itemType.defaultColor)];
    });
    _saveToPrefs();
  }

  void _onDropToTrash(PlacedItem item) {
    _recordHistory();
    setState(() {
      _placedItems.removeWhere((i) => i.uniqueId == item.uniqueId);
      _placedItems = [..._placedItems]; // Force refresh
      _isDraggingMapPin = false;
    });
    _saveToPrefs();
  }

  void _onRepositionPin(PlacedItem item, Offset newGlobalPos) {
    _recordHistory();
    final RenderBox renderBox = _mapStackKey.currentContext!.findRenderObject() as RenderBox;
    final Offset localPos = renderBox.globalToLocal(newGlobalPos);

    // Apply Snap
    final Offset snappedPos = _getSnappedPosition(localPos);

    setState(() {
      item.position = snappedPos;
      // Force repaint by updating list reference even if object is mutated
      _placedItems = [..._placedItems];
      _isDraggingMapPin = false;
    });
    _saveToPrefs();
  }

  Future<void> _onPinTap(PlacedItem item) async {
    await showDialog(
      context: context,
      builder: (ctx) => EditPinDialog(
        initialQuantity: item.quantity,
        initialColor: item.color,
        onSave: (newQty, newColor) {
          _recordHistory();
          setState(() {
            item.quantity = newQty;
            item.color = newColor;
            _placedItems = [..._placedItems]; // Force repaint
          });
          _saveToPrefs();
        },
      ),
    );
  }

  MapItem _getType(String id) => _availableTypes.firstWhere((e) => e.id == id, orElse: () => _availableTypes.first);

  // --- BUILD UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tactical Map Editor"),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: Icon(_snapToGrid ? Icons.grid_3x3 : Icons.grid_off), tooltip: _snapToGrid ? "Snap On" : "Snap Off", onPressed: () => setState(() => _snapToGrid = !_snapToGrid)),
          IconButton(icon: Icon(_showDensityGrid ? Icons.visibility : Icons.visibility_off), tooltip: "Toggle Heatmap", onPressed: () => setState(() => _showDensityGrid = !_showDensityGrid)),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              _recordHistory();
              setState(() => _placedItems = []);
              await _saveToPrefs();
            },
            tooltip: "Clear Map",
          ),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  color: Colors.black87,
                  child: ClipRect(
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      minScale: 0.1,
                      maxScale: 5.0,
                      constrained: false,
                      child: _buildMapContent(),
                    ),
                  ),
                ),
              ),
              _buildSideMenu(),
            ],
          ),
          if (_isDraggingMapPin) _buildTrashZone(),
        ],
      ),
    );
  }

  Widget _buildMapContent() {
    return DragTarget<Object>(
      onAcceptWithDetails: (details) {
        if (details.data is MapItem)
          _onDropFromMenu(details);
        else if (details.data is PlacedItem)
          _onRepositionPin(details.data as PlacedItem, details.offset);
      },
      builder: (context, candidates, rejects) {
        return Container(
          key: _mapStackKey,
          width: _mapWidth,
          height: _mapHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // OPTIMIZATION: Wrap static/heavy paints in RepaintBoundary
              RepaintBoundary(
                child: Stack(
                  children: [
                    // 1. BACKGROUND
                    Positioned.fill(
                      child: Container(
                        color: Colors.blueGrey[900],
                        child: Center(
                          child: Text(
                            'Tactical Grid $_mapWidth x $_mapHeight',
                            style: const TextStyle(color: Colors.white10, fontSize: 40, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),

                    // 2. DENSITY GRID (Responsive to Slider)
                    if (_showDensityGrid)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: DensityGridPainter(
                            items: _placedItems,
                            gridSize: _gridSize, // <--- Dynamic Grid Size
                            opacity: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 3. PINS (Dynamic Layer)
              ..._placedItems.map((placedItem) => Positioned(left: placedItem.position.dx, top: placedItem.position.dy, child: _buildInteractivePin(placedItem))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSideMenu() {
    return Container(
      width: 140, // Widened slightly for text
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(icon: const Icon(Icons.reply), onPressed: _undoStack.isNotEmpty ? _undo : null),
              IconButton(icon: const Icon(Icons.forward), onPressed: _redoStack.isNotEmpty ? _redo : null),
            ],
          ),
          const Divider(),

          // --- GRID SIZE CONTROLS ---
          const Text("Grid Size", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Slider(
            value: _gridSize,
            min: 20,
            max: 150,
            divisions: 13,
            label: _gridSize.round().toString(),
            onChanged: (val) {
              setState(() {
                _gridSize = val;
              });
            },
          ),
          const Divider(),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _availableTypes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 20),
              itemBuilder: (context, index) => _buildDraggableMenuItem(_availableTypes[index]),
            ),
          ),
          const Divider(),
          const Text("Zoom", style: TextStyle(fontSize: 10)),
          SizedBox(
            height: 120,
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: _currentScale.clamp(0.1, 5.0),
                min: 0.1,
                max: 5.0,
                activeColor: Colors.blueGrey,
                onChanged: (val) {
                  _transformController.value = Matrix4.identity()..scale(val);
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDraggableMenuItem(MapItem item) {
    return Draggable<MapItem>(
      data: item,
      feedback: Material(
        color: Colors.transparent,
        child: Icon(item.icon, color: item.defaultColor, size: 50),
      ),
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[100],
            child: Icon(item.icon, color: item.defaultColor),
          ),
          const SizedBox(height: 4),
          Text(item.label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildInteractivePin(PlacedItem placed) {
    final itemType = _getType(placed.mapItemId);
    final inverseScale = 1 / _currentScale;
    final size = _iconSize;

    return Transform.translate(
      offset: Offset(-(size * inverseScale) / 2, -(size * inverseScale) / 2),
      child: GestureDetector(
        onTap: () => _onPinTap(placed),
        child: Draggable<PlacedItem>(
          data: placed,
          onDragStarted: () => setState(() => _isDraggingMapPin = true),
          onDraggableCanceled: (_, __) => setState(() => _isDraggingMapPin = false),
          onDragEnd: (d) => setState(() => _isDraggingMapPin = false),
          feedback: Material(
            color: Colors.transparent,
            child: Transform.scale(
              scale: 1.2,
              child: Icon(itemType.icon, color: placed.color, size: size),
            ),
          ),
          childWhenDragging: const SizedBox(),
          child: Transform.scale(
            scale: inverseScale,
            alignment: Alignment.center,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(itemType.icon, color: placed.color, size: size),
                  if (placed.quantity > 1)
                    Positioned(
                      right: -5,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text(
                          '${placed.quantity}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrashZone() {
    return Positioned(
      bottom: 20,
      left: 20,
      child: DragTarget<PlacedItem>(
        onAccept: _onDropToTrash,
        builder: (context, candidates, rejects) {
          bool active = candidates.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: active ? 140 : 120,
            height: active ? 100 : 80,
            decoration: BoxDecoration(
              color: active ? Colors.red : Colors.red.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black45)],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.delete_outline, color: Colors.white, size: 30),
                Text(
                  "Remove",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- UPDATED DENSITY GRID PAINTER ---

class DensityGridPainter extends CustomPainter {
  final List<PlacedItem> items;
  final double gridSize;
  final double opacity;

  DensityGridPainter({required this.items, this.gridSize = 50.0, this.opacity = 0.5});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Grid Lines (To help user see the snap grid)
    final Paint linePaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1.0;

    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    if (items.isEmpty) return;

    // 2. Binning: Calculate the value for each grid cell
    final Map<String, int> gridData = {};

    for (var item in items) {
      final int gridX = (item.position.dx / gridSize).floor();
      final int gridY = (item.position.dy / gridSize).floor();
      final String key = "${gridX}_$gridY";
      gridData[key] = (gridData[key] ?? 0) + item.quantity;
    }

    // 3. Drawing Heatmap Cells
    final Paint cellPaint = Paint()..style = PaintingStyle.fill;

    gridData.forEach((key, value) {
      final parts = key.split('_');
      final int gridX = int.parse(parts[0]);
      final int gridY = int.parse(parts[1]);

      final double normalized = (min(value, 10) / 10.0);

      // Color Mixing: White -> Deep Blue
      final Color cellColor = Color.lerp(Colors.white, const Color(0xFF0D47A1), normalized)!;

      cellPaint.color = cellColor.withOpacity(opacity);

      final rect = Rect.fromLTWH(gridX * gridSize, gridY * gridSize, gridSize, gridSize);

      canvas.drawRect(rect, cellPaint);
    });
  }

  @override
  bool shouldRepaint(covariant DensityGridPainter oldDelegate) {
    return oldDelegate.items != items || oldDelegate.gridSize != gridSize || oldDelegate.opacity != opacity;
  }
}

// --- DIALOGS ---

class EditPinDialog extends StatefulWidget {
  final int initialQuantity;
  final Color initialColor;
  final Function(int, Color) onSave;

  const EditPinDialog({super.key, required this.initialQuantity, required this.initialColor, required this.onSave});

  @override
  State<EditPinDialog> createState() => _EditPinDialogState();
}

class _EditPinDialogState extends State<EditPinDialog> {
  late int _quantity;
  late Color _color;
  final List<Color> _colors = [Colors.red, Colors.orange, Colors.amber, Colors.green, Colors.blue, Colors.indigo, Colors.purple, Colors.grey, Colors.black];

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity;
    _color = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit Unit"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("Count: "),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () => setState(() {
                  if (_quantity > 1) _quantity--;
                }),
              ),
              Text("$_quantity", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() {
                  _quantity++;
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Color:"),
          const SizedBox(height: 5),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colors
                .map(
                  (c) => GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: _color == c ? Border.all(color: Colors.black, width: 3) : null,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_quantity, _color);
            Navigator.pop(context);
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
