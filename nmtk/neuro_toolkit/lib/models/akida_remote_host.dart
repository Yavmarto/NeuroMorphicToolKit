class AkidaRemoteHost {
  const AkidaRemoteHost({
    required this.id,
    required this.displayName,
    required this.baseUrl,
  });

  final String id;
  final String displayName;
  final String baseUrl;

  factory AkidaRemoteHost.fromJson(Map<String, dynamic> json) {
    return AkidaRemoteHost(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Remote Akida Host',
      baseUrl: json['baseUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'baseUrl': baseUrl,
  };

  AkidaRemoteHost copyWith({String? id, String? displayName, String? baseUrl}) {
    return AkidaRemoteHost(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}
