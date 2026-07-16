class VideoFile {
  final String filename;
  final String time;
  final int startSeconds;
  final double duration;
  final double sizeMb;
  final String codec;
  final String pixFmt;
  final bool hasCache;
  final String directUrl;
  final String? cacheUrl;
  final String transcodeUrl;
  final String downloadUrl;
  final String url;

  VideoFile({
    required this.filename,
    required this.time,
    required this.startSeconds,
    required this.duration,
    required this.sizeMb,
    required this.codec,
    required this.pixFmt,
    required this.hasCache,
    required this.directUrl,
    this.cacheUrl,
    required this.transcodeUrl,
    required this.downloadUrl,
    required this.url,
  });

  factory VideoFile.fromJson(Map<String, dynamic> json) {
    return VideoFile(
      filename: json['filename'] as String? ?? '',
      time: json['time'] as String? ?? '',
      startSeconds: json['start_seconds'] as int? ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      sizeMb: (json['size_mb'] as num?)?.toDouble() ?? 0.0,
      codec: json['codec'] as String? ?? 'unknown',
      pixFmt: json['pix_fmt'] as String? ?? '',
      hasCache: json['has_cache'] as bool? ?? false,
      directUrl: json['direct_url'] as String? ?? '',
      cacheUrl: json['cache_url'] as String?,
      transcodeUrl: json['transcode_url'] as String? ?? '',
      downloadUrl: json['download_url'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  bool get isH264 => codec.toLowerCase() == 'h264' || codec.toLowerCase() == 'avc';
  bool get isHevc => codec.toLowerCase() == 'hevc' || codec.toLowerCase() == 'h265';
  
  // Bắt buộc đi qua luồng stream api đối với camera Yoosee (Cam 3) để bỏ audio lỗi
  bool get needsTranscode {
    if (directUrl.contains('/recordings/3/')) {
      return true;
    }
    return !isH264 && !isHevc;
  }

  bool get canPlayDirect {
    if (directUrl.contains('/recordings/3/')) {
      return false;
    }
    return isH264 || isHevc;
  }
}
