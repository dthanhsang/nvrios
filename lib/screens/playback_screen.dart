import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../models/camera.dart';
import '../models/video_file.dart';

class PlaybackScreen extends StatefulWidget {
  final int? initialCameraId;
  final String? initialDate;
  final String? initialEventTimestamp;

  const PlaybackScreen({
    super.key,
    this.initialCameraId,
    this.initialDate,
    this.initialEventTimestamp,
  });

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<Camera> _cameras = [];
  Camera? _selectedCamera;
  String? _selectedDate;
  List<VideoFile> _videos = [];
  List<Map<String, dynamic>> _events = [];
  List<String> _availableDates = [];
  VideoFile? _currentVideo;
  int _currentVideoIndex = -1;
  double _currentPlaySeconds = 0;
  bool _isLoading = true;
  bool _isTranscoding = false;
  int _transcodingProgress = 0;
  int _timelineZoom = 1; // 1=24h, 4=6h, 24=1h
  bool _showAllVideos = false;

  bool _hasAutoPlayedEvent = false;

  // Video Player state
  VideoPlayerController? _videoPlayerController;
  bool _isPlayerInitialized = false;
  double _playbackLoadingPercent = 0.0;
  double _videoBufferPercent = 0.0;
  Timer? _playbackLoadingTimer;

  // New state
  double _playbackSpeed = 1.0;
  double _downloadProgress = -1; // -1 = not downloading
  String? _lastDownloadedPath;
  bool _isSnapshotting = false;

  static const List<double> _speedOptions = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  @override
  void dispose() {
    _disposeVideoPlayer();
    super.dispose();
  }

  void _disposeVideoPlayer() {
    _playbackLoadingTimer?.cancel();
    _videoPlayerController?.removeListener(_videoPlayerListener);
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _isPlayerInitialized = false;
  }

  Map<String, dynamic>? _findVideoForEvent(Map<String, dynamic> event) {
    final timestampStr = event['timestamp'] as String? ?? '';
    if (timestampStr.isEmpty) return null;
    
    DateTime? eventTime;
    try {
      eventTime = DateTime.parse(timestampStr);
    } catch (_) {
      final parts = timestampStr.split(' ');
      final timePart = parts.length > 1 ? parts[1] : parts[0];
      final timeParts = timePart.split(':');
      if (timeParts.length >= 3) {
        final now = DateTime.now();
        eventTime = DateTime(
          now.year, now.month, now.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
          int.parse(timeParts[2]),
        );
      }
    }
    
    if (eventTime == null) return null;
    final eventSeconds = eventTime.hour * 3600 + eventTime.minute * 60 + eventTime.second;

    for (int i = 0; i < _videos.length; i++) {
      final video = _videos[i];
      final start = video.startSeconds;
      final end = start + video.duration;
      if (eventSeconds >= start && eventSeconds <= end) {
        return {
          'videoIndex': i,
          'seekSeconds': eventSeconds - start,
        };
      }
    }
    return null;
  }

  void _videoPlayerListener() {
    if (_videoPlayerController == null || !_isPlayerInitialized) return;
    
    final value = _videoPlayerController!.value;
    if (value.position.inSeconds != 0) {
      if (mounted) {
        setState(() {
          _currentPlaySeconds = (_currentVideo?.startSeconds.toDouble() ?? 0) + value.position.inSeconds;
        });
      }
    }

    if (value.isInitialized) {
      final totalMs = value.duration.inMilliseconds;
      if (totalMs > 0) {
        int totalBufferedMs = 0;
        for (final range in value.buffered) {
          totalBufferedMs += (range.end.inMilliseconds - range.start.inMilliseconds);
        }
        final double percent = (totalBufferedMs / totalMs) * 100.0;
        if (mounted && percent != _videoBufferPercent) {
          setState(() {
            _videoBufferPercent = percent.clamp(0.0, 100.0);
          });
        }
      }
    }

    // Tự động chuyển video tiếp theo khi kết thúc
    if (value.isInitialized && value.position >= value.duration) {
      _onVideoEnded();
    }
  }

