import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../models/camera.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _api = ApiService();
  bool _isScanning = false;
  bool _hasScanned = false;
  String? _scanSubnet;
  String? _localIp;
  List<_DiscoveredCamera> _discovered = [];

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _hasScanned = false;
      _discovered = [];
    });

    try {
      final resp = await http.post(
        Uri.parse('${_api.baseUrl}/api/cameras/discover'),
        headers: {..._api.authHeaders, 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        _scanSubnet = data['subnet'] as String?;
        _localIp = data['local_ip'] as String?;
        final cameras = data['cameras'] as List? ?? [];
        _discovered = cameras.map((c) => _DiscoveredCamera.fromJson(c)).toList();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi quét: Server trả về ${resp.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        _hasScanned = true;
      });
    }
  }

  Future<void> _probeCamera(_DiscoveredCamera cam) async {
    setState(() => cam.probeStatus = _ProbeStatus.testing);

    try {
      final resp = await http.post(
        Uri.parse('${_api.baseUrl}/api/cameras/probe'),
        headers: {..._api.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'rtsp_url': cam.rtspUrls.isNotEmpty ? cam.rtspUrls.first : cam.ip}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final success = data['success'] as bool? ?? false;
        setState(() => cam.probeStatus = success ? _ProbeStatus.ok : _ProbeStatus.failed);
      } else {
        setState(() => cam.probeStatus = _ProbeStatus.failed);
      }
    } catch (_) {
      setState(() => cam.probeStatus = _ProbeStatus.failed);
    }
  }

  void _showAddDialog(_DiscoveredCamera cam) {
    final nameController = TextEditingController(text: cam.name.isNotEmpty ? cam.name : 'Camera ${cam.ip}');
    String selectedUrl = cam.rtspUrls.isNotEmpty ? cam.rtspUrls.first : '';
    final go2rtcController = TextEditingController(
      text: cam.name.isNotEmpty
        ? cam.name.toLowerCase().replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '')
        : 'cam_${cam.ip.replaceAll('.', '_')}',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E2330),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Thêm Camera', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecor('Tên camera'),
                ),
                const SizedBox(height: 12),
                const Text('RTSP URL:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                if (cam.rtspUrls.length > 1)
                  ...cam.rtspUrls.map((url) => RadioListTile<String>(
                    value: url,
                    groupValue: selectedUrl,
                    title: Text(url, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    activeColor: const Color(0xFF007AFF),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setDialogState(() => selectedUrl = v!),
                  ))
                else
                  Text(
                    selectedUrl.isNotEmpty ? selectedUrl : 'Không có URL',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: go2rtcController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecor('go2rtc source name'),
                ),
                const SizedBox(height: 8),
                Text('IP: ${cam.ip}', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                if (cam.manufacturer.isNotEmpty)
                  Text('Hãng: ${cam.manufacturer}', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                final success = await _api.addCamera({
                  'name': nameController.text,
                  'rtsp_url': selectedUrl,
                  'rtsp_url_sub': '',
                  'protocol': 'tcp',
                  'go2rtc_src': go2rtcController.text,
                  'enabled': '1',
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(success ? 'Đã thêm camera ${nameController.text}' : 'Lỗi thêm camera')),
                  );
                  if (success) {
                    setState(() => cam.isAdded = true);
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF)),
              child: const Text('Thêm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.grey[500]),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.grey[700]!),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Color(0xFF007AFF)),
      borderRadius: BorderRadius.circular(8),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tìm Camera')),
      body: Column(
        children: [
          // Scan controls
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E2330),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.radar, color: Color(0xFF007AFF), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Quét camera trên mạng LAN',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            _scanSubnet != null ? 'Mạng: $_scanSubnet • IP: $_localIp' : 'Tìm camera ONVIF và RTSP tự động',
                            style: TextStyle(color: Colors.grey[500], fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isScanning ? null : _startScan,
                      icon: _isScanning
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search, size: 18, color: Colors.white),
                      label: Text(_isScanning ? 'Đang quét...' : 'Quét mạng',
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                if (_isScanning) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(
                    backgroundColor: Color(0xFF2A2F3D),
                    valueColor: AlwaysStoppedAnimation(Color(0xFF007AFF)),
                  ),
                ],
              ],
            ),
          ),

          // Results
          Expanded(
            child: !_hasScanned && !_isScanning
              ? _emptyState()
              : _isScanning
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang quét mạng LAN...\nCó thể mất 30-60 giây',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : _discovered.isEmpty
                  ? const Center(child: Text('Không tìm thấy camera nào', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _discovered.length,
                      itemBuilder: (ctx, i) => _cameraCard(_discovered[i]),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.router, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        const Text('Nhấn "Quét mạng" để tìm camera', style: TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 4),
        Text('Hỗ trợ ONVIF, RTSP', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    ),
  );

  Widget _cameraCard(_DiscoveredCamera cam) => Card(
    color: const Color(0xFF1E2330),
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                cam.isAdded ? Icons.check_circle : Icons.videocam,
                color: cam.isAdded ? const Color(0xFF34C759) : const Color(0xFF007AFF),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cam.name.isNotEmpty ? cam.name : cam.ip,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(cam.ip,
                      style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  ],
                ),
              ),
              _probeIndicator(cam.probeStatus),
            ],
          ),
          const SizedBox(height: 8),

          if (cam.manufacturer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.business, color: Colors.grey[600], size: 14),
                  const SizedBox(width: 4),
                  Text(cam.manufacturer, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
            ),

          if (cam.source.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600], size: 14),
                  const SizedBox(width: 4),
                  Text('Phát hiện qua: ${cam.source}', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
            ),

          // RTSP URLs
          if (cam.rtspUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cam.rtspUrls.map((url) => Text(
                  url, style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                )).toList(),
              ),
            ),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: cam.probeStatus == _ProbeStatus.testing ? null : () => _probeCamera(cam),
                icon: cam.probeStatus == _ProbeStatus.testing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check, size: 16),
                label: const Text('Test', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: cam.isAdded ? null : () => _showAddDialog(cam),
                icon: Icon(cam.isAdded ? Icons.check : Icons.add, size: 16, color: Colors.white),
                label: Text(cam.isAdded ? 'Đã thêm' : 'Thêm',
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cam.isAdded ? Colors.grey[700] : const Color(0xFF34C759),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _probeIndicator(_ProbeStatus status) {
    switch (status) {
      case _ProbeStatus.none:
        return const SizedBox.shrink();
      case _ProbeStatus.testing:
        return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
      case _ProbeStatus.ok:
        return const Icon(Icons.check_circle, color: Color(0xFF34C759), size: 22);
      case _ProbeStatus.failed:
        return const Icon(Icons.cancel, color: Color(0xFFFF3B30), size: 22);
    }
  }
}

// ==================== Models ====================

enum _ProbeStatus { none, testing, ok, failed }

class _DiscoveredCamera {
  final String ip;
  final int port;
  String name;
  final String manufacturer;
  final String source; // "ONVIF" or "RTSP scan"
  final List<String> rtspUrls;
  _ProbeStatus probeStatus;
  bool isAdded;

  _DiscoveredCamera({
    required this.ip,
    this.port = 554,
    this.name = '',
    this.manufacturer = '',
    this.source = '',
    this.rtspUrls = const [],
    this.probeStatus = _ProbeStatus.none,
    this.isAdded = false,
  });

  factory _DiscoveredCamera.fromJson(Map<String, dynamic> json) => _DiscoveredCamera(
    ip: json['ip'] as String? ?? '',
    port: json['port'] as int? ?? 554,
    name: json['name'] as String? ?? '',
    manufacturer: json['manufacturer'] as String? ?? '',
    source: json['source'] as String? ?? '',
    rtspUrls: (json['rtsp_urls'] as List?)?.map((e) => e.toString()).toList() ?? [],
  );
}
