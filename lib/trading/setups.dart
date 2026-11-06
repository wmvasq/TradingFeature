import 'models.dart';

/// Estado de seguimiento de un setup guardado.
enum SetupState {
  /// Esperando que el precio llegue a la entrada (setup "en espera").
  pending,

  /// Entrada activada, esperando SL o TP.
  open,
  won,
  lost,

  /// No llegó a entrar a tiempo, o el precio fue al TP sin pasar por la entrada.
  expired;

  bool get isFinal => this == won || this == lost || this == expired;
}

enum SetupOrigin { auto, manual }

class SavedSetup {
  final int? id;
  final String symbol;
  final String assetLabel;
  final String interval;
  final String strategy;
  final Direction direction;
  final SetupOrigin origin;
  final SetupState state;
  final double entry;
  final double stopLoss;
  final double takeProfit;
  final String summary;

  /// Apertura de la vela (cerrada) en la que se detectó el setup.
  final DateTime signalTime;
  final DateTime createdAt;
  final DateTime? triggeredAt;
  final DateTime? resolvedAt;

  /// Última vela ya revisada; el seguimiento continúa desde aquí.
  final DateTime checkedUntil;
  final int candlesChecked;

  const SavedSetup({
    this.id,
    required this.symbol,
    required this.assetLabel,
    required this.interval,
    required this.strategy,
    required this.direction,
    required this.origin,
    required this.state,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.summary,
    required this.signalTime,
    required this.createdAt,
    required this.checkedUntil,
    this.triggeredAt,
    this.resolvedAt,
    this.candlesChecked = 0,
  });

  /// Crea un setup a partir del resultado de una estrategia.
  /// Devuelve null si el resultado no tiene niveles (no se puede seguir).
  static SavedSetup? fromResult({
    required StrategyResult result,
    required String symbol,
    required String assetLabel,
    required String interval,
    required String strategy,
    required DateTime signalTime,
    required SetupOrigin origin,
  }) {
    final direction = result.direction;
    if (result.status == SetupStatus.none ||
        direction == null ||
        result.entry == null ||
        result.stopLoss == null ||
        result.takeProfit == null) {
      return null;
    }
    final isEntry = result.status == SetupStatus.entry;
    return SavedSetup(
      symbol: symbol,
      assetLabel: assetLabel,
      interval: interval,
      strategy: strategy,
      direction: direction,
      origin: origin,
      state: isEntry ? SetupState.open : SetupState.pending,
      entry: result.entry!,
      stopLoss: result.stopLoss!,
      takeProfit: result.takeProfit!,
      summary: result.summary,
      signalTime: signalTime,
      createdAt: DateTime.now(),
      triggeredAt: isEntry ? signalTime : null,
      checkedUntil: signalTime,
    );
  }

  /// Identifica el setup para no guardarlo dos veces. Una entrada es única
  /// por su vela; un setup en espera se repite vela tras vela con el mismo
  /// precio de entrada, así que se identifica por ese precio.
  String get key {
    final base = '$symbol|$interval|$strategy|${direction.name}';
    return triggeredAt == signalTime
        ? '$base|E|${signalTime.millisecondsSinceEpoch}'
        : '$base|W|${entry.toStringAsPrecision(10)}';
  }

  bool get isLong => direction == Direction.long;

  double get plannedRiskReward =>
      (takeProfit - entry).abs() / (entry - stopLoss).abs();

  /// Resultado en R: +R:R si ganó, -1 si perdió, null si no está cerrado.
  double? get resultR => switch (state) {
    SetupState.won => plannedRiskReward,
    SetupState.lost => -1,
    _ => null,
  };

  SavedSetup copyWith({
    int? id,
    SetupState? state,
    DateTime? triggeredAt,
    DateTime? resolvedAt,
    DateTime? checkedUntil,
    int? candlesChecked,
  }) {
    return SavedSetup(
      id: id ?? this.id,
      symbol: symbol,
      assetLabel: assetLabel,
      interval: interval,
      strategy: strategy,
      direction: direction,
      origin: origin,
      state: state ?? this.state,
      entry: entry,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      summary: summary,
      signalTime: signalTime,
      createdAt: createdAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      checkedUntil: checkedUntil ?? this.checkedUntil,
      candlesChecked: candlesChecked ?? this.candlesChecked,
    );
  }
}

/// Avanza el seguimiento de [setup] con las velas cerradas posteriores.
/// Es incremental: solo mira velas después de `checkedUntil`.
///
/// Reglas (conservadoras):
/// - En espera: se activa cuando una vela toca la entrada. Si en esa misma
///   vela también toca el SL, cuenta como perdido. Si el precio llega al TP
///   sin haber entrado, o pasan [expiryCandles] velas, expira.
/// - Abierto: si una vela toca SL y TP a la vez, cuenta como perdido.
SavedSetup trackSetup(
  SavedSetup setup,
  List<Candle> candles, {
  int expiryCandles = 50,
}) {
  var s = setup;
  for (final c in candles) {
    if (s.state.isFinal) break;
    if (!c.openTime.isAfter(s.checkedUntil)) continue;

    final long = s.isLong;
    final hitStop = long ? c.low <= s.stopLoss : c.high >= s.stopLoss;
    final hitTarget = long ? c.high >= s.takeProfit : c.low <= s.takeProfit;
    s = s.copyWith(
      checkedUntil: c.openTime,
      candlesChecked: s.candlesChecked + 1,
    );

    if (s.state == SetupState.pending) {
      final touchedEntry = long ? c.low <= s.entry : c.high >= s.entry;
      if (touchedEntry) {
        s = hitStop
            ? s.copyWith(
                state: SetupState.lost,
                triggeredAt: c.openTime,
                resolvedAt: c.openTime,
              )
            : s.copyWith(state: SetupState.open, triggeredAt: c.openTime);
      } else if (hitTarget || s.candlesChecked >= expiryCandles) {
        s = s.copyWith(state: SetupState.expired, resolvedAt: c.openTime);
      }
    } else if (hitStop) {
      s = s.copyWith(state: SetupState.lost, resolvedAt: c.openTime);
    } else if (hitTarget) {
      s = s.copyWith(state: SetupState.won, resolvedAt: c.openTime);
    }
  }
  return s;
}

/// Estadísticas de los setups cerrados (ganados + perdidos).
class SetupStats {
  final int total;
  final int won;
  final int lost;
  final int active;
  final double totalR;

  const SetupStats({
    required this.total,
    required this.won,
    required this.lost,
    required this.active,
    required this.totalR,
  });

  factory SetupStats.of(List<SavedSetup> setups) {
    var won = 0, lost = 0, active = 0;
    var totalR = 0.0;
    for (final s in setups) {
      switch (s.state) {
        case SetupState.won:
          won++;
        case SetupState.lost:
          lost++;
        case SetupState.pending || SetupState.open:
          active++;
        case SetupState.expired:
          break;
      }
      totalR += s.resultR ?? 0;
    }
    return SetupStats(
      total: setups.length,
      won: won,
      lost: lost,
      active: active,
      totalR: totalR,
    );
  }

  int get closed => won + lost;
  double? get winRate => closed == 0 ? null : won / closed;
}
