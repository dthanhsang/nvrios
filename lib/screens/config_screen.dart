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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCameras();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cấu hình thiết bị"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCameras,
          ),
        ],
      ),
      body: _isLoading
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCameraForm(),
        backgroundColor: const Color(0xFFFF3B30),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
