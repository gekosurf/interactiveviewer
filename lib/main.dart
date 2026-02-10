import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: MapStackView()));
}

class MapStackView extends StatefulWidget {
  const MapStackView({super.key});

  @override
  State<MapStackView> createState() => _MapStackViewState();
}

class _MapStackViewState extends State<MapStackView> {
  final List<Offset> _pins = [];
  final TransformationController _transformController = TransformationController();

  bool _is3D = false; // Toggle state

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("3D Map with Shadows")),
      backgroundColor: Colors.grey[900],
      floatingActionButton: FloatingActionButton(onPressed: () => setState(() => _is3D = !_is3D), child: Icon(_is3D ? Icons.map : Icons.view_in_ar)),
      body: Center(
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.1,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          constrained: false,

          // ANIMATE THE TILT
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            tween: Tween<double>(begin: 0, end: _is3D ? 1.1 : 0),
            builder: (context, angle, child) {
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // Perspective
                  ..rotateX(-angle), // Tilt Map
                child: _buildContent(angle),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(double tiltAngle) {
    return GestureDetector(
      onTapUp: (details) {
        setState(() {
          _pins.add(details.localPosition);
        });
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. THE MAP IMAGE
          // 1. BACKGROUND
          Container(
            width: 2000,
            height: 2000,
            color: Colors.blueGrey[900],
            child: const Center(
              child: Text(
                'Tactical Grid ',
                style: TextStyle(color: Colors.white10, fontSize: 40, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // ... Shaders would go here ...

          // 2. THE PINS AND SHADOWS
          // We use expand to generate 2 widgets for every 1 pin location
          ..._pins.expand((offset) {
            return [
              // --- A. THE SHADOW (Stays Flat) ---
              Positioned(
                left: offset.dx - 12, // Center the shadow (width 24 / 2)
                top: offset.dy - 8, // Align under the pin tip
                child: Transform(
                  alignment: Alignment.center,
                  // Squash the shadow vertically to look like a disk on the floor
                  transform: Matrix4.diagonal3Values(1.0, 0.4, 1.0),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3), // Semi-transparent
                      shape: BoxShape.circle,
                      // Blur enables a softer shadow look
                      boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black45)],
                    ),
                  ),
                ),
              ),

              // --- B. THE PIN (Stands Up) ---
              Positioned(
                left: offset.dx - 24,
                top: offset.dy - 48,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  // Counter-rotate to stand up vertically
                  transform: Matrix4.identity()..rotateX(tiltAngle),
                  child: const Icon(Icons.location_on, color: Colors.red, size: 48),
                ),
              ),
            ];
          }),
        ],
      ),
    );
  }
}
