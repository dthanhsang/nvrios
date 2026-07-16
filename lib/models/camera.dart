class Camera {
  final int id;
  final String name;
  final String rtspUrl;
  final String? rtspUrlSub;
  final String protocol;
  final String go2rtcSrc;
  final bool enabled;

  Camera({
    required this.id,
    required this.name,
    required this.rtspUrl,
    this.rtspUrlSub,
    required this.protocol,
    required this.go2rtcSrc,
    required this.enabled,
  });

  factory Camera.fromJson(Map<String, dynamic> json) {
    return Camera(
      id: json['id'] as int,
      name: json['name'] as String,
      rtspUrl: json['rtsp_url'] as String,
      rtspUrlSub: json['rtsp_url_sub'] as String?,
      protocol: json['protocol'] as String? ?? 'tcp',
      go2rtcSrc: json['go2rtc_src'] as String,
      enabled: (json['enabled'] as int? ?? 1) == 1,
    );
  }

  Map<String, String> toFormData() => {
    'name': name,
    'rtsp_url': rtspUrl,
    'rtsp_url_sub': rtspUrlSub ?? '',
    'protocol': protocol,
    'go2rtc_src': go2rtcSrc,
    'enabled': enabled ? '1' : '0',
  };
}
