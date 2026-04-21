enum Severity { info, warn, crit }

class Alert {
  /// Stable identifier for grouping the same alert across samples
  /// (e.g. `cpu.high`, `disk.full.<mount>`).
  final String id;
  final Severity severity;
  final String metric;
  final double value;
  final double threshold;
  final String message;
  final DateTime since;

  Alert({
    required this.id,
    required this.severity,
    required this.metric,
    required this.value,
    required this.threshold,
    required this.message,
    required this.since,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.name,
        'metric': metric,
        'value': value,
        'threshold': threshold,
        'message': message,
        'since': since.toUtc().toIso8601String(),
      };

  factory Alert.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return Alert(
      id: j['id'] as String,
      severity: Severity.values.byName(j['severity'] as String),
      metric: j['metric'] as String,
      value: (j['value'] as num).toDouble(),
      threshold: (j['threshold'] as num).toDouble(),
      message: j['message'] as String,
      since: DateTime.parse(j['since'] as String),
    );
  }
}

class AlertList {
  final List<Alert> active;
  final DateTime sampledAt;

  AlertList({required this.active, required this.sampledAt});

  Severity? get worstSeverity {
    if (active.isEmpty) return null;
    return active
        .map((a) => a.severity)
        .reduce((a, b) => a.index >= b.index ? a : b);
  }

  Map<String, dynamic> toJson() => {
        'active': active.map((a) => a.toJson()).toList(),
        'sampledAt': sampledAt.toUtc().toIso8601String(),
      };

  factory AlertList.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return AlertList(
      active: (j['active'] as List).map(Alert.fromJson).toList(growable: false),
      sampledAt: DateTime.parse(j['sampledAt'] as String),
    );
  }

  /// True when the active id-set differs from [other], or any value moved
  /// across the threshold boundary.
  bool changedFrom(AlertList? other) {
    if (other == null) return active.isNotEmpty;
    if (other.active.length != active.length) return true;
    final otherById = {for (final a in other.active) a.id: a};
    for (final a in active) {
      if (!otherById.containsKey(a.id)) return true;
      // severity escalation/de-escalation matters
      if (otherById[a.id]!.severity != a.severity) return true;
    }
    return false;
  }
}
