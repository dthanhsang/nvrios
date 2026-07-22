import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../models/camera.dart';

class FloorplanScreen extends StatefulWidget {
  const FloorplanScreen({super.key});

  @override
  State<FloorplanScreen> createState() => _FloorplanScreenState();
}

class _FloorplanScreenState extends State<FloorplanScreen> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;

  // Floor plan data
  String? _floorplanImageUrl;
  int? _floorplanId;
  double _fpWidth = 1.0;
  double _fpHeight = 1.0;

  // Camera positions (cam_id -> {x_pct, y_pct, rotation_deg, fov_deg})
  final Map<int, _CamPosition> _cameraPositions = {};
  List<Camera> _cameras = [];

  // Events overlay
  final Map<int, int> _cameraEventCounts = {};
  final Map<int, String> _cameraLatestEvent = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadCameras(),
      _loadFloorplan(),
      _loadEvents(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadCameras() async {
    _cameras = await _api.getCameras();
  }

  Future<void> _loadFloorplan() async {
    try {
      final resp = await http.get(
        Uri.parse('${_api.baseUrl}/api/floorplan'),
        headers: _api.authHeaders,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        _floorplanId = data['id'] as int?;
        final imagePath = data['image_path'] as String?;
        if (imagePath != null && imagePath.isNotEmpty) {
          _floorplanImageUrl = imagePath.startsWith('/') ? '${_api.baseUrl}$imagePath' : imagePath;
        }
        _fpWidth = (data['width'] as num?)?.toDouble() ?? 1.0;
        _fpHeight = (data['height'] as num?)?.toDouble() ?? 1.0;

        // Load camera positions
        final positions = data['camera_positions'] as List? ?? [];
        _cameraPositions.clear();
        for (final pos in positions) {
          final camId = pos['camera_id'] as int;
          _cameraPositions[camId] = _CamPosition(
            xPct: (pos['x_pct'] as num?)?.toDouble() ?? 0.5,
            yPct: (pos['y_pct'] as num?)?.toDouble() ?? 0.5,
            rotationDeg: (pos['rotation_deg'] as num?)?.toDouble() ?? 0,
            fovDeg: (pos['fov_deg'] as num?)?.toDouble() ?? 90,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _loadEvents() async {
    try {
      final resp = await http.get(
        Uri.parse('${_api.baseUrl}/api/floorplan/events?hours=24'),
        headers: _api.authHeaders,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final events = data['camera_events'] as Map<String, dynamic>? ?? {};
        _cameraEventCounts.clear();
        _cameraLatestEvent.clear();
        for (final entry in events.entries) {
          final camId = int.tryParse(entry.key);
          if (camId == null) continue;
          final camData = entry.value as Map<String, dynamic>? ?? {};
          _cameraEventCounts[camId] = (camData['count'] as int?) ?? 0;
          _cameraLatestEvent[camId] = camData['latest'] as String? ?? '';
        }
      }
    } catch (_) {}
  }

  Future<void> _uploadFloorplan() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2000);
    if (picked == null) return;

    setState(() => _isLoading = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${_api.baseUrl}/api/floorplan/upload'),
      );
      request.headers.addAll(_api.authHeaders);
      request.files.add(await http.MultipartFile.fromPath('file', picked.path));
      final resp = await request.send();
      if (resp.statusCode == 200) {
        await _loadFloorplan();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã tải lên sơ đồ nhà')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi upload: $e')),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _savePositions() async {
    setState(() => _isSaving = true);
    try {
      final positions = _cameraPositions.entries.map((e) => {
        'camera_id': e.key,
        'x_pct': e.value.xPct,
        'y_pct': e.value.yPct,
        'rotation_deg': e.value.rotationDeg,
        'fov_deg': e.value.fovDeg,
      }).toList();

      final resp = await http.post(
        Uri.parse('${_api.baseUrl}/api/floorplan/cameras'),
        headers: {..._api.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'positions': positions}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu vị trí camera')),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi lưu: $e')),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  void _showCameraPopup(Camera cam) {
    final count = _cameraEventCounts[cam.id] ?? 0;
    final latest = _cameraLatestEvent[cam.id] ?? 'N/A';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2330),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.videocam, color: Color(0xFFFF3B30), size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(cam.name, style: const TextStyle(color: Colors.white, fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _popupRow(Icons.event, 'Sự kiện 24h:', '$count'),
            const SizedBox(height: 8),
            _popupRow(Icons.access_time, 'Gần nhất:', latest.isNotEmpty && latest != 'N/A' ? latest : 'Chưa có'),
            if (_isEditing) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.grey),
              const SizedBox(height: 8),
              Text('Góc quay: ${_cameraPositions[cam.id]?.rotationDeg.round() ?? 0}°',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: _cameraPositions[cam.id]?.rotationDeg ?? 0,
                min: 0, max: 360,
                activeColor: const Color(0xFF007AFF),
                onChanged: (v) {
                  setState(() {
                    _cameraPositions[cam.id] = (_cameraPositions[cam.id] ?? _CamPosition()).copyWith(rotationDeg: v);
                  });
                },
              ),
              Text('Góc nhìn (FOV): ${_cameraPositions[cam.id]?.fovDeg.round() ?? 90}°',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Slider(
                value: _cameraPositions[cam.id]?.fovDeg ?? 90,
                min: 30, max: 180,
                activeColor: const Color(0xFF007AFF),
                onChanged: (v) {
                  setState(() {
                    _cameraPositions[cam.id] = (_cameraPositions[cam.id] ?? _CamPosition()).copyWith(fovDeg: v);
                  });
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _popupRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, color: Colors.grey, size: 16),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      const SizedBox(width: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sơ đồ nhà'),
        actions: [
          if (_floorplanImageUrl != null) ...[
            IconButton(
              icon: Icon(_isEditing ? Icons.check : Icons.edit, size: 20),
              tooltip: _isEditing ? 'Lưu' : 'Chỉnh sửa vị trí camera',
              onPressed: () {
                if (_isEditing) {
                  _savePositions();
                } else {
                  setState(() => _isEditing = true);
                }
              },
            ),
          ],
          IconButton(icon: const Icon(Icons.file_upload_outlined, size: 20), tooltip: 'Upload sơ đồ', onPressed: _uploadFloorplan),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadAll),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _floorplanImageUrl == null
          ? _emptyState()
          : _floorplanView(),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Chưa có sơ đồ nhà', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Upload ảnh sơ đồ nhà (floor plan) để đặt vị trí camera và xem event theo vị trí.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _uploadFloorplan,
            icon: const Icon(Icons.file_upload, color: Colors.white),
            label: const Text('Upload sơ đồ', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _floorplanView() {
    return Column(
      children: [
        // Edit mode banner
        if (_isEditing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF007AFF).withOpacity(0.2),
            child: Row(
              children: [
                const Icon(Icons.touch_app, color: Color(0xFF007AFF), size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Kéo camera để đặt vị trí • Nhấn camera để chỉnh góc',
                    style: TextStyle(color: Color(0xFF007AFF), fontSize: 11)),
                ),
                if (_isSaving)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),

        // Floor plan with cameras
        Expanded(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            boundaryMargin: const EdgeInsets.all(100),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                return Stack(
                  children: [
                    // Floor plan image
                    Image.network(
                      _floorplanImageUrl!,
                      headers: _api.authHeaders,
                      fit: BoxFit.contain,
                      width: constraints.maxWidth,
                      errorBuilder: (_, __, ___) => Container(
                        width: constraints.maxWidth,
                        height: constraints.maxWidth * 0.75,
                        color: const Color(0xFF1E2330),
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 48)),
                      ),
                    ),

                    // FOV cones (paint behind icons)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FovPainter(_cameraPositions, constraints.maxWidth, constraints.maxWidth * 0.75),
                      ),
                    ),

                    // Camera icons
                    ..._cameras.map((cam) {
                      final pos = _cameraPositions[cam.id];
                      if (pos == null && !_isEditing) return const SizedBox.shrink();

                      final xPct = pos?.xPct ?? 0.5;
                      final yPct = pos?.yPct ?? 0.5;
                      final hasEvents = (_cameraEventCounts[cam.id] ?? 0) > 0;

                      final x = xPct * constraints.maxWidth - 18;
                      final y = yPct * (constraints.maxWidth * 0.75) - 18;

                      Widget icon = GestureDetector(
                        onTap: () => _showCameraPopup(cam),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: hasEvents
                                      ? const Color(0xFFFF3B30).withOpacity(0.9)
                                      : const Color(0xFF007AFF).withOpacity(0.9),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: hasEvents
                                      ? [BoxShadow(color: const Color(0xFFFF3B30).withOpacity(0.5), blurRadius: 12, spreadRadius: 2)]
                                      : null,
                                  ),
                                  child: const Icon(Icons.videocam, color: Colors.white, size: 18),
                                ),
                                if (hasEvents)
                                  Positioned(
                                    right: -4, top: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
                                      child: Text('${_cameraEventCounts[cam.id]}',
                                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(cam.name, style: const TextStyle(color: Colors.white, fontSize: 8)),
                            ),
                          ],
                        ),
                      );

                      if (_isEditing) {
                        return Positioned(
                          left: x, top: y,
                          child: Draggable(
                            feedback: Opacity(opacity: 0.7, child: Material(color: Colors.transparent, child: icon)),
                            childWhenDragging: Opacity(opacity: 0.3, child: icon),
                            onDragEnd: (details) {
                              final RenderBox box = ctx.findRenderObject() as RenderBox;
                              final localPos = box.globalToLocal(details.offset);
                              final newXPct = (localPos.dx + 18) / constraints.maxWidth;
                              final newYPct = (localPos.dy + 18) / (constraints.maxWidth * 0.75);
                              setState(() {
                                _cameraPositions[cam.id] = (pos ?? _CamPosition()).copyWith(
                                  xPct: newXPct.clamp(0.0, 1.0),
                                  yPct: newYPct.clamp(0.0, 1.0),
                                );
                              });
                            },
                            child: icon,
                          ),
                        );
                      } else {
                        return Positioned(left: x, top: y, child: icon);
                      }
                    }),
                  ],
                );
              },
            ),
          ),
        ),

        // Legend
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF1E2330),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(const Color(0xFF007AFF), 'Bình thường'),
              const SizedBox(width: 16),
              _legendDot(const Color(0xFFFF3B30), 'Có sự kiện'),
              const SizedBox(width: 16),
              Container(width: 20, height: 10, decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withOpacity(0.15),
                border: Border.all(color: const Color(0xFF007AFF).withOpacity(0.4), width: 0.5),
                borderRadius: BorderRadius.circular(2),
              )),
              const SizedBox(width: 4),
              Text('FOV', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10)),
    ],
  );
}

