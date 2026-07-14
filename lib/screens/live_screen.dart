import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
  int _gridColumns = 2; // 1 = single, 2 = 2x2
  int? _fullscreenCamId; // null = grid, non-null = single camera fullscreen
  final Map<int, bool> _hdMode = {}; // camId -> true=HD, false=SD
  bool _useMjpeg = true; // default MJPEG (smooth, fast, low overhead)

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
      setState(() {
        _cameras = cameras.where((c) => c['enabled'] == 1 || c['enabled'] == true).toList();
        for (var cam in _cameras) {
          _hdMode.putIfAbsent(cam['id'], () => false); // default SD for grid
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  String _getStreamUrl(dynamic camera, {bool? forceHd}) {
    final base = _apiService.go2rtcUrl;
    final src = camera['go2rtc_src'] as String;
    final camId = camera['id'] as int;
    final useHd = forceHd ?? (_hdMode[camId] ?? false);
    final streamSrc = useHd ? src : '${src}_sub';
    return '$base/stream.html?src=$streamSrc&mode=mse,webrtc&token=${_apiService.sessionToken}';
  }

  String _getMjpegStreamUrl(dynamic camera) {
    final base = _apiService.go2rtcUrl;
    final src = camera['go2rtc_src'] as String;
    return '$base/api/stream.mjpeg?src=${src}_mjpeg&token=${_apiService.sessionToken}';
  }

  void _enterFullscreen(int camId) {
    setState(() {
      _fullscreenCamId = camId;
      _hdMode[camId] = true; // auto-switch to HD in fullscreen
    });
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  void _exitFullscreen() {
    setState(() => _fullscreenCamId = null);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
          // Stream type toggle (MJPEG/WebView)
          IconButton(
            icon: Icon(_useMjpeg ? Icons.bolt : Icons.slow_motion_video,
              color: _useMjpeg ? const Color(0xFF4CD964) : const Color(0xFF7E8B9B),
              size: 20,
            ),
            onPressed: () => setState(() => _useMjpeg = !_useMjpeg),
            tooltip: _useMjpeg ? "Chế độ MJPEG (Mượt) - Chạm để đổi" : "Chế độ WebView (WebRTC) - Chạm để đổi",
          ),
          const SizedBox(width: 4),
          // Grid layout toggle
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
              style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 16, fontWeight: FontWeight.w600),
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
        final isHd = _hdMode[camId] ?? false;

        return GestureDetector(
          onDoubleTap: () => _enterFullscreen(camId),
          child: Card(
            clipBehavior: Clip.antiAlias,
            color: Colors.black,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Stack(
              children: [
                // Video stream
                _useMjpeg
                    ? MjpegStreamPlayer(
                        url: _getMjpegStreamUrl(camera),
                        fit: BoxFit.cover,
                        key: ValueKey('mjpeg_${camId}'),
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 28),
                                const SizedBox(height: 6),
                                Text(
                                  "Lỗi tải luồng MJPEG\n$error",
                                  style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 10),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : _Go2rtcWebView(
                        url: _getStreamUrl(camera),
                        key: ValueKey('cam_${camId}_${isHd ? "hd" : "sd"}'),
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
                        // HD/SD toggle
                        GestureDetector(
                          onTap: () => setState(() => _hdMode[camId] = !isHd),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isHd ? const Color(0xFFFF3B30) : const Color(0x66FFFFFF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isHd ? "HD" : "SD",
                              style: const TextStyle(
                                color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
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

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Full-screen video
            Positioned.fill(
              child: _useMjpeg
                  ? InteractiveViewer(
                      child: MjpegStreamPlayer(
                        url: _getMjpegStreamUrl(camera),
                        fit: BoxFit.contain,
                        key: ValueKey('mjpeg_fs_${camera['id']}'),
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              "Lỗi tải luồng MJPEG\n$error",
                              style: const TextStyle(color: Color(0xFFFF3B30)),
                            ),
                          );
                        },
                      ),
                    )
                  : _Go2rtcWebView(
                      url: _getStreamUrl(camera, forceHd: true),
                      key: ValueKey('fullscreen_${camera['id']}'),
                    ),
            ),
            // Top overlay bar
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                        onPressed: _exitFullscreen,
                      ),
                      Expanded(
                        child: Text(
                          camera['name'] ?? 'Camera',
                          style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.white, size: 8),
                            SizedBox(width: 4),
                            Text("LIVE HD", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// WebView widget that loads go2rtc stream player
class _Go2rtcWebView extends StatefulWidget {
  final String url;
  const _Go2rtcWebView({super.key, required this.url});

  @override
  State<_Go2rtcWebView> createState() => _Go2rtcWebViewState();
}

class _Go2rtcWebViewState extends State<_Go2rtcWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
          // Clean up go2rtc UI, make video fill container, auto-play muted
          _controller.runJavaScript('''
            document.body.style.margin = '0';
            document.body.style.padding = '0';
            document.body.style.overflow = 'hidden';
            document.body.style.backgroundColor = '#000';
            var video = document.querySelector('video');
            if (video) {
              video.style.width = '100%';
              video.style.height = '100%';
              video.style.objectFit = 'contain';
              video.muted = true;
              video.playsInline = true;
              video.autoplay = true;
              video.play().catch(function(){});
            }
            // Hide non-video UI elements (buttons, dropdowns)
            var btns = document.querySelectorAll('button, select, input');
            btns.forEach(function(el){ el.style.display = 'none'; });
          ''');
        },
        onWebResourceError: (error) {
          if (mounted) {
            setState(() {
              _error = error.description;
              _isLoading = false;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 28),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(_error!,
                  style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B30), strokeWidth: 2),
            ),
          ),
      ],
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

class _MjpegStreamPlayerState extends State<MjpegStreamPlayer> {
  Uint8List? _frameBytes;
  StreamSubscription? _subscription;
  HttpClient? _client;
  Object? _error;
  bool _isLoading = true;
  int _retryCount = 0;
  static const int _maxRetries = 3;

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
    _stopStreaming();
    super.dispose();
  }

  void _startStreaming() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _frameBytes = null;
      _isLoading = true;
    });

    _client = HttpClient();
    _client!.connectionTimeout = const Duration(seconds: 10);
    // Allow self-signed certificates (important for local network on iOS)
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
            
            // Search for JPEG SOI marker (0xFF 0xD8) as a fallback detection method
            // Primary: Content-Length header parsing
            final maxScan = buffer.length > 2000 ? 2000 : buffer.length;
            final str = String.fromCharCodes(buffer.sublist(0, maxScan));
            final lowerStr = str.toLowerCase();
            final lenIdx = lowerStr.indexOf('content-length:');
            if (lenIdx == -1) {
              // If we have accumulated too much data but no header, clear buffer to prevent OOM
              if (buffer.length > 131072) {
                buffer.clear();
              }
              break;
            }

            final lineEndIdx = str.indexOf('\r\n', lenIdx);
            if (lineEndIdx == -1) break;

            final lenStr = str.substring(lenIdx + 15, lineEndIdx).trim();
            final contentLength = int.tryParse(lenStr);
            if (contentLength == null) {
              buffer = buffer.sublist(lineEndIdx);
              continue;
            }

            final headerEndIdx = str.indexOf('\r\n\r\n', lenIdx);
            if (headerEndIdx == -1) break;

            final payloadStartIdx = headerEndIdx + 4;
            final payloadEndIdx = payloadStartIdx + contentLength;

            if (buffer.length < payloadEndIdx) {
              break;
            }

            final frame = Uint8List.fromList(buffer.sublist(payloadStartIdx, payloadEndIdx));
            if (mounted) {
              setState(() {
                _frameBytes = frame;
                _error = null;
                _isLoading = false;
              });
              _retryCount = 0; // Reset retry count on successful frame
            }

            buffer = buffer.sublist(payloadEndIdx);
          }
        },
        onError: (err) {
          if (mounted) {
            if (_retryCount < _maxRetries) {
              _retryCount++;
              _stopStreaming();
              Future.delayed(Duration(seconds: _retryCount), () {
                if (mounted) _startStreaming();
              });
            } else {
              setState(() {
                _error = err;
                _isLoading = false;
              });
            }
          }
        },
        onDone: () {
          // Stream ended unexpectedly - auto-retry
          if (mounted && _retryCount < _maxRetries) {
            _retryCount++;
            _stopStreaming();
            Future.delayed(Duration(seconds: _retryCount), () {
              if (mounted) _startStreaming();
            });
          }
        },
        cancelOnError: false,
      );
    }).catchError((err) {
      if (mounted) {
        if (_retryCount < _maxRetries) {
          _retryCount++;
          _stopStreaming();
          Future.delayed(Duration(seconds: _retryCount), () {
            if (mounted) _startStreaming();
          });
        } else {
          setState(() {
            _error = err;
            _isLoading = false;
          });
        }
      }
    });
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
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!, null);
      }
      return Center(
        child: Text(
          'Error: $_error',
          style: const TextStyle(color: Colors.red),
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
