import '../diff.dart';

class MemStats {
  final int totalKb;
  final int usedKb;
  final int availKb;
  final int swapTotalKb;
  final int swapUsedKb;
  final DateTime sampledAt;

  MemStats({
    required this.totalKb,
    required this.usedKb,
    required this.availKb,
    required this.swapTotalKb,
    required this.swapUsedKb,
    required this.sampledAt,
  });

  double get usedPct => totalKb == 0 ? 0 : (usedKb / totalKb) * 100;
  double get swapUsedPct =>
      swapTotalKb == 0 ? 0 : (swapUsedKb / swapTotalKb) * 100;

  Map<String, dynamic> toJson() => {
        'totalKb': totalKb,
        'usedKb': usedKb,
        'availKb': availKb,
        'swapTotalKb': swapTotalKb,
        'swapUsedKb': swapUsedKb,
        'sampledAt': sampledAt.toUtc().toIso8601String(),
      };

  factory MemStats.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return MemStats(
      totalKb: (j['totalKb'] as num).toInt(),
      usedKb: (j['usedKb'] as num).toInt(),
      availKb: (j['availKb'] as num).toInt(),
      swapTotalKb: (j['swapTotalKb'] as num).toInt(),
      swapUsedKb: (j['swapUsedKb'] as num).toInt(),
      sampledAt: DateTime.parse(j['sampledAt'] as String),
    );
  }

  /// Significant change: usedPct or swapUsedPct moved >= [pctEpsilon].
  bool changedFrom(MemStats? other, {double pctEpsilon = 1.0}) {
    if (other == null) return true;
    return Diff.numChanged(usedPct, other.usedPct, epsilon: pctEpsilon) ||
        Diff.numChanged(swapUsedPct, other.swapUsedPct, epsilon: pctEpsilon);
  }
}
