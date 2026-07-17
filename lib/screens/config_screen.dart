import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

  List<String> _profiles = [];
  List<Map<String, dynamic>> _shareLinks = [];
  bool _isLoadingProfiles = false;
  bool _isLoadingShareLinks = false;

  final _intervalCtrl = TextEditingController();
  final _cooldownCtrl = TextEditingController();
  final _geminiKeyCtrl = TextEditingController();
  final _geminiModelCtrl = TextEditingController();
  final _aiBaseUrlCtrl = TextEditingController();
  final _aiApiKeyCtrl = TextEditingController();
  final _aiModelCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  final _tgBotTokenCtrl = TextEditingController();
  final _tgChatIdCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _intervalCtrl.dispose();
    _cooldownCtrl.dispose();
    _geminiKeyCtrl.dispose();
    _geminiModelCtrl.dispose();
    _aiBaseUrlCtrl.dispose();
    _aiApiKeyCtrl.dispose();
    _aiModelCtrl.dispose();
    _promptCtrl.dispose();
    _tgBotTokenCtrl.dispose();
    _tgChatIdCtrl.dispose();
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
        _intervalCtrl.text = _settings['face_detection_interval'] ?? '5';
        _cooldownCtrl.text = _settings['face_detection_cooldown'] ?? '30';
        _geminiKeyCtrl.text = _settings['gemini_api_key'] ?? '';
        _geminiModelCtrl.text = _settings['gemini_model'] ?? 'gemini-flash-latest';
        _aiBaseUrlCtrl.text = _settings['ai_base_url'] ?? '';
        _aiApiKeyCtrl.text = _settings['ai_api_key'] ?? '';
        _aiModelCtrl.text = _settings['ai_model'] ?? 'gemini/gemini-3.1-flash-lite-preview';
        _promptCtrl.text = _settings['ai_prompt'] ?? '';
        _tgBotTokenCtrl.text = _settings['telegram_bot_token'] ?? '';
        _tgChatIdCtrl.text = _settings['telegram_chat_id'] ?? '';
        _isLoading = false;
      });
    }
    _loadFamilyProfiles();
    _loadShareLinks();
  }

  Future<void> _loadFamilyProfiles() async {
    setState(() => _isLoadingProfiles = true);
    final profiles = await _apiService.getFamilyProfiles();
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _isLoadingProfiles = false;
      });
    }
  }

  Future<void> _loadShareLinks() async {
    setState(() => _isLoadingShareLinks = true);
    final shares = await _apiService.getShareLinks();
    if (mounted) {
      setState(() {
        _shareLinks = shares;
        _isLoadingShareLinks = false;
      });
    }
  }

  Future<void> _uploadProfilePhoto() async {
    final picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2330),
        title: const Text('Chọn ảnh từ', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Text('Máy ảnh'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('Thư viện'),
          ),
        ],
      ),
    );

    if (source == null) return;
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80);
    if (pickedFile == null) return;

    if (!mounted) return;
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2330),
        title: const Text('Tên thành viên', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nhập tên (ví dụ: Nguyen Van A)',
            hintStyle: TextStyle(color: Colors.grey),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text),
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;

    setState(() => _isLoading = true);
    final ok = await _apiService.uploadFamilyProfile(pickedFile.path, name.trim());
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Tải lên thành công!' : 'Tải lên thất bại!'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
      _loadFamilyProfiles();
    }
  }

  void _deleteProfile(String filename) {
    final name = filename.replaceAll(RegExp(r'\.[^.]+$'), '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2330),
        title: const Text('Xóa thành viên?', style: TextStyle(color: Colors.white)),
        content: Text('Bạn có chắc chắn muốn xóa thành viên "$name"?', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final ok = await _apiService.deleteFamilyProfile(filename);
              if (mounted) {
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Đã xóa thành công!' : 'Xóa thất bại!'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
                _loadFamilyProfiles();
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Color(0xFFFF3B30))),
          ),
        ],
      ),
    );
  }

  void _showShareLinkForm() {
    if (_cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng thêm camera trước khi tạo link chia sẻ!')),
      );
      return;
    }

    Camera selectedCam = _cameras.first;
    final passwordCtrl = TextEditingController();
    int expiresDays = 0;
    bool allowPlayback = false;

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
                const Text('Tạo liên kết chia sẻ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                DropdownButtonFormField<Camera>(
                  value: selectedCam,
                  dropdownColor: const Color(0xFF1E2330),
                  decoration: const InputDecoration(labelText: 'Chọn camera chia sẻ'),
                  style: const TextStyle(color: Colors.white),
                  items: _cameras.map((c) => DropdownMenuItem(value: c, child: Text(c.name, style: const TextStyle(color: Colors.white)))).toList(),
                  onChanged: (c) {
                    if (c != null) setSheetState(() => selectedCam = c);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu bảo vệ (Tùy chọn)',
                    hintText: 'Để trống nếu không đặt mật khẩu',
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: expiresDays,
                  dropdownColor: const Color(0xFF1E2330),
                  decoration: const InputDecoration(labelText: 'Thời hạn liên kết'),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Không hết hạn', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 1, child: Text('1 ngày', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 3, child: Text('3 ngày', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 7, child: Text('7 ngày', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 30, child: Text('30 ngày', style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (days) {
                    if (days != null) setSheetState(() => expiresDays = days);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Cho phép xem Playback', style: TextStyle(color: Colors.white)),
                  value: allowPlayback,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setSheetState(() => allowPlayback = v),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    setState(() => _isLoading = true);
                    final ok = await _apiService.createShareLink(
                      cameraId: selectedCam.id,
                      password: passwordCtrl.text,
                      expiresDays: expiresDays,
                      allowPlayback: allowPlayback ? 1 : 0,
                    );
                    if (mounted) {
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? 'Tạo link chia sẻ thành công!' : 'Tạo link thất bại!'),
                          backgroundColor: ok ? Colors.green : Colors.red,
                        ),
                      );
                      _loadShareLinks();
                    }
                  },
                  child: const Text('Tạo liên kết'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteShareLink(Map<String, dynamic> share) {
    final int id = share['id'] as int;
    final cameraName = share['camera_name'] ?? 'Camera';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2330),
        title: const Text('Xóa liên kết chia sẻ?', style: TextStyle(color: Colors.white)),
        content: Text('Bạn muốn xóa liên kết chia sẻ cho camera "$cameraName"?', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final ok = await _apiService.deleteShareLink(id);
              if (mounted) {
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Đã xóa liên kết!' : 'Xóa liên kết thất bại!'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
                _loadShareLinks();
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Color(0xFFFF3B30))),
          ),
        ],
      ),
    );
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
                    if (ok && ctx.mounted) {
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
          isScrollable: true,
          tabs: const [
            Tab(text: 'Camera'),
            Tab(text: 'Thành viên'),
            Tab(text: 'Chia sẻ'),
            Tab(text: 'AI'),
            Tab(text: 'Telegram'),
          ],
        ),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: [
              _buildCameraTab(),
              _buildFamilyProfilesTab(),
              _buildShareLinksTab(),
              _buildAiTab(),
              _buildTelegramTab(),
            ],
          ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (_, __) {
          if (_tabController.index == 0) {
            return FloatingActionButton(
              onPressed: () => _showCameraForm(),
              backgroundColor: const Color(0xFFFF3B30),
              child: const Icon(Icons.add),
            );
          } else if (_tabController.index == 1) {
            return FloatingActionButton(
              onPressed: _uploadProfilePhoto,
              backgroundColor: const Color(0xFFFF3B30),
              child: const Icon(Icons.add_a_photo),
            );
          } else if (_tabController.index == 2) {
            return FloatingActionButton(
              onPressed: _showShareLinkForm,
              backgroundColor: const Color(0xFFFF3B30),
              child: const Icon(Icons.share),
            );
          }
          return const SizedBox.shrink();
        },
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
                  TextField(
                    controller: _intervalCtrl,
                    decoration: const InputDecoration(labelText: 'Khoảng cách quét (giây)'),
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cooldownCtrl,
                    decoration: const InputDecoration(labelText: 'Thời gian chờ (giây)'),
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // OpenRouter AI
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('OpenRouter (9router) - Chính', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Bật AI', style: TextStyle(color: Colors.white)),
                    value: aiEnabled,
                    onChanged: (v) => setState(() => _settings['ai_enabled'] = v ? '1' : '0'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  TextField(
                    controller: _aiBaseUrlCtrl,
                    decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://openrouter.ai/api/v1'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _aiApiKeyCtrl,
                    decoration: const InputDecoration(labelText: 'API Key'),
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _aiModelCtrl,
                    decoration: const InputDecoration(labelText: 'Model', hintText: 'gemini/gemini-3.1-flash-lite-preview'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Gemini Backup
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Google Gemini (Dự phòng)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _geminiKeyCtrl,
                    decoration: const InputDecoration(labelText: 'API Key (Dự phòng)'),
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _geminiModelCtrl,
                    decoration: const InputDecoration(labelText: 'Model (Dự phòng)', hintText: 'gemini-flash-latest'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // AI Prompt
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Prompt phân tích hình ảnh', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _promptCtrl,
                    decoration: const InputDecoration(labelText: 'AI Prompt'),
                    style: const TextStyle(color: Colors.white),
                    maxLines: 6,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action Buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _saveAiSettings();
                        final result = await _apiService.testAi();
                        if (mounted) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E2330),
                              title: Text(result?['status'] == 'success' ? '✅ Thành công (OpenRouter)' : '❌ Lỗi (OpenRouter)', style: const TextStyle(color: Colors.white)),
                              content: Text(result?['message'] ?? 'Không thể kết nối hoặc lỗi cấu hình', style: const TextStyle(color: Colors.grey)),
                              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.rocket_launch, size: 16),
                      label: const Text('Test OpenRouter', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal,
                        side: const BorderSide(color: Colors.teal),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _saveAiSettings();
                        final result = await _apiService.testGemini();
                        if (mounted) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E2330),
                              title: Text(result?['status'] == 'ok' ? '✅ Thành công (Gemini)' : '❌ Lỗi (Gemini)', style: const TextStyle(color: Colors.white)),
                              content: Text(result?['message'] ?? 'Không thể kết nối hoặc lỗi cấu hình', style: const TextStyle(color: Colors.grey)),
                              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.psychology, size: 16),
                      label: const Text('Test Gemini', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _saveAiSettings,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Lưu cấu hình'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveAiSettings() async {
    _settings['face_detection_interval'] = _intervalCtrl.text;
    _settings['face_detection_cooldown'] = _cooldownCtrl.text;
    _settings['ai_base_url'] = _aiBaseUrlCtrl.text;
    _settings['ai_api_key'] = _aiApiKeyCtrl.text;
    _settings['ai_model'] = _aiModelCtrl.text;
    _settings['gemini_api_key'] = _geminiKeyCtrl.text;
    _settings['gemini_model'] = _geminiModelCtrl.text;
    _settings['ai_prompt'] = _promptCtrl.text;
    _settings['telegram_bot_token'] = _tgBotTokenCtrl.text;
    _settings['telegram_chat_id'] = _tgChatIdCtrl.text;
    final ok = await _apiService.updateSettings(_settings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Đã lưu cấu hình' : 'Lỗi khi lưu cấu hình')),
      );
    }
  }

  Widget _buildTelegramTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: const Color(0xFF1E2330),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Telegram Bot Alert', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tgBotTokenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Telegram Bot Token',
                      hintText: 'Nhập bot token từ BotFather',
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tgChatIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Telegram Chat ID',
                      hintText: 'Nhập ID nhóm hoặc ID chat cá nhân',
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              await _saveAiSettings();
              final result = await _apiService.testTelegram();
              if (mounted) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E2330),
                    title: Text(result?['status'] == 'success' ? '✅ Thành công' : '❌ Thất bại', style: const TextStyle(color: Colors.white)),
                    content: Text(result?['message'] ?? 'Không thể kết nối hoặc cấu hình sai', style: const TextStyle(color: Colors.grey)),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                  ),
                );
              }
            },
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Gửi tin nhắn test Telegram'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _saveAiSettings,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Lưu cấu hình'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyProfilesTab() {
    if (_isLoadingProfiles) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_profiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Chưa có thành viên gia đình',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Nhấn vào nút ảnh ở góc phải bên dưới để thêm thành viên mới cho AI nhận diện.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFamilyProfiles,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: _profiles.length,
        itemBuilder: (context, idx) {
          final filename = _profiles[idx];
          final name = filename.replaceAll(RegExp(r'\.[^.]+$'), '');
          final photoUrl = _apiService.getFamilyProfilePhotoUrl(filename);

          return Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  photoUrl,
                  headers: _apiService.authHeaders,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.person, size: 48, color: Colors.grey),
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.grey[900],
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  },
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _deleteProfile(filename),
                          child: const Icon(Icons.delete, color: Color(0xFFFF3B30), size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildShareLinksTab() {
    if (_isLoadingShareLinks) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_shareLinks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.share, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Chưa có liên kết chia sẻ',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Nhấn vào nút chia sẻ ở góc phải bên dưới để tạo liên kết truy cập camera tạm thời.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadShareLinks,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _shareLinks.length,
        itemBuilder: (context, i) {
          final share = _shareLinks[i];
          final cameraName = share['camera_name'] ?? 'Camera ID: ${share['camera_id']}';
          final token = share['token'] ?? '';
          final expiresAt = share['expires_at'];
          final allowPlayback = share['allow_playback'] == 1;
          final hasPassword = share['password_hash'] != null && share['password_hash'].toString().isNotEmpty;
          final shareUrl = '${_apiService.baseUrl}/shared/$token';

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cameraName,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Color(0xFFFF3B30), size: 20),
                        onPressed: () => _deleteShareLink(share),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.link, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          shareUrl,
                          style: const TextStyle(color: Colors.blue, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16, color: Colors.blue),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shareUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã sao chép liên kết chia sẻ!')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.grey),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hasPassword ? Icons.lock : Icons.lock_open,
                            size: 14,
                            color: hasPassword ? Colors.orange : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasPassword ? 'Mật khẩu bảo vệ' : 'Không mật khẩu',
                            style: TextStyle(color: hasPassword ? Colors.orange : Colors.grey, fontSize: 11),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            allowPlayback ? Icons.history : Icons.block,
                            size: 14,
                            color: allowPlayback ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            allowPlayback ? 'Có Playback' : 'Chỉ xem Live',
                            style: TextStyle(color: allowPlayback ? Colors.green : Colors.grey, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.timer, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        expiresAt != null ? 'Hết hạn: $expiresAt' : 'Không hết hạn',
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