  Future<void> _loadCameras() async {
    final cameras = await _apiService.getCameras();
    if (mounted) {
      setState(() {
        _cameras = cameras.where((c) => c.enabled).toList();
        
        // Ưu tiên camera truyền vào từ constructor
        if (widget.initialCameraId != null) {
          final found = _cameras.firstWhere(
            (c) => c.id == widget.initialCameraId,
            orElse: () => _cameras.isNotEmpty ? _cameras.first : Camera(id: -1, name: '', enabled: false, rtspUrl: '', rtspUrlSub: '', go2rtcSrc: '', protocol: 'tcp'),
          );
          if (found.id != -1) {
            _selectedCamera = found;
          }
        }
        
        if (_selectedCamera == null && _cameras.isNotEmpty) {
          _selectedCamera = _cameras.first;
        }

        // Ưu tiên ngày truyền vào từ constructor
        if (widget.initialDate != null) {
          _selectedDate = widget.initialDate;
        } else {
          _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        }

        _isLoading = false;
      });
      _loadDatesAndVideos();
    }
  }

  Future<void> _loadDatesAndVideos() async {
    if (_selectedCamera == null || _selectedDate == null) return;
    setState(() => _isLoading = true);

    final dates = await _apiService.getPlaybackDates(_selectedCamera!.id);
    final videos = await _apiService.getPlaybackVideos(_selectedCamera!.id, _selectedDate!);
    final events = await _apiService.getPlaybackEvents(_selectedCamera!.id, _selectedDate!);

    if (mounted) {
      setState(() {
        _availableDates = dates;
        _videos = videos;
        _events = events;
        _isLoading = false;
        
        // Nếu đang phát mà chuyển camera/ngày, dừng trình phát
        _disposeVideoPlayer();
        _currentVideo = null;
        _currentVideoIndex = -1;
        _currentPlaySeconds = 0;
      });

      // Tự động phát video chứa sự kiện nếu có initialEventTimestamp
      if (widget.initialEventTimestamp != null && !_hasAutoPlayedEvent && _videos.isNotEmpty) {
        _hasAutoPlayedEvent = true;
        final eventMap = {'timestamp': widget.initialEventTimestamp};
        final match = _findVideoForEvent(eventMap);
        if (match != null) {
          final int videoIdx = match['videoIndex'] as int;
          final double seekSec = match['seekSeconds'] as double;
          // Lùi lại 5 giây để người dùng xem trước ngữ cảnh của sự kiện
          final startSeek = (seekSec - 5).clamp(0.0, _videos[videoIdx].duration.toDouble()).toInt();
          
          // Phát video
          _playVideo(videoIdx, seekSeconds: startSeek);
        }
      }
    }
  }

