import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/camera.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final _apiService = ApiService();
  late TabController _tabController;
  List<Camera> _cameras = [];
  Map<String, dynamic> _settings = {};
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final cameras = await _apiService.getCameras();
    final settings = await _apiService.getSettings();
    if (mounted) {
      setState(() {
        _cameras = cameras;
        _settings = settings ?? {};
        _isLoading = false;
      });
    }
  }

  void _showCameraForm({Camera? camera}) {
    final nameCtrl = TextEditingController(text: camera?.name ?? '');
    final rtspCtrl = TextEditingController(text: camera?.rtspUrl ?? '');
    final rtspSubCtrl = TextEditingController(text: camera?.rtspUrlSub ?? '');
    final srcCtrl = TextEditingController(text: camera?.go2rtcSrc ?? '');
    String protocol = camera?.protocol ?? 'tcp';
    bool enabled = camera?.enabled ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2330),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(camera == null ? 'Thêm Camera' : 'Sửa Camera', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên camera'), style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                TextField(controller: rtspCtrl, decoration: const InputDecoration(labelText: 'RTSP URL (HD)'), style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                TextField(controller: rtspSubCtrl, decoration: const InputDecoration(labelText: 'RTSP URL Sub (SD)'), style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                TextField(controller: srcCtrl, decoration: const InputDecoration(labelText: 'go2rtc Source'), style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: protocol,
                  dropdownColor: const Color(0xFF1E2330),
                  decoration: const InputDecoration(labelText: 'Protocol'),
                  items: const [
                    DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                    DropdownMenuItem(value: 'udp', child: Text('UDP')),
                  ],
                  onChanged: (v) => setSheetState(() => protocol = v ?? 'tcp'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Kích hoạt', style: TextStyle(color: Colors.white)),
                  value: enabled,
                  onChanged: (v) => setSheetState(() => enabled = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final data = {
                      'name': nameCtrl.text,
                      'rtsp_url': rtspCtrl.text,
                      'rtsp_url_sub': rtspSubCtrl.text,
                      'protocol': protocol,
                      'go2rtc_src': srcCtrl.text,
                      'enabled': enabled ? '1' : '0',
                    };
                    bool ok;
                    if (camera != null) {
                      ok = await _apiService.updateCamera(camera.id, data);
                    } else {
                      ok = await _apiService.addCamera(data);
                    }
                    if (ok && mounted) {
                      Navigator.pop(ctx);
                      _loadData();
                    }
                  },
                  child: Text(camera == null ? 'Thêm' : 'Cập nhật'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteCamera(Camera camera) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2330),
        title: const Text('Xóa camera?', style: TextStyle(color: Colors.white)),
        content: Text('Xóa "${camera.name}" và tất cả bản ghi?', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _apiService.deleteCamera(camera.id);
              _loadData();
            },
            child: const Text('Xóa', style: TextStyle(color: Color(0xFFFF3B30))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF3B30),
          labelColor: const Color(0xFFFF3B30),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Camera'),
            Tab(text: 'AI'),
          ],
        ),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: [
              _buildCameraTab(),
              _buildAiTab(),
            ],
          ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (_, __) => _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () => _showCameraForm(),
              backgroundColor: const Color(0xFFFF3B30),
              child: const Icon(Icons.add),
            )
          : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildCameraTab() {
    if (_cameras.isEmpty) {
      return const Center(child: Text('Chưa có camera nào', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _cameras.length,
        itemBuilder: (context, i) {
          final cam = _cameras[i];
          return Card(
            child: ListTile(
              leading: Icon(
                Icons.videocam,
                color: cam.enabled ? const Color(0xFFFF3B30) : Colors.grey,
              ),
              title: Text(cam.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${cam.go2rtcSrc} • ${cam.protocol.toUpperCase()}',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showCameraForm(camera: cam)),
                  IconButton(icon: const Icon(Icons.delete, size: 20, color: Color(0xFFFF3B30)), onPressed: () => _deleteCamera(cam)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAiTab() {
    final faceEnabled = _settings['face_detection_enabled'] == '1';
    final aiEnabled = _settings['ai_enabled'] == '1';
    final intervalCtrl = TextEditingController(text: _settings['face_detection_interval'] ?? '5');
    final cooldownCtrl = TextEditingController(text: _settings['face_detection_cooldown'] ?? '30');
    final geminiKeyCtrl = TextEditingController(text: _settings['gemini_api_key'] ?? '');
    final geminiModelCtrl = TextEditingController(text: _settings['gemini_model'] ?? 'gemini-flash-latest');
    final promptCtrl = TextEditingController(text: _settings['ai_prompt'] ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Face Detection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Phát hiện khuôn mặt (YOLOv8)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Bật phát hiện', style: TextStyle(color: Colors.white)),
                    value: faceEnabled,
                    onChanged: (v) => setState(() => _settings['face_detection_enabled'] = v ? '1' : '0'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  TextField(controller: intervalCtrl, decoration: const InputDecoration(labelText: 'Khoảng cách quét (giây)'), style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number),
                  const SizedBox(height: 8),
                  TextField(controller: cooldownCtrl, decoration: const InputDecoration(labelText: 'Thời gian chờ (giây)'), style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // AI Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gemini AI', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Bật AI', style: TextStyle(color: Colors.white)),
                    value: aiEnabled,
                    onChanged: (v) => setState(() => _settings['ai_enabled'] = v ? '1' : '0'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  TextField(controller: geminiKeyCtrl, decoration: const InputDecoration(labelText: 'API Key'), style: const TextStyle(color: Colors.white), obscureText: true),
                  const SizedBox(height: 8),
                  TextField(controller: geminiModelCtrl, decoration: const InputDecoration(labelText: 'Model'), style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 8),
                  TextField(controller: promptCtrl, decoration: const InputDecoration(labelText: 'AI Prompt'), style: const TextStyle(color: Colors.white), maxLines: 5),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // Save first, then test
                    await _saveAiSettings(intervalCtrl, cooldownCtrl, geminiKeyCtrl, geminiModelCtrl, promptCtrl);
                    final result = await _apiService.testGemini();
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E2330),
                          title: Text(result?['status'] == 'ok' ? '✅ Thành công' : '❌ Lỗi', style: const TextStyle(color: Colors.white)),
                          content: Text(result?['message'] ?? 'Không thể kết nối', style: const TextStyle(color: Colors.grey)),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Test Gemini'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _saveAiSettings(intervalCtrl, cooldownCtrl, geminiKeyCtrl, geminiModelCtrl, promptCtrl),
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Lưu'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveAiSettings(
    TextEditingController interval, TextEditingController cooldown,
    TextEditingController key, TextEditingController model, TextEditingController prompt,
  ) async {
    _settings['face_detection_interval'] = interval.text;
    _settings['face_detection_cooldown'] = cooldown.text;
    _settings['gemini_api_key'] = key.text;
    _settings['gemini_model'] = model.text;
    _settings['ai_prompt'] = prompt.text;
    final ok = await _apiService.updateSettings(_settings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Đã lưu cấu hình' : 'Lỗi khi lưu')),
      );
    }
  }
}
