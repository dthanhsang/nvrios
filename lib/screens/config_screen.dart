import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<dynamic> _cameras = [];
  bool _isLoading = true;

  // AI Settings variables
  bool _isLoadingSettings = false;
  bool _isSavingSettings = false;
  bool _isTestingGemini = false;
  Map<String, dynamic> _settings = {};

  final _geminiKeyController = TextEditingController();
  final _geminiModelController = TextEditingController();
  final _aiPromptController = TextEditingController();
  
  final _intervalController = TextEditingController();
  final _cooldownController = TextEditingController();
  
  bool _faceEnabled = false;
  bool _aiEnabled = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCameras();
    _loadSettings();
  }

  @override
  void dispose() {
    _geminiKeyController.dispose();
    _geminiModelController.dispose();
    _aiPromptController.dispose();
    _intervalController.dispose();
    _cooldownController.dispose();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    setState(() {
      _isLoading = true;
    });
    final cameras = await _apiService.getCameras();
    setState(() {
      _cameras = cameras;
      _isLoading = false;
    });
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoadingSettings = true;
    });
    final settings = await _apiService.getSettings();
    if (settings != null && mounted) {
      setState(() {
        _settings = settings;
        _faceEnabled = settings["face_detection_enabled"] == "1";
        _aiEnabled = settings["ai_enabled"] == "1";
        
        _geminiKeyController.text = settings["gemini_api_key"] ?? "";
        _geminiModelController.text = settings["gemini_model"] ?? "gemini-flash-latest";
        _aiPromptController.text = settings["ai_prompt"] ?? "";
        
        _intervalController.text = settings["face_detection_interval"] ?? "5";
        _cooldownController.text = settings["face_detection_cooldown"] ?? "30";
        
        _isLoadingSettings = false;
      });
    } else {
      if (mounted) {
        setState(() => _isLoadingSettings = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSavingSettings = true;
    });
    
    final updated = {
      "face_detection_enabled": _faceEnabled ? "1" : "0",
      "face_detection_interval": _intervalController.text.trim(),
      "face_detection_cooldown": _cooldownController.text.trim(),
      "ai_enabled": _aiEnabled ? "1" : "0",
      "gemini_api_key": _geminiKeyController.text.trim(),
      "gemini_model": _geminiModelController.text.trim(),
      "ai_prompt": _aiPromptController.text.trim(),
      "telegram_bot_token": _settings["telegram_bot_token"] ?? "",
      "telegram_chat_id": _settings["telegram_chat_id"] ?? "",
      "alert_schedule_enabled": _settings["alert_schedule_enabled"] ?? "0",
      "alert_schedule_start": _settings["alert_schedule_start"] ?? "22:00",
      "alert_schedule_end": _settings["alert_schedule_end"] ?? "06:00",
      "alert_mode": _settings["alert_mode"] ?? "always",
      "retention_days": _settings["retention_days"] ?? "7",
    };
    
    final success = await _apiService.updateSettings(updated);
    if (mounted) {
      setState(() {
        _isSavingSettings = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? "Lưu cấu hình thành công!" : "Lỗi khi lưu cấu hình"),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _runTestGemini() async {
    setState(() {
      _isTestingGemini = true;
    });
    
    // Auto save first
    await _saveSettings();
    
    final result = await _apiService.testGemini();
    if (mounted) {
      setState(() {
        _isTestingGemini = false;
      });
      
      if (result != null) {
        final status = result["status"] ?? "error";
        final message = result["message"] ?? "";
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF161920),
            title: Text(status == "success" ? "Kiểm tra thành công" : "Kiểm tra thất bại",
              style: TextStyle(color: status == "success" ? Colors.green : Colors.red),
            ),
            content: SingleChildScrollView(
              child: Text(message, style: const TextStyle(color: Color(0xFFE2E8F0))),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK", style: TextStyle(color: Color(0xFFFF3B30))),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lỗi khi kết nối kiểm tra Gemini"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCameraForm({dynamic camera}) {
    final isEdit = camera != null;
    final nameController = TextEditingController(text: isEdit ? camera['name'] : "");
    final mainUrlController = TextEditingController(text: isEdit ? camera['rtsp_url'] : "rtsp://");
    final subUrlController = TextEditingController(text: isEdit ? (camera['rtsp_url_sub'] ?? "") : "rtsp://");
    final protocolController = TextEditingController(text: isEdit ? camera['protocol'] : "rtsp");
    final srcController = TextEditingController(text: isEdit ? camera['go2rtc_src'] : "");
    bool isEnabled = isEdit ? (camera['enabled'] == 1 || camera['enabled'] == true) : true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161920),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEdit ? "Cấu hình Camera #${camera['id']}" : "Thêm Camera Mới",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                  decoration: const InputDecoration(labelText: "Tên Camera"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mainUrlController,
                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                  decoration: const InputDecoration(labelText: "Đường dẫn RTSP chính (HD)"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subUrlController,
                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                  decoration: const InputDecoration(labelText: "Đường dẫn RTSP phụ (SD) - Tùy chọn"),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: protocolController,
                        style: const TextStyle(color: Color(0xFFE2E8F0)),
                        decoration: const InputDecoration(labelText: "Giao thức"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: srcController,
                        style: const TextStyle(color: Color(0xFFE2E8F0)),
                        decoration: const InputDecoration(
                          labelText: "Nguồn go2rtc (Không dấu/cách)",
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text("Kích hoạt ghi hình & phát", style: TextStyle(color: Color(0xFFE2E8F0))),
                  value: isEnabled,
                  activeColor: const Color(0xFFFF3B30),
                  onChanged: (val) {
                    setModalState(() {
                      isEnabled = val;
                    });
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final data = {
                      "name": nameController.text.trim(),
                      "rtsp_url": mainUrlController.text.trim(),
                      "rtsp_url_sub": subUrlController.text.trim(),
                      "protocol": protocolController.text.trim(),
                      "go2rtc_src": srcController.text.trim(),
                      "enabled": isEnabled ? "1" : "0",
                    };

                    if (data['name']!.isEmpty || data['rtsp_url']!.isEmpty || data['go2rtc_src']!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Vui lòng điền đủ các trường bắt buộc.")),
                      );
                      return;
                    }

                    bool success;
                    if (isEdit) {
                      success = await _apiService.updateCamera(camera['id'], data);
                    } else {
                      success = await _apiService.addCamera(data);
                    }

                    if (success) {
                      Navigator.pop(context);
                      _loadCameras();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isEdit ? "Cập nhật thành công!" : "Thêm mới thành công!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Có lỗi xảy ra, vui lòng thử lại."), backgroundColor: Colors.red),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isEdit ? "Lưu thay đổi" : "Thêm Camera"),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteCamera(int camId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161920),
        title: const Text("Xóa Camera", style: TextStyle(color: Color(0xFFE2E8F0))),
        content: const Text("Bạn có chắc chắn muốn xóa camera này khỏi DVR? Hành động này không thể hoàn tác.",
          style: TextStyle(color: Color(0xFF7E8B9B)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text("Hủy", style: TextStyle(color: Color(0xFF7E8B9B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF3B30)),
            child: const Text("Xóa"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _apiService.deleteCamera(camId);
      if (success) {
        _loadCameras();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đã xóa camera thành công."), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lỗi khi xóa camera."), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Cấu hình thiết bị"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Camera"),
              Tab(text: "Cấu hình AI"),
            ],
            indicatorColor: Color(0xFFFF3B30),
            labelColor: Color(0xFFFF3B30),
            unselectedLabelColor: Color(0xFF7E8B9B),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadCameras();
                _loadSettings();
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // Tab 1: Camera list
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(12.0),
                    itemCount: _cameras.length,
                    itemBuilder: (context, index) {
                      final cam = _cameras[index];
                      final isCamEnabled = cam['enabled'] == 1 || cam['enabled'] == true;

                      return Card(
                        elevation: 2,
                        color: const Color(0xFF161920),
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCamEnabled ? Colors.green.withOpacity(0.2) : const Color(0xFF2A2F3A),
                            child: Icon(
                              isCamEnabled ? Icons.videocam : Icons.videocam_off,
                              color: isCamEnabled ? Colors.green : const Color(0xFF7E8B9B),
                            ),
                          ),
                          title: Text(
                            cam['name'] ?? 'Camera',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0)),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text("Stream: ${cam['go2rtc_src']}", style: const TextStyle(fontSize: 12, color: Color(0xFF7E8B9B))),
                              Text("RTSP: ${cam['rtsp_url']}", style: const TextStyle(fontSize: 11, color: Color(0xFF7E8B9B)), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Color(0xFFFF3B30)),
                                onPressed: () => _showCameraForm(camera: cam),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red[400]),
                                onPressed: () => _deleteCamera(cam['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            
            // Tab 2: AI Settings form
            _isLoadingSettings
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Face detection card
                        Card(
                          color: const Color(0xFF161920),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Phát hiện khuôn mặt (YOLOv8)",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFE2E8F0))),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text("Kích hoạt nhận diện", style: TextStyle(color: Color(0xFFE2E8F0))),
                                  value: _faceEnabled,
                                  activeColor: const Color(0xFFFF3B30),
                                  onChanged: (val) {
                                    setState(() => _faceEnabled = val);
                                  },
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _intervalController,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Color(0xFFE2E8F0)),
                                        decoration: const InputDecoration(
                                          labelText: "Khoảng quét (giây)",
                                          labelStyle: TextStyle(color: Color(0xFF7E8B9B)),
                                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF232731))),
                                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF3B30))),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _cooldownController,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Color(0xFFE2E8F0)),
                                        decoration: const InputDecoration(
                                          labelText: "Thời gian chờ (giây)",
                                          labelStyle: TextStyle(color: Color(0xFF7E8B9B)),
                                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF232731))),
                                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF3B30))),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Gemini AI Analysis card
                        Card(
                          color: const Color(0xFF161920),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Nhận diện người lạ/người quen (AI Gemini)",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFE2E8F0))),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text("Kích hoạt Phân tích AI", style: TextStyle(color: Color(0xFFE2E8F0))),
                                  value: _aiEnabled,
                                  activeColor: const Color(0xFFFF3B30),
                                  onChanged: (val) {
                                    setState(() => _aiEnabled = val);
                                  },
                                ),
                                TextField(
                                  controller: _geminiKeyController,
                                  obscureText: true,
                                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                                  decoration: const InputDecoration(
                                    labelText: "Gemini API Key",
                                    labelStyle: TextStyle(color: Color(0xFF7E8B9B)),
                                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF232731))),
                                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF3B30))),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _geminiModelController,
                                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                                  decoration: const InputDecoration(
                                    labelText: "Gemini Model",
                                    labelStyle: TextStyle(color: Color(0xFF7E8B9B)),
                                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF232731))),
                                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF3B30))),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _aiPromptController,
                                  maxLines: 8,
                                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                                  decoration: const InputDecoration(
                                    labelText: "Prompt phân tích AI",
                                    labelStyle: TextStyle(color: Color(0xFF7E8B9B)),
                                    alignLabelWithHint: true,
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF232731))),
                                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF3B30))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isTestingGemini ? null : _runTestGemini,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFFF3B30)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: _isTestingGemini
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30)),
                                      )
                                    : const Text("Test kết nối Gemini", style: TextStyle(color: Color(0xFFFF3B30))),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isSavingSettings ? null : _saveSettings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF3B30),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: _isSavingSettings
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text("Lưu cấu hình AI"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) {
            // Only show FAB when on the first tab (index 0)
            final TabController tabController = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tabController,
              builder: (context, child) {
                return tabController.index == 0
                    ? FloatingActionButton(
                        onPressed: () => _showCameraForm(),
                        backgroundColor: const Color(0xFFFF3B30),
                        child: const Icon(Icons.add, color: Colors.white),
                      )
                    : const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );
  }
}