  Future<void> _playVideo(int index, {int seekSeconds = 0}) async {
    if (index < 0 || index >= _videos.length) return;
    final video = _videos[index];

    // Ngừng player cũ
    _disposeVideoPlayer();

    // Check if transcoding needed
    if (video.needsTranscode && !video.hasCache) {
      setState(() {
        _isTranscoding = true;
        _transcodingProgress = 0;
      });

      // Trigger and poll transcoding
      for (int i = 0; i < 150; i++) {
        final status = await _apiService.checkPlaybackCache(
          _selectedCamera!.id, _selectedDate!, video.filename,
        );
        if (status != null) {
          if (status['status'] == 'ready') {
            break;
          }
          if (status['status'] == 'transcoding') {
            final progressVal = status['progress'] as int? ?? 0;
            if (mounted) {
              setState(() {
                _transcodingProgress = progressVal;
              });
            }
          }
        }
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
      }

      if (mounted) {
        setState(() {
          _isTranscoding = false;
          _transcodingProgress = 0;
        });
      }
    }

    final videoUrl = video.needsTranscode
        ? _apiService.getStreamUrl(_selectedCamera!.id, _selectedDate!, video.filename, seekSeconds: seekSeconds)
        : '${_apiService.baseUrl}${video.canPlayDirect ? video.directUrl : (video.hasCache ? video.cacheUrl ?? video.url : video.url)}';

    if (mounted) {
      setState(() {
        _currentVideo = video;
        _currentVideoIndex = index;
        _currentPlaySeconds = video.startSeconds.toDouble() + seekSeconds;
        _isLoading = false;
      });
    }

    _playbackLoadingTimer?.cancel();
    _playbackLoadingPercent = 0.0;
    _videoBufferPercent = 0.0;
    _playbackLoadingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          if (_playbackLoadingPercent < 95.0) {
            _playbackLoadingPercent += 5.0;
          }
        });
      }
    });

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        httpHeaders: _apiService.authHeaders,
      );

      _videoPlayerController = controller;
      await controller.initialize();
      
      _playbackLoadingTimer?.cancel();
      if (!mounted) return;

      controller.addListener(_videoPlayerListener);
      await controller.setPlaybackSpeed(_playbackSpeed);
      
      if (seekSeconds > 0) {
        await controller.seekTo(Duration(seconds: seekSeconds));
      }
      
      await controller.play();

      setState(() {
        _playbackLoadingPercent = 100.0;
        _isPlayerInitialized = true;
      });
    } catch (e) {
      _playbackLoadingTimer?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khởi tạo trình phát: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _enterFullscreen() {
    if (_videoPlayerController == null || !_isPlayerInitialized) return;
    
    _videoPlayerController!.removeListener(_videoPlayerListener);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenPlaybackScreen(
          controller: _videoPlayerController!,
          cameraName: _selectedCamera?.name ?? 'Camera',
          date: _selectedDate ?? '',
        ),
      ),
    ).then((_) {
      if (mounted && _videoPlayerController != null) {
        _videoPlayerController!.addListener(_videoPlayerListener);
        setState(() {});
      }
    });
  }

  void _onVideoEnded() {
    if (_currentVideoIndex < _videos.length - 1) {
      _playVideo(_currentVideoIndex + 1);
    }
  }

  void _onTimelineTap(double totalSeconds) async {
    // Find video containing this timestamp
    for (int i = 0; i < _videos.length; i++) {
      final v = _videos[i];
      if (totalSeconds >= v.startSeconds && totalSeconds < v.startSeconds + v.duration) {
        final offset = (totalSeconds - v.startSeconds).toInt();
        
        // Nếu đang phát đúng video đó, chỉ cần seek native (cực nhanh!)
        if (_currentVideoIndex == i && _videoPlayerController != null && _isPlayerInitialized) {
          await _videoPlayerController!.seekTo(Duration(seconds: offset));
          if (mounted) {
            setState(() {
              _currentPlaySeconds = totalSeconds;
            });
          }
        } else {
          // Play video mới hoặc transcode
          _playVideo(i, seekSeconds: offset);
        }
        return;
      }
    }
  }

  void _cycleZoom() {
    setState(() {
      if (_timelineZoom == 1) {
        _timelineZoom = 4;
      } else if (_timelineZoom == 4) {
        _timelineZoom = 24;
      } else {
        _timelineZoom = 1;
      }
    });
  }

  String get _zoomLabel {
    if (_timelineZoom == 1) {
      return '24h';
    }
    if (_timelineZoom == 4) {
      return '6h';
    }
    return '1h';
  }

  List<String> get _dateChips {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final date = now.subtract(Duration(days: i));
      return DateFormat('yyyy-MM-dd').format(date);
    });
  }

  String _formatDateChip(String date) {
    final dt = DateTime.parse(date);
    final weekdays = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
    final day = DateFormat('dd/MM').format(dt);
    return '${weekdays[dt.weekday % 7]}\n$day';
  }

  void _setPlaybackSpeed(double speed) async {
    setState(() => _playbackSpeed = speed);
    if (_videoPlayerController != null && _isPlayerInitialized) {
      await _videoPlayerController!.setPlaybackSpeed(speed);
    }
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2330),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Tốc độ phát', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1, color: Color(0xFF2A3040)),
            ..._speedOptions.map((speed) => ListTile(
              dense: true,
              title: Text(
                'x${speed == speed.toInt() ? speed.toInt().toString() : speed.toString()}',
                style: TextStyle(
                  color: _playbackSpeed == speed ? const Color(0xFFFF3B30) : Colors.white,
                  fontWeight: _playbackSpeed == speed ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: _playbackSpeed == speed
                  ? const Icon(Icons.check, color: Color(0xFFFF3B30), size: 20)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _setPlaybackSpeed(speed);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _speedLabel(double speed) {
    if (speed == speed.toInt()) return 'x${speed.toInt()}';
    return 'x$speed';
  }

  Future<void> _downloadCurrentVideo() async {
    if (_currentVideo == null || _downloadProgress >= 0) return;

    final video = _currentVideo!;
    final downloadUrl = '${_apiService.baseUrl}${video.downloadUrl}';
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/${video.filename}';

    setState(() => _downloadProgress = 0);

    try {
      final dio = Dio();
      dio.options.headers.addAll(_apiService.authHeaders);

      await dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadProgress = -1;
          _lastDownloadedPath = savePath;
        });
        _showDownloadComplete(savePath);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadProgress = -1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tải xuống thất bại: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDownloadComplete(String filePath) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tải xuống hoàn tất!'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'Chia sẻ',
          textColor: Colors.white,
          onPressed: () => _shareFile(filePath),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _shareFile(String filePath) async {
    final file = XFile(filePath);
    await Share.shareXFiles(
      [file],
      text: _currentVideo?.filename ?? 'Video',
    );
  }

  Future<void> _takeSnapshot() async {
    if (_selectedCamera == null || _isSnapshotting) return;

    setState(() => _isSnapshotting = true);

    try {
      final snapshotUrl =
          '${_apiService.baseUrl}/go2rtc/api/frame.jpeg?src=${_selectedCamera!.go2rtcSrc}';

      final dio = Dio();
      dio.options.headers.addAll(_apiService.authHeaders);

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final savePath = '${dir.path}/snapshot_${_selectedCamera!.name}_$timestamp.jpg';

      await dio.download(snapshotUrl, savePath);

      if (mounted) {
        setState(() => _isSnapshotting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Đã chụp ảnh!'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Chia sẻ',
              textColor: Colors.white,
              onPressed: () async {
                final file = XFile(savePath);
                await Share.shareXFiles([file], text: 'Snapshot ${_selectedCamera!.name}');
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSnapshotting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chụp ảnh thất bại: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xem lại'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, size: 20),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_selectedDate ?? '') ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _selectedDate = DateFormat('yyyy-MM-dd').format(picked));
                _loadDatesAndVideos();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera selector
          if (_cameras.isNotEmpty) SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _cameras.length,
              itemBuilder: (context, i) {
                final cam = _cameras[i];
                final selected = cam.id == _selectedCamera?.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cam.name, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.grey)),
                    selected: selected,
                    selectedColor: const Color(0xFFFF3B30),
                    backgroundColor: const Color(0xFF1E2330),
                    onSelected: (_) {
                      setState(() => _selectedCamera = cam);
                      _loadDatesAndVideos();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),

          // Date selector
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _dateChips.length,
              itemBuilder: (context, i) {
                final date = _dateChips[i];
                final selected = date == _selectedDate;
                final hasRecordings = _availableDates.contains(date);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedDate = date);
                      _loadDatesAndVideos();
                    },
                    child: Container(
                      width: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFF3B30) : const Color(0xFF1E2330),
                        borderRadius: BorderRadius.circular(8),
                        border: hasRecordings && !selected
                            ? Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3))
                            : null,
                      ),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Center(
                            child: Text(
                              _formatDateChip(date),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: selected ? Colors.white : (hasRecordings ? Colors.white70 : Colors.grey),
                                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (hasRecordings && !selected) Positioned(
                            top: 4, right: 6,
                            child: Container(
                              width: 5, height: 5,
                              decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
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
          const SizedBox(height: 4),

          // Video player area
          SizedBox(
            height: 220,
            child: _buildPlayerArea(),
          ),

          // Controls bar: speed, snapshot, download
          if (_currentVideo != null) _buildControlsBar(),

          // Current video info
          if (_currentVideo != null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF161920),
            child: Row(
              children: [
                Text(
                  _currentVideo!.time,
                  style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_currentVideo!.filename, style: const TextStyle(color: Colors.grey, fontSize: 11), overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _currentVideo!.isH264 ? Colors.blue : Colors.purple,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _currentVideo!.codec.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${_currentVideo!.sizeMb.toStringAsFixed(1)}MB', style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ),

          // Download progress
          if (_downloadProgress >= 0) _buildDownloadProgress(),

          // Timeline
          _buildTimeline(),

          // Transcoding indicator
          if (_isTranscoding) Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1E2330),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30))),
                const SizedBox(width: 8),
                Text('Đang chuyển đổi video: $_transcodingProgress% ...', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),

          // Mode Selector Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _showAllVideos ? 'Tất cả bản ghi (24/24)' : 'Sự kiện phát hiện chuyển động',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAllVideos = !_showAllVideos;
                    });
                  },
                  icon: Icon(
                    _showAllVideos ? Icons.event_note : Icons.video_library,
                    size: 16,
                    color: const Color(0xFFFF3B30),
                  ),
                  label: Text(
                    _showAllVideos ? 'Xem theo sự kiện' : 'Xem toàn bộ 24/24',
                    style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    backgroundColor: const Color(0xFFFF3B30).withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),

          // Video / Event list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _showAllVideos
                    ? (_videos.isEmpty
                        ? const Center(child: Text('Không có video', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _videos.length,
                            itemBuilder: (context, i) {
                              final video = _videos[i];
                              final isPlaying = i == _currentVideoIndex;
                              return ListTile(
                                dense: true,
                                selected: isPlaying,
                                selectedTileColor: const Color(0xFFFF3B30).withOpacity(0.1),
                                leading: Icon(
                                  isPlaying ? Icons.play_circle_filled : Icons.play_circle_outline,
                                  color: isPlaying ? const Color(0xFFFF3B30) : Colors.grey,
                                  size: 28,
                                ),
                                title: Text(video.time, style: TextStyle(
                                  color: isPlaying ? const Color(0xFFFF3B30) : Colors.white,
                                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                )),
                                subtitle: Text(
                                  '${_formatDuration(video.duration)} • ${video.sizeMb.toStringAsFixed(1)}MB',
                                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: video.isH264 ? Colors.blue.withOpacity(0.2) : Colors.purple.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        video.codec.toUpperCase(),
                                        style: TextStyle(
                                          color: video.isH264 ? Colors.blue : Colors.purple,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => _playVideo(i),
                              );
                            },
                          ))
                    : (_events.isEmpty
                        ? const Center(child: Text('Không có sự kiện chuyển động nào trong ngày này', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _events.length,
                            itemBuilder: (context, i) {
                              final event = _events[i];
                              final timestampStr = event['timestamp'] as String? ?? '';
                              String displayTime = timestampStr;
                              if (timestampStr.contains(' ')) {
                                displayTime = timestampStr.split(' ')[1];
                              }
                              final rawDetails = event['details'] as String? ?? 'Phát hiện chuyển động';
                              // Extract short summary from AI markdown details
                              String details = rawDetails;
                              if (rawDetails.contains('ALERT_STRANGER')) {
                                details = '⚠️ Người lạ - Cảnh báo';
                              } else if (rawDetails.contains('FAMILY')) {
                                final familyMatch = RegExp(r'FAMILY:\s*(.+)', caseSensitive: false).firstMatch(rawDetails);
                                details = familyMatch != null ? '🏠 ${familyMatch.group(1)!.trim()}' : '🏠 Thành viên gia đình';
                                if (details.length > 60) details = '${details.substring(0, 60)}...';
                              } else if (rawDetails.contains('NORMAL')) {
                                details = '✅ Người đi đường';
                              } else if (rawDetails.length > 60) {
                                // Truncate long AI analysis to first meaningful line
                                final lines = rawDetails.split(RegExp(r'[\n#]+'));
                                details = lines.firstWhere((l) => l.trim().length > 5, orElse: () => rawDetails).trim();
                                if (details.length > 60) details = '${details.substring(0, 60)}...';
                              }
                              final snapshotPath = event['snapshot_path'] as String?;
                              
                              bool isCurrentEvent = false;
                              final mapping = _findVideoForEvent(event);
                              if (mapping != null && _currentVideoIndex == mapping['videoIndex']) {
                                final eventSec = mapping['seekSeconds'] as int;
                                final currentSec = _videoPlayerController != null && _isPlayerInitialized
                                    ? _videoPlayerController!.value.position.inSeconds
                                    : 0;
                                if ((currentSec - eventSec).abs() < 15) {
                                  isCurrentEvent = true;
                                }
                              }

                              return ListTile(
                                dense: true,
                                selected: isCurrentEvent,
                                selectedTileColor: const Color(0xFFFF3B30).withOpacity(0.1),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: snapshotPath != null && snapshotPath.isNotEmpty
                                      ? Image.network(
                                          '${_apiService.baseUrl}$snapshotPath',
                                          headers: _apiService.authHeaders,
                                          width: 50,
                                          height: 38,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.motion_photos_on, color: Colors.orange, size: 28),
                                        )
                                      : const Icon(Icons.motion_photos_on, color: Colors.orange, size: 28),
                                ),
                                title: Text(
                                  '$displayTime - $details',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrentEvent ? const Color(0xFFFF3B30) : Colors.white,
                                    fontWeight: isCurrentEvent ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  'Loại: ${event['event_type'] ?? 'chuyển động'}',
                                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                                ),
                                trailing: const Icon(Icons.play_arrow, color: Colors.grey, size: 18),
                                onTap: () {
                                  if (mapping != null) {
                                    _playVideo(mapping['videoIndex'] as int, seekSeconds: mapping['seekSeconds'] as int);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Không tìm thấy file video tương ứng')),
                                    );
                                  }
                                },
                              );
                            },
                          )),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerArea() {
    if (_currentVideo == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Chọn một video từ danh sách để xem', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_videoPlayerController == null || !_isPlayerInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFF3B30)),
            const SizedBox(height: 12),
            Text(
              'Đang tải luồng video... ${_playbackLoadingPercent.toInt()}%',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onTap: () {
            if (_videoPlayerController != null) {
              setState(() {
                if (_videoPlayerController!.value.isPlaying) {
                  _videoPlayerController!.pause();
                } else {
                  _videoPlayerController!.play();
                }
              });
            }
          },
          child: Container(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: _videoPlayerController!.value.aspectRatio,
              child: VideoPlayer(_videoPlayerController!),
            ),
          ),
        ),
        if (_videoPlayerController!.value.isBuffering)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFFFF3B30)),
                const SizedBox(height: 12),
                Text(
                  'Đang tải thêm... ${_videoBufferPercent.toInt()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 13, shadows: [
                    Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black),
                  ]),
                ),
              ],
            ),
          )
        else if (!_videoPlayerController!.value.isPlaying)
          IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                size: 40,
                color: Colors.white,
              ),
            ),
          ),
        Positioned(
          bottom: 8,
          right: 8,
          child: GestureDetector(
            onTap: _enterFullscreen,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.fullscreen,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF0D1117),
      child: Row(
        children: [
          // Speed button
          _controlButton(
            icon: Icons.speed,
            label: _speedLabel(_playbackSpeed),
            highlighted: _playbackSpeed != 1.0,
            onTap: _showSpeedPicker,
          ),
          const SizedBox(width: 8),

          // Snapshot button
          _controlButton(
            icon: _isSnapshotting ? Icons.hourglass_top : Icons.camera_alt,
            label: 'Chụp',
            onTap: _isSnapshotting ? null : _takeSnapshot,
          ),
          const SizedBox(width: 8),

          // Download button
          _controlButton(
            icon: _downloadProgress >= 0 ? Icons.downloading : Icons.download,
            label: _downloadProgress >= 0
                ? '${(_downloadProgress * 100).toInt()}%'
                : 'Tải',
            onTap: _downloadProgress >= 0 ? null : _downloadCurrentVideo,
          ),

          // Share last downloaded
          if (_lastDownloadedPath != null) ...[
            const SizedBox(width: 8),
            _controlButton(
              icon: Icons.share,
              label: 'Chia sẻ',
              onTap: () => _shareFile(_lastDownloadedPath!),
            ),
          ],

          const Spacer(),

          // Current time label
          Text(
            _formatSecondsToTime(_currentPlaySeconds),
            style: const TextStyle(
              color: Color(0xFFFF3B30),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    bool highlighted = false,
    VoidCallback? onTap,
  }) {
    final color = highlighted ? const Color(0xFFFF3B30) : Colors.white70;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2330),
            borderRadius: BorderRadius.circular(6),
            border: highlighted ? Border.all(color: const Color(0xFFFF3B30).withOpacity(0.5), width: 1) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: const Color(0xFF0D1117),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: const Color(0xFF1E2330),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF3B30)),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _cycleZoom,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2330),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_zoomLabel, style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) {
                    final ratio = details.localPosition.dx / constraints.maxWidth;
                    final viewDuration = 86400.0 / _timelineZoom;
                    double viewStart = 0;
                    if (_timelineZoom > 1) {
                      viewStart = (_currentPlaySeconds - viewDuration / 2).clamp(0, 86400.0 - viewDuration);
                    }
                    final totalSeconds = viewStart + ratio * viewDuration;
                    _onTimelineTap(totalSeconds);
                  },
                  onScaleUpdate: (details) {
                    if (details.scale > 1.3 && _timelineZoom < 24) {
                      setState(() {
                        if (_timelineZoom == 1) {
                          _timelineZoom = 4;
                        } else if (_timelineZoom == 4) {
                          _timelineZoom = 24;
                        }
                      });
                    } else if (details.scale < 0.7 && _timelineZoom > 1) {
                      setState(() {
                        if (_timelineZoom == 24) {
                          _timelineZoom = 4;
                        } else if (_timelineZoom == 4) {
                          _timelineZoom = 1;
                        }
                      });
                    }
                  },
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      videos: _videos,
                      events: _events,
                      currentSeconds: _currentPlaySeconds,
                      zoom: _timelineZoom,
                    ),
                    size: Size(constraints.maxWidth, 60),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final m = (seconds / 60).floor();
    final s = (seconds % 60).floor();
    return '${m}m${s.toString().padLeft(2, '0')}s';
  }

  String _formatSecondsToTime(double totalSeconds) {
    final h = (totalSeconds / 3600).floor();
    final m = ((totalSeconds % 3600) / 60).floor();
    final s = (totalSeconds % 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ==================== TIMELINE PAINTER ====================

class _TimelinePainter extends CustomPainter {
  final List<VideoFile> videos;
  final List<Map<String, dynamic>> events;
  final double currentSeconds;
  final int zoom;

  _TimelinePainter({
    required this.videos,
    required this.events,
    required this.currentSeconds,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF1E2330);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(6)),
      bgPaint,
    );

    const double totalSeconds = 86400.0;
    double viewStart = 0;
    double viewEnd = totalSeconds;

    if (zoom > 1) {
      final viewDuration = totalSeconds / zoom;
      viewStart = (currentSeconds - viewDuration / 2).clamp(0, totalSeconds - viewDuration);
      viewEnd = viewStart + viewDuration;
    }

    final viewDuration = viewEnd - viewStart;

    // Draw recording blocks
    final recPaint = Paint()..color = Colors.green.withOpacity(0.4);
    for (final v in videos) {
      final start = v.startSeconds.toDouble();
      final end = start + v.duration;
      if (end < viewStart || start > viewEnd) {
        continue;
      }
      final x1 = ((start - viewStart) / viewDuration * size.width).clamp(0.0, size.width);
      final x2 = ((end - viewStart) / viewDuration * size.width).clamp(0.0, size.width);
      canvas.drawRect(Rect.fromLTRB(x1, 10, x2, size.height - 10), recPaint);
    }

    // Draw AI Events
    final eventPaint = Paint()..color = Colors.red;
    for (final ev in events) {
      final double sec = (ev['seconds'] as num?)?.toDouble() ?? 0.0;
      if (sec < viewStart || sec > viewEnd) {
        continue;
      }
      final x = (sec - viewStart) / viewDuration * size.width;
      canvas.drawCircle(Offset(x, size.height / 2), 3, eventPaint);
    }

    // Draw time ticks
    final tickPaint = Paint()..color = Colors.grey.withOpacity(0.3);
    const textStyle = TextStyle(color: Colors.grey, fontSize: 8);
    int tickInterval;
    if (zoom >= 24) {
      tickInterval = 600; // 10 min
    } else if (zoom >= 4) {
      tickInterval = 1800; // 30 min
    } else {
      tickInterval = 7200; // 2 hours
    }

    for (int t = 0; t < 86400; t += tickInterval) {
      if (t < viewStart || t > viewEnd) {
        continue;
      }
      final x = (t - viewStart) / viewDuration * size.width;
      canvas.drawLine(Offset(x, size.height - 18), Offset(x, size.height - 10), tickPaint);

      // Label
      final h = t ~/ 3600;
      final m = (t % 3600) ~/ 60;
      final timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      final textPainter = TextPainter(
        text: TextSpan(text: timeStr, style: textStyle),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - 8));
    }

    // Draw current play indicator line
    if (currentSeconds >= viewStart && currentSeconds <= viewEnd) {
      final x = (currentSeconds - viewStart) / viewDuration * size.width;
      final linePaint = Paint()
        ..color = const Color(0xFFFF3B30)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), linePaint);

      // Triangle handle on top
      final path = Path();
      path.moveTo(x - 4, 0);
      path.lineTo(x + 4, 0);
      path.lineTo(x, 6);
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFFF3B30));
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.videos != videos ||
        oldDelegate.events != events ||
        oldDelegate.currentSeconds != currentSeconds ||
        oldDelegate.zoom != zoom;
  }
}

