import '../diff.dart';

class IfaceStats {
  final String name;
  final double rxKbps;
  final double txKbps;
  final int errors;

  IfaceStats({
    required this.name,
    required this.rxKbps,
    required this.txKbps,
    required this.errors,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'rxKbps': rxKbps,
        'txKbps': txKbps,
        'errors': errors,
      };

  factory IfaceStats.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return IfaceStats(
      name: j['name'] as String,
      rxKbps: (j['rxKbps'] as num).toDouble(),
      txKbps: (j['txKbps'] as num).toDouble(),
      errors: (j['errors'] as num).toInt(),
    );
  }
}

class NetStats {
  final List<IfaceStats> ifaces;
  final DateTime sampledAt;

  NetStats({required this.ifaces, required this.sampledAt});

  Map<String, dynamic> toJson() => {
        'ifaces': ifaces.map((i) => i.toJson()).toList(),
        'sampledAt': sampledAt.toUtc().toIso8601String(),
      };

  factory NetStats.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return NetStats(
      ifaces: (j['ifaces'] as List)
          .map(IfaceStats.fromJson)
          .toList(growable: false),
      sampledAt: DateTime.parse(j['sampledAt'] as String),
    );
  }

  /// Significant change: any iface's rx or tx moved >= [kbpsEpsilon] or
  /// error count changed.
  bool changedFrom(NetStats? other, {double kbpsEpsilon = 5.0}) {
    if (other == null) return true;
    if (other.ifaces.length != ifaces.length) return true;
    final otherByName = {for (final i in other.ifaces) i.name: i};
    for (final i in ifaces) {
      final o = otherByName[i.name];
      if (o == null) return true;
      if (Diff.numChanged(i.rxKbps, o.rxKbps, epsilon: kbpsEpsilon) ||
          Diff.numChanged(i.txKbps, o.txKbps, epsilon: kbpsEpsilon) ||
          i.errors != o.errors) {
        return true;
      }
    }
    return false;
  }
}
