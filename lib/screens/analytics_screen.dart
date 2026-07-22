import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/offline_cache_service.dart';
import '../models/camera.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  final _cache = OfflineCacheService();

  List<Camera> _cameras = [];
  int? _selectedCamId;
  DateTime _selectedDate = DateTime.now();
  String _dateRangeLabel = '7 ngày qua';
  int _rangeDays = 7;

  bool _isLoading = true;
  bool _isOffline = false;

  // Data
  Map<String, dynamic> _summary = {};
  List<int> _hourlyData = List.filled(24, 0);
  List<Map<String, dynamic>> _dailyData = [];
  List<Map<String, dynamic>> _heatmapData = [];
  String? _snapshotUrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    _isOffline = !(await _cache.isOnline());

    await Future.wait([
      _loadCameras(),
      _loadSummary(),
      _loadHourly(),
      _loadDaily(),
      _loadHeatmap(),
    ]);

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadCameras() async {
    try {
      _cameras = await _api.getCameras();
      if (_cameras.isNotEmpty) {
        await _cache.cacheData(_cache.cameraListKey(), _cameras.map((c) => {'id': c.id, 'name': c.name, 'go2rtc_src': c.go2rtcSrc}).toList());
      }
    } catch (_) {
      final cached = await _cache.getCachedData(_cache.cameraListKey());
      if (cached is List) {
        // minimal restore for dropdown
        _cameras = cached.map((c) => Camera(id: c['id'], name: c['name'], rtspUrl: '', protocol: 'tcp', go2rtcSrc: c['go2rtc_src'] ?? '', enabled: true)).toList();
      }
    }
  }

  String _camParam() => _selectedCamId != null ? 'cam_id=$_selectedCamId' : '';

  Future<void> _loadSummary() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final from = DateFormat('yyyy-MM-dd').format(_selectedDate.subtract(Duration(days: _rangeDays)));
    try {
      final resp = await http.get(
        Uri.parse('${_api.baseUrl}/api/analytics/summary?${_camParam()}&from=$from&to=$dateStr'),
        headers: _api.authHeaders,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        _summary = jsonDecode(utf8.decode(resp.bodyBytes));
        await _cache.cacheData(_cache.analyticsSummaryKey(_selectedCamId), _summary);
        return;
      }
    } catch (_) {}
    final cached = await _cache.getCachedData(_cache.analyticsSummaryKey(_selectedCamId));
    if (cached is Map) _summary = Map<String, dynamic>.from(cached);
  }

  Future<void> _loadHourly() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final resp = await http.get(
        Uri.parse('${_api.baseUrl}/api/analytics/hourly?${_camParam()}&date=$dateStr'),
        headers: _api.authHeaders,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        if (data['hours'] is List) {
          _hourlyData = List<int>.from(data['hours']);
        }
        return;
      }
    } catch (_) {}
  }

  Future<void> _loadDaily() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final from = DateFormat('yyyy-MM-dd').format(_selectedDate.subtract(Duration(days: _rangeDays)));
    try {
      final resp = await http.get(
        Uri.parse('${_api.baseUrl}/api/analytics/daily?${_camParam()}&from=$from&to=$dateStr'),
        headers: _api.authHeaders,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        if (data['days'] is List) {
          _dailyData = List<Map<String, dynamic>>.from(data['days']);
        }
        return;
      }
    } catch (_) {}
  }

  Future<void> _loadHeatmap() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final resp = await http.get(
        Uri.parse('${_api.baseUrl}/api/analytics/heatmap?${_camParam()}&date=$dateStr'),
        headers: _api.authHeaders,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        if (data['boxes'] is List) {
          _heatmapData = List<Map<String, dynamic>>.from(data['boxes']);
        }
        _snapshotUrl = data['snapshot_url'] as String?;
        return;
      }
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: Color(0xFFFF3B30), surface: Color(0xFF1E2330)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê'),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today, size: 20), onPressed: _pickDate),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadAll),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadAll,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Offline banner
                if (_isOffline) _offlineBanner(),

                // Camera filter chips
                _cameraFilter(),
                const SizedBox(height: 8),

                // Date range selector
                _dateRangeSelector(),
                const SizedBox(height: 16),

                // Summary cards
                _summaryCards(),
                const SizedBox(height: 20),

                // Hourly bar chart
                _sectionTitle('Sự kiện theo giờ', Icons.bar_chart),
                const SizedBox(height: 8),
                _hourlyChart(),
                const SizedBox(height: 20),

                // Daily trend
                _sectionTitle('Xu hướng theo ngày', Icons.show_chart),
                const SizedBox(height: 8),
                _dailyChart(),
                const SizedBox(height: 20),

                // Heatmap
                _sectionTitle('Heatmap vùng phát hiện', Icons.grain),
                const SizedBox(height: 8),
                _heatmapView(),
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _offlineBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
    child: const Row(
      children: [
        Icon(Icons.wifi_off, color: Colors.orange, size: 18),
        SizedBox(width: 8),
        Text('Đang offline — hiện dữ liệu đã lưu', style: TextStyle(color: Colors.orange, fontSize: 12)),
      ],
    ),
  );

  Widget _cameraFilter() => SizedBox(
    height: 38,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: const Text('Tất cả', style: TextStyle(fontSize: 12)),
            selected: _selectedCamId == null,
            selectedColor: const Color(0xFFFF3B30),
            backgroundColor: const Color(0xFF1E2330),
            onSelected: (_) { setState(() => _selectedCamId = null); _loadAll(); },
          ),
        ),
        ..._cameras.map((cam) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(cam.name, style: const TextStyle(fontSize: 12)),
            selected: _selectedCamId == cam.id,
            selectedColor: const Color(0xFFFF3B30),
            backgroundColor: const Color(0xFF1E2330),
            onSelected: (_) { setState(() => _selectedCamId = cam.id); _loadAll(); },
          ),
        )),
      ],
    ),
  );

  Widget _dateRangeSelector() => SizedBox(
    height: 32,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final entry in [('Hôm nay', 0), ('7 ngày', 7), ('30 ngày', 30)])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(entry.$1, style: const TextStyle(fontSize: 11)),
              selected: _rangeDays == entry.$2,
              selectedColor: const Color(0xFF007AFF),
              backgroundColor: const Color(0xFF1E2330),
              labelStyle: TextStyle(
                color: _rangeDays == entry.$2 ? Colors.white : Colors.grey[400],
                fontSize: 11,
              ),
              onSelected: (_) {
                setState(() {
                  _rangeDays = entry.$2;
                  _dateRangeLabel = entry.$1;
                });
                _loadAll();
              },
            ),
          ),
      ],
    ),
  );

  Widget _summaryCards() {
    final total = _summary['total_events'] ?? 0;
    final strangers = _summary['strangers'] ?? 0;
    final family = _summary['family'] ?? 0;
    final passerby = _summary['passerby'] ?? 0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: [
        _summaryCard('Tổng sự kiện', '$total', Icons.event, const Color(0xFF007AFF)),
        _summaryCard('Người lạ', '$strangers', Icons.warning_amber, const Color(0xFFFF3B30)),
        _summaryCard('Gia đình', '$family', Icons.home, const Color(0xFF34C759)),
        _summaryCard('Đi đường', '$passerby', Icons.directions_walk, Colors.grey),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1E2330),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ],
        ),
      ],
    ),
  );

  Widget _sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, color: const Color(0xFFFF3B30), size: 18),
      const SizedBox(width: 6),
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
    ],
  );

  // ==================== Hourly Bar Chart (CustomPainter) ====================

  Widget _hourlyChart() {
    final maxVal = _hourlyData.reduce(max).clamp(1, 999999);
    return Container(
      height: 180,
      decoration: BoxDecoration(color: const Color(0xFF1E2330), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: CustomPaint(
        size: const Size(double.infinity, 160),
        painter: _HourlyBarPainter(_hourlyData, maxVal),
      ),
    );
  }

  // ==================== Daily Trend Line Chart (CustomPainter) ====================

  Widget _dailyChart() {
    if (_dailyData.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(color: const Color(0xFF1E2330), borderRadius: BorderRadius.circular(12)),
        child: const Center(child: Text('Chưa có dữ liệu', style: TextStyle(color: Colors.grey))),
      );
    }
    return Container(
      height: 180,
      decoration: BoxDecoration(color: const Color(0xFF1E2330), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: CustomPaint(
        size: const Size(double.infinity, 160),
        painter: _DailyLinePainter(_dailyData),
      ),
    );
  }

  // ==================== Heatmap Overlay ====================

  Widget _heatmapView() {
    if (_heatmapData.isEmpty && _snapshotUrl == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(color: const Color(0xFF1E2330), borderRadius: BorderRadius.circular(12)),
        child: const Center(child: Text('Chưa có dữ liệu heatmap', style: TextStyle(color: Colors.grey))),
      );
    }

    final fullSnapshotUrl = _snapshotUrl != null && _snapshotUrl!.startsWith('/')
      ? '${_api.baseUrl}$_snapshotUrl'
      : _snapshotUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (fullSnapshotUrl != null)
              Image.network(
                fullSnapshotUrl,
                headers: _api.authHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E2330)),
              )
            else
              Container(color: const Color(0xFF1E2330)),
            CustomPaint(
              painter: _HeatmapPainter(_heatmapData),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== Custom Painters ====================

class _HourlyBarPainter extends CustomPainter {
  final List<int> data;
  final int maxVal;

  _HourlyBarPainter(this.data, this.maxVal);

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = (size.width - 40) / 24;
    final chartHeight = size.height - 24;

    final barPaint = Paint()..color = const Color(0xFFFF3B30);
    final textStyle = const TextStyle(color: Colors.grey, fontSize: 8);

    for (int i = 0; i < 24; i++) {
      final val = data.length > i ? data[i] : 0;
      final barHeight = maxVal > 0 ? (val / maxVal) * chartHeight : 0.0;

      final x = 30 + i * barWidth;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, chartHeight - barHeight, barWidth - 2, barHeight),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, barPaint);

      // Hour labels (every 3 hours)
      if (i % 3 == 0) {
        final tp = TextPainter(
          text: TextSpan(text: '${i}h', style: textStyle),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + barWidth / 2 - tp.width / 2, chartHeight + 4));
      }
    }

    // Y-axis labels
    for (int i = 0; i <= 4; i++) {
      final val = (maxVal * i / 4).round();
      final y = chartHeight - (chartHeight * i / 4);
      final tp = TextPainter(
        text: TextSpan(text: '$val', style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));

      canvas.drawLine(
        Offset(28, y),
        Offset(size.width, y),
        Paint()..color = Colors.grey.withOpacity(0.15)..strokeWidth = 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyBarPainter oldDelegate) => true;
}