class _FullscreenPlaybackScreen extends StatefulWidget {
  final VideoPlayerController controller;
  final String cameraName;
  final String date;

  const _FullscreenPlaybackScreen({
    required this.controller,
    required this.cameraName,
    required this.date,
  });

  @override
  State<_FullscreenPlaybackScreen> createState() => _FullscreenPlaybackScreenState();
}

class _FullscreenPlaybackScreenState extends State<_FullscreenPlaybackScreen> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startHideTimer();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            if (_showControls) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.cameraName} - Xem lại ${widget.date}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (widget.controller.value.isPlaying) {
                        widget.controller.pause();
                      } else {
                        widget.controller.play();
                      }
                    });
                    _startHideTimer();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      ValueListenableBuilder(
                        valueListenable: widget.controller,
                        builder: (context, VideoPlayerValue value, child) {
                          final position = value.position;
                          final duration = value.duration;
                          return Text(
                            '${_formatDuration(position)} / ${_formatDuration(duration)}',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ValueListenableBuilder(
                          valueListenable: widget.controller,
                          builder: (context, VideoPlayerValue value, child) {
                            final position = value.position.inMilliseconds.toDouble();
                            final duration = value.duration.inMilliseconds.toDouble();
                            return SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.0,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                              ),
                              child: Slider(
                                activeColor: const Color(0xFFFF3B30),
                                inactiveColor: Colors.white24,
                                value: duration > 0 ? position.clamp(0.0, duration) : 0.0,
                                max: duration > 0 ? duration : 1.0,
                                onChanged: (val) {
                                  widget.controller.seekTo(Duration(milliseconds: val.toInt()));
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
