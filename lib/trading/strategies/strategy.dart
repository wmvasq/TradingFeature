import '../models.dart';
import 'merino_strategy.dart';
import 'smc_strategy.dart';

/// Una estrategia recibe velas cerradas y dice si hay entrada.
/// Para agregar una nueva: implementar esta clase y registrarla en [strategies].
abstract class Strategy {
  String get name;
  String get description;

  /// Velas mínimas para poder evaluar.
  int get minCandles;

  StrategyResult evaluate(List<Candle> candles);
}

final List<Strategy> strategies = [SmcStrategy(), MerinoStrategy()];
