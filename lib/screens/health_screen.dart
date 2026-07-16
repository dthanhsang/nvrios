import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _cameraHealth = [];
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
    final status = await _apiService.getSystemStatus();
    final health = await _apiService.getCameraHealth();
    if (mounted) {
      setState(() {
        _status = status;
        _cameraHealth = health;
        _isLoading = false;
      });
    }
  }

  Color _usageColor(double ratio) {
    if (ratio < 0.7) return Colors.green;
    if (ratio < 0.85) return Colors.orange;
    return Colors.red;
  }

  Color _tempColor(double temp) {
    if (temp < 60) return Colors.green;
    if (temp < 75) return Colors.orange;
    return Colors.red;
  }

  void _showLogs() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1115),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => FutureBuilder<String>(
          future: _apiService.getSystemLogs(limit: 250),
          builder: (_, snap) => Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('System Logs', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: snap.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        snap.data ?? 'No logs',
                        style: const TextStyle(color: Colors.green, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hệ thống')),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Camera Health
                ..._cameraHealth.map((cam) {
                  final status = cam['status'] as String? ?? 'unknown';
                  final name = cam['name'] as String? ?? 'Camera';
                  Color statusColor;
                  IconData statusIcon;
                  switch (status) {
                    case 'recording': statusColor = Colors.green; statusIcon = Icons.fiber_manual_record; break;
                    case 'connecting': statusColor = Colors.orange; statusIcon = Icons.sync; break;
                    case 'error': statusColor = Colors.red; statusIcon = Icons.error; break;
                    case 'disabled': statusColor = Colors.grey; statusIcon = Icons.block; break;
                    default: statusColor = Colors.grey; statusIcon = Icons.help; break;
                  }
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.videocam, color: statusColor),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      trailing: Icon(statusIcon, color: statusColor, size: 16),
                    ),
                  );
                }),
                const SizedBox(height: 12),

                // System resources
                if (_status != null) ...[
                  _buildResourceCard('CPU', Icons.memory, _status!),
                  const SizedBox(height: 8),
                  _buildRamCard(),
                  const SizedBox(height: 8),
                  _buildDiskCard(),
                ],
                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showLogs,
                        icon: const Icon(Icons.description, size: 18),
                        label: const Text('Logs'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.green, side: const BorderSide(color: Colors.green)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E2330),
                              title: const Text('Khởi động lại?', style: TextStyle(color: Colors.white)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK', style: TextStyle(color: Color(0xFFFF3B30)))),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await _apiService.restartDvr();
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang khởi động lại...')));
                          }
                        },
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Restart'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await _apiService.cleanupFaces();
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Đã dọn dẹp' : 'Lỗi')));
                        },
                        icon: const Icon(Icons.cleaning_services, size: 18),
                        label: const Text('Dọn ảnh'),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF3B30), side: const BorderSide(color: Color(0xFFFF3B30))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildResourceCard(String title, IconData icon, Map<String, dynamic> status) {
    final cpuLoad = status['cpu_load'] as List<dynamic>? ?? [];
    final load1 = cpuLoad.isNotEmpty ? (cpuLoad[0] as num).toDouble() : 0.0;
    final temp = (status['cpu_temp'] as num?)?.toDouble() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: _tempColor(temp), size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('Load: ${load1.toStringAsFixed(2)} • Temp: ${temp.toStringAsFixed(0)}°C',
                    style: TextStyle(color: _tempColor(temp), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRamCard() {
    final ram = _status?['ram'] as Map<String, dynamic>? ?? {};
    final totalBytes = (ram['total'] as num?)?.toDouble() ?? 0;
    final usedBytes = (ram['used'] as num?)?.toDouble() ?? 0;
    final total = totalBytes / (1024 * 1024 * 1024);
    final used = usedBytes / (1024 * 1024 * 1024);
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sd_card, color: _usageColor(ratio), size: 28),
                const SizedBox(width: 14),
                const Text('RAM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${used.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} GB', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: ratio, backgroundColor: Colors.grey[800], valueColor: AlwaysStoppedAnimation(_usageColor(ratio))),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskCard() {
    final disk = _status?['disk'] as Map<String, dynamic>? ?? {};
    final totalBytes = (disk['total'] as num?)?.toDouble() ?? 0;
    final usedBytes = (disk['used'] as num?)?.toDouble() ?? 0;
    final freeBytes = (disk['free'] as num?)?.toDouble() ?? 0;
    final totalGb = totalBytes / (1024 * 1024 * 1024);
    final usedGb = usedBytes / (1024 * 1024 * 1024);
    final freeGb = freeBytes / (1024 * 1024 * 1024);
    final ratio = totalGb > 0 ? (usedGb / totalGb).clamp(0.0, 1.0) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: _usageColor(ratio), size: 28),
                const SizedBox(width: 14),
                const Text('Disk', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${usedGb.toStringAsFixed(1)} / ${totalGb.toStringAsFixed(1)} GB (Free: ${freeGb.toStringAsFixed(1)} GB)', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: ratio, backgroundColor: Colors.grey[800], valueColor: AlwaysStoppedAnimation(_usageColor(ratio))),
          ],
        ),
      ),
    );
  }
}
