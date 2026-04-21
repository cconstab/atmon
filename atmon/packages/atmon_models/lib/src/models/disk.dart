import '../diff.dart';

class FilesystemStats {
  final String mount;
  final String fsType;
  final int sizeKb;
  final int usedKb;

  FilesystemStats({
    required this.mount,
    required this.fsType,
    required this.sizeKb,
    required this.usedKb,
  });

  double get usedPct => sizeKb == 0 ? 0 : (usedKb / sizeKb) * 100;

  Map<String, dynamic> toJson() => {
        'mount': mount,
        'fsType': fsType,
        'sizeKb': sizeKb,
        'usedKb': usedKb,
      };

  factory FilesystemStats.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return FilesystemStats(
      mount: j['mount'] as String,
      fsType: j['fsType'] as String,
      sizeKb: (j['sizeKb'] as num).toInt(),
      usedKb: (j['usedKb'] as num).toInt(),
    );
  }
}

class DiskStats {
  final List<FilesystemStats> filesystems;
  final DateTime sampledAt;

  DiskStats({required this.filesystems, required this.sampledAt});

  Map<String, dynamic> toJson() => {
        'filesystems': filesystems.map((f) => f.toJson()).toList(),
        'sampledAt': sampledAt.toUtc().toIso8601String(),
      };

  factory DiskStats.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return DiskStats(
      filesystems: (j['filesystems'] as List)
          .map(FilesystemStats.fromJson)
          .toList(growable: false),
      sampledAt: DateTime.parse(j['sampledAt'] as String),
    );
  }

  /// Significant change: a mount appeared/disappeared, or any mount's used%
  /// moved >= [pctEpsilon].
  bool changedFrom(DiskStats? other, {double pctEpsilon = 0.5}) {
    if (other == null) return true;
    if (other.filesystems.length != filesystems.length) return true;
    final otherByMount = {for (final f in other.filesystems) f.mount: f};
    for (final f in filesystems) {
      final o = otherByMount[f.mount];
      if (o == null) return true;
      if (Diff.numChanged(f.usedPct, o.usedPct, epsilon: pctEpsilon)) {
        return true;
      }
    }
    return false;
  }
}