class _DailyLinePainter extends CustomPainter {
  final List<Map<String, dynamic>> data;

  _DailyLinePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final chartHeight = size.height - 24;
    final chartWidth = size.width - 40;
    final maxVal = data.map((d) => (d['count'] as int?) ?? 0).reduce(max).clamp(1, 999999);
    final textStyle = const TextStyle(color: Colors.grey, fontSize: 8);

    final linePaint = Paint()
      ..color = const Color(0xFF007AFF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..color = const Color(0xFF007AFF);

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x40007AFF), Color(0x00007AFF)],
      ).createShader(Rect.fromLTWH(30, 0, chartWidth, chartHeight));

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final val = (data[i]['count'] as int?) ?? 0;
      final x = 30 + (i / (data.length - 1).clamp(1, 999)) * chartWidth;
      final y = chartHeight - (val / maxVal) * chartHeight;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, chartHeight);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 3, dotPaint);

      // Date labels (show first, last, and a few in between)
      if (i == 0 || i == data.length - 1 || (data.length > 5 && i % (data.length ~/ 4) == 0)) {
        final dateStr = data[i]['date']?.toString() ?? '';
        final short = dateStr.length >= 5 ? dateStr.substring(5) : dateStr; // "MM-DD"
        final tp = TextPainter(
          text: TextSpan(text: short, style: textStyle),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, chartHeight + 4));
      }
    }

    fillPath.lineTo(30 + chartWidth, chartHeight);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _DailyLinePainter oldDelegate) => true;
}

class _HeatmapPainter extends CustomPainter {
  final List<Map<String, dynamic>> boxes;

  _HeatmapPainter(this.boxes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      final x = ((box['x'] as num?) ?? 0) * size.width;
      final y = ((box['y'] as num?) ?? 0) * size.height;
      final w = ((box['w'] as num?) ?? 0.1) * size.width;
      final h = ((box['h'] as num?) ?? 0.1) * size.height;
      final intensity = ((box['intensity'] as num?) ?? 0.5).clamp(0.0, 1.0);

      final color = Color.lerp(const Color(0x4000FF00), const Color(0xC0FF0000), intensity.toDouble())!;
      final paint = Paint()..color = color;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) => true;
}
