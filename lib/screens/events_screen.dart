import 'package:flutter/material.dart';
import '../services/api_service.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<dynamic> _events = [];
  Map<int, String> _cameraNames = {};
  bool _isLoading = true;
  String? _error;
  int _limit = 50;
  int? _selectedCamId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load camera names first
      final cameras = await _apiService.getCameras();
      final Map<int, String> names = {};
      for (var cam in cameras) {
        if (cam['id'] != null) {
          names[cam['id']] = cam['name'] ?? 'Camera ${cam['id']}';
        }
      }

      final events = await _apiService.getFaceEvents(limit: _limit, cameraId: _selectedCamId);

      setState(() {
        _cameraNames = names;
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshEvents() async {
    try {
      final events = await _apiService.getFaceEvents(limit: _limit, cameraId: _selectedCamId);
      setState(() {
        _events = events;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi tải lại: $e"), backgroundColor: Colors.red),
      );
    }
  }

  String _getCameraName(dynamic camIdOpt) {
    if (camIdOpt == null) return "Không rõ";
    int? camId;
    if (camIdOpt is String) camId = int.tryParse(camIdOpt);
    else if (camIdOpt is int) camId = camIdOpt;

    if (camId != null && _cameraNames.containsKey(camId)) {
      return _cameraNames[camId]!;
    }
    return "Camera $camIdOpt";
  }

  Map<String, String> _getImageHeaders() {
    return _apiService.authHeaders;
  }

  void _showImageDialog(dynamic event) {
    final base = _apiService.baseUrl;
    final imageUrl = "$base${event['url']}";
    final cameraName = _getCameraName(event['camera_id']);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF161920),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E2330),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.face, color: Color(0xFFFF3B30), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "$cameraName \u2022 ${event['time'] ?? ''}",
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF7E8B9B), size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Image
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  headers: _getImageHeaders(),
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30))),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image, size: 48, color: Color(0xFF7E8B9B)),
                            SizedBox(height: 8),
                            Text("Không thể tải ảnh",
                              style: TextStyle(color: Color(0xFF7E8B9B))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Footer info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: Color(0xFF7E8B9B), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    "${event['date'] ?? ''} ${event['time'] ?? ''}",
                    style: const TextStyle(fontSize: 13, color: Color(0xFF7E8B9B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraSelector() {
    if (_cameraNames.isEmpty) return const SizedBox.shrink();
    
    final camIds = [null, ..._cameraNames.keys];
    
    return Container(
      height: 44,
      color: const Color(0xFF161920),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: camIds.length,
        itemBuilder: (context, index) {
          final camId = camIds[index];
          final isActive = camId == _selectedCamId;
          final label = camId == null ? "Tất cả" : (_cameraNames[camId] ?? 'Camera $camId');
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCamId = camId;
                });
                _loadInitialData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFFF3B30) : const Color(0xFF1E2330),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive ? const Color(0xFFFF3B30) : const Color(0xFF2A3142),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(camId == null ? Icons.all_inclusive : Icons.videocam, size: 14,
                      color: isActive ? Colors.white : const Color(0xFF7E8B9B)),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: isActive ? Colors.white : const Color(0xFF7E8B9B),
                        fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Nhận diện khuôn mặt"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCameraSelector(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
                : _error != null
                    ? _buildErrorView()
                    : _events.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _refreshEvents,
                            color: const Color(0xFFFF3B30),
                            child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final ev = _events[index];
                          final base = _apiService.baseUrl;
                          final imageUrl = "$base${ev['url']}";
                          final cameraName = _getCameraName(ev['camera_id']);

                          return GestureDetector(
                            onTap: () => _showImageDialog(ev),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF161920),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF232731)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Container(
                                      color: const Color(0xFF1E2330),
                                      child: Image.network(
                                        imageUrl,
                                        headers: _getImageHeaders(),
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, progress) {
                                          if (progress == null) return child;
                                          return const Center(
                                            child: CircularProgressIndicator(
                                              color: Color(0xFFFF3B30), strokeWidth: 2),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Center(
                                            child: Icon(Icons.person, size: 40, color: Color(0xFF7E8B9B)),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cameraName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 12,
                                            color: Color(0xFFE2E8F0),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              ev['time'] ?? '',
                                              style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                            Text(
                                              ev['date'] ?? '',
                                              style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text("Lỗi tải sự kiện:\n$_error", textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE2E8F0))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh),
              label: const Text("Tải lại"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.face_retouching_off, size: 64, color: Color(0xFF7E8B9B)),
          const SizedBox(height: 16),
          const Text("Không có sự kiện khuôn mặt nào gần đây.",
            style: TextStyle(color: Color(0xFF7E8B9B), fontSize: 15),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadInitialData,
            icon: const Icon(Icons.refresh),
            label: const Text("Tải lại"),
          ),
        ],
      ),
    );
  }
}
