/// Vela OHLCV ya cerrada.
class Candle {
  final DateTime openTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  bool get isBullish => close > open;
  bool get isBearish => close < open;
}

enum Direction { long, short }

/// Resultado de evaluar una estrategia sobre las velas.
enum SetupStatus {
  /// La última vela cerrada cumple todas las condiciones obligatorias.
  entry,

  /// Hay un setup válido pero el precio aún no llega a la zona de entrada.
  waiting,

  /// No hay setup.
  none,
}

/// Una condición evaluada por la estrategia (se muestra como ✓ / ✗).
class Condition {
  final String label;
  final bool met;

  /// Si es false, la condición es informativa y no bloquea la entrada.
  final bool required;

  const Condition(this.label, this.met, {this.required = true});
}

/// Zona de precio a dibujar en el gráfico (order block, FVG, etc.).
class PriceZone {
  final String label;
  final double top;
  final double bottom;
  final int startIndex;
  final Direction bias;

  const PriceZone({
    required this.label,
    required this.top,
    required this.bottom,
    required this.startIndex,
    required this.bias,
  });
}

/// Nivel marcado en el gráfico (BOS, CHoCH...), desde [fromIndex] hasta [toIndex].
class PriceLevel {
  final String label;
  final double price;
  final int fromIndex;
  final int toIndex;
  final Direction bias;

  const PriceLevel({
    required this.label,
    required this.price,
    required this.fromIndex,
    required this.toIndex,
    required this.bias,
  });
}

/// Serie de indicador sobre el precio (EMA, etc.), alineada índice a índice
/// con las velas. [color] en formato ARGB (0xAARRGGBB).
class IndicatorLine {
  final String label;
  final List<double?> values;
  final int color;

  const IndicatorLine(this.label, this.values, this.color);
}

class StrategyResult {
  final SetupStatus status;
  final Direction? direction;
  final String summary;
  final double? entry;
  final double? stopLoss;
  final double? takeProfit;
  final List<Condition> conditions;
  final List<PriceZone> zones;
  final List<PriceLevel> levels;
  final List<IndicatorLine> lines;

  const StrategyResult({
    required this.status,
    required this.summary,
    this.direction,
    this.entry,
    this.stopLoss,
    this.takeProfit,
    this.conditions = const [],
    this.zones = const [],
    this.levels = const [],
    this.lines = const [],
  });

  double? get riskReward {
    if (entry == null || stopLoss == null || takeProfit == null) return null;
    final risk = (entry! - stopLoss!).abs();
    if (risk == 0) return null;
    return (takeProfit! - entry!).abs() / risk;
  }
}
