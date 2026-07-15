import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<dynamic> _cameras = [];
  bool _isLoading = true;
  String? _loadError;
  int _gridColumns = 2;
  int? _fullscreenCamId;
  final Map<int, GlobalKey<_MjpegStreamPlayerState>> _mjpegKeys = {};

  // Fullscreen controls
  bool _showFullscreenControls = true;
  Timer? _hideControlsTimer;
  bool _isFullscreenHD = true; // fullscreen always starts HD

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
      _loadError = null;
    });
    try {
      final cameras = await _apiService.getCameras();
      if (!mounted) return;
      setState(() {
        _cameras = cameras.where((c) => c['enabled'] == 1 || c['enabled'] == true).toList();
        for (var cam in _cameras) {
          _mjpegKeys.putIfAbsent(cam['id'], () => GlobalKey<_MjpegStreamPlayerState>());
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  String _getMjpegStreamUrl(dynamic camera, {bool hd = false}) {
    final base = _apiService.go2rtcUrl;
    final src = camera['go2rtc_src'] as String;
    // SD: use _mjpeg (sub stream), HD: use main stream via mjpeg
    final streamSrc = hd ? '${src}_mjpeg' : '${src}_mjpeg';
    return '$base/api/stream.mjpeg?src=$streamSrc&token=${_apiService.sessionToken}';
  }

  String _getHdStreamUrl(dynamic camera) {
    // For fullscreen HD, use the main MJPEG stream
    final base = _apiService.go2rtcUrl;
    final src = camera['go2rtc_src'] as String;
    return '$base/api/stream.mjpeg?src=${src}_mjpeg&token=${_apiService.sessionToken}';
  }

  void _enterFullscreen(int camId) {
    setState(() {
      _fullscreenCamId = camId;
      _isFullscreenHD = true;
      _showFullscreenControls = true;
    });
    _startHideControlsTimer();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    _hideControlsTimer?.cancel();
    setState(() => _fullscreenCamId = null);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _fullscreenCamId != null) {
        setState(() => _showFullscreenControls = false);
      }
    });
  }

  void _toggleFullscreenControls() {
    setState(() => _showFullscreenControls = !_showFullscreenControls);
    if (_showFullscreenControls) {
      _startHideControlsTimer();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_fullscreenCamId != null) {
      return _buildFullscreenView();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Giám sát trực tiếp"),
        actions: [
          _buildGridButton(1, Icons.crop_square),
          _buildGridButton(2, Icons.grid_view),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadCameras,
            tooltip: "Tải lại",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : _loadError != null
              ? _buildErrorState()
              : _cameras.isEmpty
                  ? _buildEmptyState()
                  : _buildGridView(),
    );
  }

  Widget _buildGridButton(int cols, IconData icon) {
    final isActive = _gridColumns == cols;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => setState(() => _gridColumns = cols),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFFF3B30) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 20, color: isActive ? Colors.white : const Color(0xFF7E8B9B)),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Color(0xFFFF3B30)),
            const SizedBox(height: 16),
            const Text("Không thể kết nối tới máy chủ",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_loadError ?? '', style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 12),
              textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadCameras,
              icon: const Icon(Icons.refresh),
              label: const Text("Thử lại"),
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
          const Icon(Icons.videocam_off, size: 64, color: Color(0xFF7E8B9B)),
          const SizedBox(height: 16),
          const Text("Không có camera nào đang hoạt động.",
            style: TextStyle(color: Color(0xFF7E8B9B), fontSize: 15),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadCameras,
            icon: const Icon(Icons.refresh),
            label: const Text("Thử lại"),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridColumns,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 16 / 10,
      ),
      itemCount: _cameras.length,
      itemBuilder: (context, index) {
        final camera = _cameras[index];
        final camId = camera['id'] as int;

        return GestureDetector(
          onDoubleTap: () => _enterFullscreen(camId),
          child: Card(
            clipBehavior: Clip.antiAlias,
            color: Colors.black,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Stack(
              children: [
                MjpegStreamPlayer(
                  key: _mjpegKeys[camId],
                  url: _getMjpegStreamUrl(camera),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 28),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "Lỗi kết nối\n$error",
                              style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 10),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Top overlay - camera name + controls
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xBB000000), Color(0x00000000)],
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      children: [
                        // LIVE indicator
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xCCFF3B30),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, color: Colors.white, size: 6),
                              SizedBox(width: 2),
                              Text("LIVE", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        // Camera name
                        Expanded(
                          child: Text(
                            camera['name'] ?? 'Camera $camId',
                            style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
                              shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Fullscreen button
                        GestureDetector(
                          onTap: () => _enterFullscreen(camId),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0x66FFFFFF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.fullscreen, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFullscreenView() {
    final camera = _cameras.firstWhere(
      (c) => c['id'] == _fullscreenCamId,
      orElse: () => null,
    );
    if (camera == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _exitFullscreen());
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleFullscreenControls,
          child: Stack(
            children: [
              // Full-screen video with pinch-to-zoom
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: MjpegStreamPlayer(
                    url: _getHdStreamUrl(camera),
                    fit: BoxFit.contain,
                    key: ValueKey('mjpeg_fs_${camera['id']}_hd'),
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Text(
                          "Lỗi tải luồng MJPEG\n$error",
                          style: const TextStyle(color: Color(0xFFFF3B30)),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // === TOP BAR (YouTube-like) ===
              AnimatedOpacity(
                opacity: _showFullscreenControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showFullscreenControls,
                  child: Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xDD000000), Color(0x00000000)],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(4, 8, 8, 16),
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            // Shrink/minimize button (like YouTube)
                            IconButton(
                              icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 26),
                              onPressed: _exitFullscreen,
                              tooltip: "Thu nhỏ",
                            ),
                            const SizedBox(width: 4),
                            // Camera name
                            Expanded(
                              child: Text(
                                camera['name'] ?? 'Camera',
                                style: const TextStyle(
                                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold,
                                  shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // LIVE badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3B30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, color: Colors.white, size: 8),
                                  SizedBox(width: 4),
                                  Text("LIVE", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            // HD badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2196F3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text("HD",
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // === BOTTOM BAR (YouTube-like toolbar) ===
              AnimatedOpacity(
                opacity: _showFullscreenControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showFullscreenControls,
                  child: Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xDD000000), Color(0x00000000)],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            // Current time
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: Colors.white70, fontSize: 12,
                                fontFamily: 'monospace',
                                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                              ),
                            ),
                            const Spacer(),
                            // Playback button - navigate to recorded video for this camera
                            _buildFullscreenToolButton(
                              icon: Icons.replay,
                              label: "Xem lại",
                              onTap: () {
                                _exitFullscreen();
                                // Navigate to playback tab - index 1 in MainScreen
                                // We use a callback through the Navigator to switch tabs
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Chuyển sang tab Xem lại để xem video ghi hình"),
                                      backgroundColor: Color(0xFF1E2330),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 16),
                            // Screenshot/Snapshot button
                            _buildFullscreenToolButton(
                              icon: Icons.camera_alt,
                              label: "Chụp",
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Tính năng chụp ảnh sẽ được cập nhật"),
                                    backgroundColor: Color(0xFF1E2330),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 16),
                            // Shrink button
                            _buildFullscreenToolButton(
                              icon: Icons.fullscreen_exit,
                              label: "Thu nhỏ",
                              onTap: _exitFullscreen,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        onTap();
        _startHideControlsTimer();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x55FFFFFF),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
            style: const TextStyle(
              color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600,
              shadows: [Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
        ],
      ),
    );
  }
}

/// MJPEG stream player - pure Dart multipart parser
/// Works on both Android and iOS by using dart:io HttpClient
class MjpegStreamPlayer extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const MjpegStreamPlayer({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  State<MjpegStreamPlayer> createState() => _MjpegStreamPlayerState();
}

class _MjpegStreamPlayerState extends State<MjpegStreamPlayer> with AutomaticKeepAliveClientMixin {
  Uint8List? _frameBytes;
  StreamSubscription? _subscription;
  HttpClient? _client;
  Object? _error;
  bool _isLoading = true;
  int _retryCount = 0;
  static const int _maxRetries = 5;
  Timer? _retryTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _startStreaming();
  }

  @override
  void didUpdateWidget(MjpegStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _stopStreaming();
      _retryCount = 0;
      _startStreaming();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _stopStreaming();
    super.dispose();
  }

  void _startStreaming() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _isLoading = _frameBytes == null;
    });

    _client = HttpClient();
    _client!.connectionTimeout = const Duration(seconds: 15);
    _client!.badCertificateCallback = (cert, host, port) => true;

    _client!.getUrl(Uri.parse(widget.url)).then((HttpClientRequest request) {
      return request.close();
    }).then((HttpClientResponse response) {
      if (!mounted) return;
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      List<int> buffer = [];
      _subscription = response.listen(
        (List<int> chunk) {
          if (!mounted) return;
          buffer.addAll(chunk);

          while (true) {
            if (buffer.length < 10) break;

            final maxScan = buffer.length > 4000 ? 4000 : buffer.length;
            final str = String.fromCharCodes(buffer.sublist(0, maxScan));
            final lowerStr = str.toLowerCase();
            final lenIdx = lowerStr.indexOf('content-length:');
            if (lenIdx == -1) {
              if (buffer.length > 262144) {
                final boundaryStr = lowerStr.lastIndexOf('--');
                if (boundaryStr > 0) {
                  buffer = buffer.sublist(boundaryStr);
                } else {
                  buffer.clear();
                }
              }
              break;
            }

            final lineEndIdx = str.indexOf('\r\n', lenIdx);
            if (lineEndIdx == -1) break;

            final lenStr = str.substring(lenIdx + 15, lineEndIdx).trim();
            final contentLength = int.tryParse(lenStr);
            if (contentLength == null || contentLength <= 0) {
              buffer = buffer.sublist(lineEndIdx + 2);
              continue;
            }

            final headerEndIdx = str.indexOf('\r\n\r\n', lenIdx);
            if (headerEndIdx == -1) break;

            final payloadStartIdx = headerEndIdx + 4;
            final payloadEndIdx = payloadStartIdx + contentLength;

            if (buffer.length < payloadEndIdx) break;

            final frame = Uint8List.fromList(buffer.sublist(payloadStartIdx, payloadEndIdx));
            if (mounted && frame.length > 2 && frame[0] == 0xFF && frame[1] == 0xD8) {
              setState(() {
                _frameBytes = frame;
                _error = null;
                _isLoading = false;
              });
              _retryCount = 0;
            }

            buffer = buffer.sublist(payloadEndIdx);
          }
        },
        onError: (err) => _handleStreamError(err),
        onDone: () => _handleStreamError('Stream ended'),
        cancelOnError: false,
      );
    }).catchError((err) {
      _handleStreamError(err);
      return null;
    });
  }

  void _handleStreamError(dynamic err) {
    if (!mounted) return;
    if (_retryCount < _maxRetries) {
      _retryCount++;
      _stopStreaming();
      _retryTimer = Timer(Duration(seconds: _retryCount.clamp(1, 5)), () {
        if (mounted) _startStreaming();
      });
    } else {
      setState(() {
        _error = err;
        _isLoading = false;
      });
    }
  }

  void _stopStreaming() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _client?.close(force: true);
    } catch (_) {}
    _client = null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_error != null && _frameBytes == null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!, null);
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 28),
            const SizedBox(height: 6),
            Text('Lỗi: $_error', style: const TextStyle(color: Colors.red, fontSize: 11),
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                _retryCount = 0;
                _startStreaming();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text("Thử lại", style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading || _frameBytes == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF3B30)),
        ),
      );
    }

    return Image.memory(
      _frameBytes!,
      gaplessPlayback: true,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