// ==================== FOV Cone Painter ====================

class _FovPainter extends CustomPainter {
  final Map<int, _CamPosition> positions;
  final double canvasW;
  final double canvasH;

  _FovPainter(this.positions, this.canvasW, this.canvasH);

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in positions.entries) {
      final pos = entry.value;
      final cx = pos.xPct * canvasW;
      final cy = pos.yPct * canvasH;
      final rotRad = pos.rotationDeg * pi / 180;
      final halfFov = pos.fovDeg * pi / 360;
      final radius = canvasW * 0.12; // FOV cone length

      final path = Path()
        ..moveTo(cx, cy)
        ..lineTo(cx + radius * cos(rotRad - halfFov), cy + radius * sin(rotRad - halfFov))
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius),
          rotRad - halfFov,
          halfFov * 2,
          false,
        )
        ..close();

      canvas.drawPath(path, Paint()..color = const Color(0xFF007AFF).withOpacity(0.12));
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF007AFF).withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _FovPainter oldDelegate) => true;
}

// ==================== Camera Position Model ====================

class _CamPosition {
  final double xPct;
  final double yPct;
  final double rotationDeg;
  final double fovDeg;

  _CamPosition({this.xPct = 0.5, this.yPct = 0.5, this.rotationDeg = 0, this.fovDeg = 90});

  _CamPosition copyWith({double? xPct, double? yPct, double? rotationDeg, double? fovDeg}) => _CamPosition(
    xPct: xPct ?? this.xPct,
    yPct: yPct ?? this.yPct,
    rotationDeg: rotationDeg ?? this.rotationDeg,
    fovDeg: fovDeg ?? this.fovDeg,
  );
}
