import '../diff.dart';

/// Per-core CPU usage and load average for a host.
class CpuStats {
  /// Per-core usage 0..100 (rounded to 1 decimal).
  final List<double> coreUsage;

  /// 1, 5, 15-minute load averages.
  final List<double> loadAvg;

  /// Optional CPU temperature in degrees C. Null when not available.
  final double? tempC;

  /// Wall-clock time on the agent when this sample was taken (UTC).
  final DateTime sampledAt;

  CpuStats({
    required this.coreUsage,
    required this.loadAvg,
    required this.sampledAt,
    this.tempC,
  });

  /// Maximum reported core usage 0..100.
  double get maxCore =>
      coreUsage.isEmpty ? 0 : coreUsage.reduce((a, b) => a > b ? a : b);

  /// Mean reported core usage 0..100.
  double get meanCore => coreUsage.isEmpty
      ? 0
      : coreUsage.reduce((a, b) => a + b) / coreUsage.length;

  Map<String, dynamic> toJson() => {
        'coreUsage': coreUsage,
        'loadAvg': loadAvg,
        if (tempC != null) 'tempC': tempC,
        'sampledAt': sampledAt.toUtc().toIso8601String(),
      };

  factory CpuStats.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return CpuStats(
      coreUsage:
          (j['coreUsage'] as List).map((e) => (e as num).toDouble()).toList(),
      loadAvg:
          (j['loadAvg'] as List).map((e) => (e as num).toDouble()).toList(),
      tempC: (j['tempC'] as num?)?.toDouble(),
      sampledAt: DateTime.parse(j['sampledAt'] as String),
    );
  }

  /// Significant change vs [other]: any core moved >= [coreEpsilon] %, or
  /// load avg moved >= [loadEpsilon].
  bool changedFrom(CpuStats? other,
      {double coreEpsilon = 2.0, double loadEpsilon = 0.05}) {
    if (other == null) return true;
    return Diff.numListChanged(coreUsage, other.coreUsage,
            epsilon: coreEpsilon) ||
        Diff.numListChanged(loadAvg, other.loadAvg, epsilon: loadEpsilon);
  }
}
