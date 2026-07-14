import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  Map<String, dynamic> _status = {};
  List<dynamic> _cameraHealth = [];
  bool _isLoading = true;
  String _error = "";

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _error = "";
    });
    try {
      final results = await Future.wait([
        _apiService.getSystemStatus(),
        _apiService.getCameraHealth(),
      ]);

      setState(() {
        _status = results[0] as Map<String, dynamic>;
        _cameraHealth = results[1] as List<dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Không thể kết nối tới máy chủ.\n$e";
        _isLoading = false;
      });
    }
  }

  String _formatBytes(dynamic bytesOpt) {
    if (bytesOpt == null) return "0 B";
    double bytes = 0.0;
    if (bytesOpt is int) bytes = bytesOpt.toDouble();
    else if (bytesOpt is double) bytes = bytesOpt;

    const kb = 1024.0;
    const mb = kb * 1024.0;
    const gb = mb * 1024.0;

    if (bytes >= gb) return "${(bytes / gb).toStringAsFixed(2)} GB";
    if (bytes >= mb) return "${(bytes / mb).toStringAsFixed(2)} MB";
    if (bytes >= kb) return "${(bytes / kb).toStringAsFixed(2)} KB";
    return "${bytes.toStringAsFixed(0)} B";
  }

  Color _getTempColor(double temp) {
    if (temp < 60) return Colors.green;
    if (temp < 75) return Colors.orange;
    return Colors.red;
  }

  Color _getUsageColor(double percent) {
    if (percent < 70) return Colors.green;
    if (percent < 85) return Colors.orange;
    return Colors.red;
  }

  Color _getRecordingStatusColor(String status) {
    switch (status) {
      case "recording":
        return Colors.green;
      case "connecting":
        return Colors.orange;
      case "error":
        return Colors.red;
      default:
        return const Color(0xFF7E8B9B);
    }
  }

  String _getRecordingStatusText(String status) {
    switch (status) {
      case "recording":
        return "Đang ghi hình";
      case "connecting":
        return "Đang kết nối";
      case "error":
        return "Lỗi kết nối";
      default:
        return "Đã tắt";
    }
  }

  Future<void> _restartDVR() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161920),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Khởi động lại DVR",
          style: TextStyle(color: Color(0xFFE2E8F0))),
        content: const Text(
          "Bạn có chắc chắn muốn khởi động lại dịch vụ đầu ghi DVR?",
          style: TextStyle(color: Color(0xFF7E8B9B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Hủy", style: TextStyle(color: Color(0xFF7E8B9B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF3B30)),
            child: const Text("Khởi động lại"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final success = await _apiService.restartDvr();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? "Đã gửi yêu cầu khởi động lại!"
                : "Lỗi gửi yêu cầu khởi động lại!"),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
      // Wait a moment for restart
      await Future.delayed(const Duration(seconds: 4));
      _loadStatus();
    }
  }

  Future<void> _cleanupFaces() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161920),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Dọn dẹp ảnh khuôn mặt",
          style: TextStyle(color: Color(0xFFE2E8F0))),
        content: const Text(
          "Bạn có chắc chắn muốn dọn dẹp các tệp ảnh nhận diện khuôn mặt cũ không?",
          style: TextStyle(color: Color(0xFF7E8B9B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Hủy", style: TextStyle(color: Color(0xFF7E8B9B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF3B30)),
            child: const Text("Dọn dẹp"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final success = await _apiService.cleanupFaces();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? "Dọn dẹp hoàn tất!"
                : "Dọn dẹp thất bại!"),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
      _loadStatus();
    }
  }

  void _showLogs() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Color(0xFF0F1115),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Nhật ký hệ thống (Logs)",
                  style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFFE2E8F0)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2A2F3A)),
            Expanded(
              child: FutureBuilder<String>(
                future: _apiService.getSystemLogs(limit: 250),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)));
                  }
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text("Không thể tải nhật ký.",
                        style: TextStyle(color: Color(0xFF7E8B9B))),
                    );
                  }
                  return SingleChildScrollView(
                    child: Text(
                      snapshot.data!,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  );
                },
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
      appBar: AppBar(
        title: const Text("Giám sát hệ thống"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadStatus),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : _error.isNotEmpty
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _loadStatus,
                  color: const Color(0xFFFF3B30),
                  child: _buildHealthContent(),
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
            Text(_error, textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE2E8F0))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadStatus,
              icon: const Icon(Icons.refresh),
              label: const Text("Tải lại"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthContent() {
    final cpuLoad = _status['cpu_load'] as List<dynamic>? ?? [0.0, 0.0, 0.0];
    final cpuTemp = (_status['cpu_temp'] as num?)?.toDouble() ?? 0.0;
    final ram = _status['ram'] as Map<String, dynamic>? ?? {};
    final ramPercent = (ram['percent'] as num?)?.toDouble() ?? 0.0;
    final disk = _status['disk'] as Map<String, dynamic>? ?? {};
    final diskPercent = (disk['percent'] as num?)?.toDouble() ?? 0.0;
    final network = _status['network'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Camera Health Status Card
        if (_cameraHealth.isNotEmpty) ...[
          _buildSectionHeader("Trạng thái Camera"),
          ..._cameraHealth.map((cam) {
            final recStatus = cam['recording_status']?.toString() ?? 'disabled';
            final statusColor = _getRecordingStatusColor(recStatus);
            final statusText = _getRecordingStatusText(recStatus);
            final faceText = cam['face_detection'] == 'active' ? 'Có' : 'Không';

            return Card(
              color: const Color(0xFF161920),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.videocam, color: statusColor, size: 22),
                title: Text(cam['name'] ?? 'Camera',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0))),
                subtitle: Text("Face detection: $faceText \u2022 PID: ${cam['pid'] ?? '-'}",
                  style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        _buildSectionHeader("Tài nguyên máy chủ"),

        // CPU Card
        _buildCard(
          icon: Icons.developer_board,
          iconColor: const Color(0xFFFF3B30),
          title: "Bộ xử lý (CPU)",
          children: [
            _buildInfoRow("Tải hệ thống",
              "1p: ${cpuLoad.isNotEmpty ? cpuLoad[0] : 0} | 5p: ${cpuLoad.length > 1 ? cpuLoad[1] : 0} | 15p: ${cpuLoad.length > 2 ? cpuLoad[2] : 0}"),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Nhiệt độ:", style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getTempColor(cpuTemp).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text("$cpuTemp \u00B0C",
                    style: TextStyle(color: _getTempColor(cpuTemp), fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // RAM Card
        _buildCard(
          icon: Icons.memory,
          iconColor: Colors.purple,
          title: "Bộ nhớ (RAM)",
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${ramPercent.toStringAsFixed(1)}%",
                  style: TextStyle(color: _getUsageColor(ramPercent), fontWeight: FontWeight.bold, fontSize: 16)),
                Text("${_formatBytes(ram['used'])} / ${_formatBytes(ram['total'])}",
                  style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ramPercent / 100,
                minHeight: 6,
                backgroundColor: const Color(0xFF2A2F3A),
                valueColor: AlwaysStoppedAnimation<Color>(_getUsageColor(ramPercent)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Disk Card
        _buildCard(
          icon: Icons.storage,
          iconColor: Colors.orange,
          title: "Lưu trữ Camera",
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${diskPercent.toStringAsFixed(1)}%",
                  style: TextStyle(color: _getUsageColor(diskPercent), fontWeight: FontWeight.bold, fontSize: 16)),
                Text("${_formatBytes(disk['used'])} / ${_formatBytes(disk['total'])}",
                  style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: diskPercent / 100,
                minHeight: 6,
                backgroundColor: const Color(0xFF2A2F3A),
                valueColor: AlwaysStoppedAnimation<Color>(_getUsageColor(diskPercent)),
              ),
            ),
            const SizedBox(height: 4),
            Text("Còn trống: ${_formatBytes(disk['free'])}",
              style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 11)),
          ],
        ),
        const SizedBox(height: 10),

        // Network Card
        _buildCard(
          icon: Icons.network_check,
          iconColor: Colors.teal,
          title: "Lưu lượng mạng",
          children: [
            _buildInfoRow("Nhận (Rx)", _formatBytes(network['rx_bytes'])),
            const SizedBox(height: 6),
            _buildInfoRow("Gửi (Tx)", _formatBytes(network['tx_bytes'])),
          ],
        ),
        const SizedBox(height: 16),

        // Action buttons
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showLogs,
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text("Xem Logs"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFF1E2330),
                      foregroundColor: const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _restartDVR,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text("Khởi động lại"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFFF3B30),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _cleanupFaces,
                icon: const Icon(Icons.cleaning_services, size: 18),
                label: const Text("Dọn dẹp ảnh khuôn mặt"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: const Color(0xFF1E2330),
                  foregroundColor: const Color(0xFF7E8B9B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF7E8B9B),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161920),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF232731)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0))),
            ],
          ),
          const Divider(color: Color(0xFF2A2F3A), height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13)),
        Text(value, style: const TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w500, fontSize: 13)),
      ],
    );
  }
}
