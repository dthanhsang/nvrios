import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/camera.dart';
import '../models/face_event.dart';
import 'playback_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<FaceEvent> _events = [];
  List<Camera> _cameras = [];
  int? _filterCameraId;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final cameras = await _apiService.getCameras();
    final events = await _apiService.getFaceEvents(limit: 50, cameraId: _filterCameraId);
    if (mounted) {
      setState(() {
        _cameras = cameras;
        _events = events;
        _isLoading = false;
      });
    }
  }

  void _showEventDetail(FaceEvent event) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E2330),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.face, color: Color(0xFFFF3B30), size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(event.cameraName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close, color: Colors.grey, size: 20), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
              child: Image.network(
                event.imageUrl,
                headers: _apiService.authHeaders,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 200,
                  child: Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 48)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(event.timestamp, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            if (event.details != null) Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
              child: Text(event.details!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    
                    // Trích xuất ngày YYYY-MM-DD từ timestamp (ví dụ "2026-07-17 14:32:05")
                    String? datePart;
                    if (event.timestamp.isNotEmpty) {
                      final parts = event.timestamp.trim().split(' ');
                      if (parts.isNotEmpty) {
                        datePart = parts[0];
                      }
                    }
                    
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaybackScreen(
                          initialCameraId: event.cameraId,
                          initialDate: datePart,
                          initialEventTimestamp: event.timestamp,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_circle_fill, color: Colors.white),
                  label: const Text('Xem video phát lại', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sự kiện')),
      body: Column(
        children: [
          // Camera filter
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('Tất cả', style: TextStyle(fontSize: 12)),
                    selected: _filterCameraId == null,
                    selectedColor: const Color(0xFFFF3B30),
                    backgroundColor: const Color(0xFF1E2330),
                    onSelected: (_) {
                      setState(() => _filterCameraId = null);
                      _loadData();
                    },
                  ),
                ),
                ..._cameras.map((cam) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cam.name, style: const TextStyle(fontSize: 12)),
                    selected: _filterCameraId == cam.id,
                    selectedColor: const Color(0xFFFF3B30),
                    backgroundColor: const Color(0xFF1E2330),
                    onSelected: (_) {
                      setState(() => _filterCameraId = cam.id);
                      _loadData();
                    },
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Events grid
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _events.isEmpty
                ? const Center(child: Text('Không có sự kiện', style: TextStyle(color: Colors.grey)))
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: _events.length,
                      itemBuilder: (context, i) {
                        final event = _events[i];
                        return GestureDetector(
                          onTap: () => _showEventDetail(event),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: const Color(0xFF1E2330),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Image.network(
                                      event.imageUrl,
                                      headers: _apiService.authHeaders,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.broken_image, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(event.cameraName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 2),
                                        Text(
                                          event.timestamp,
                                          style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 10),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
