class VideoFile {
  final String filename;
  final String time;
  final int startSeconds;
  final double duration;
  final double sizeMb;
  final String codec;
  final String pixFmt;
  final bool hasCache;
  final bool needsTranscode;
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
    required this.needsTranscode,
    required this.directUrl,
    this.cacheUrl,
    required this.transcodeUrl,
    required this.downloadUrl,
    required this.url,
  });

  factory VideoFile.fromJson(Map<String, dynamic> json) {
    final codecVal = json['codec'] as String? ?? 'unknown';
    final isH264 = codecVal.toLowerCase() == 'h264' || codecVal.toLowerCase() == 'avc';
    final defaultNeedsTranscode = !isH264;

    return VideoFile(
      filename: json['filename'] as String? ?? '',
      time: json['time'] as String? ?? '',
      startSeconds: json['start_seconds'] as int? ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      sizeMb: (json['size_mb'] as num?)?.toDouble() ?? 0.0,
      codec: codecVal,
      pixFmt: json['pix_fmt'] as String? ?? '',
      hasCache: json['has_cache'] as bool? ?? false,
      needsTranscode: json['needs_transcode'] as bool? ?? defaultNeedsTranscode,
      directUrl: json['direct_url'] as String? ?? '',
      cacheUrl: json['cache_url'] as String?,
      transcodeUrl: json['transcode_url'] as String? ?? '',
      downloadUrl: json['download_url'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  bool get isH264 => codec.toLowerCase() == 'h264' || codec.toLowerCase() == 'avc';
  bool get isHevc => codec.toLowerCase() == 'hevc' || codec.toLowerCase() == 'h265';

  bool get canPlayDirect {
    return !needsTranscode;
  }
}
