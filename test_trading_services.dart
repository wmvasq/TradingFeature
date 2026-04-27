import 'dart:math';
import 'package:myenglishtool/models/trading_models.dart';
import 'package:myenglishtool/services/market_data_service.dart';
import 'package:myenglishtool/services/indicators_service.dart';
import 'package:myenglishtool/services/signal_engine.dart';
import 'package:myenglishtool/services/backtesting_service.dart';

/// Script de prueba standalone para validar servicios de trading
///
/// Uso: dart run test_trading_services.dart
///
/// NOTA: Requiere conexión a internet para Binance API
void main() async {
  print('═' * 60);
  print('   TESTING TRADING SERVICES - Jaime Merino Strategy');
  print('═' * 60);

  // ============================================
  // TEST 1: MarketDataService
  // ============================================
  print('\n📡 TEST 1: MarketDataService');
  print('- ' * 30);

  final marketData = MarketDataService();

  try {
    // Test: Obtener datos de BTCUSDT
    print('Obteniendo 100 velas de BTCUSDT (1h)...');
    List<Candle> candles = await marketData.fetchBinanceKlines(
      symbol: 'BTCUSDT',
      interval: '1h',
      limit: 100,
    );

    if (candles.isNotEmpty) {
      print('✅ Datos recibidos: ${candles.length} velas');
      print(
        '   Primera: ${candles.first.timestamp} - Close: \$${candles.first.close}',
      );
      print(
        '   Última: ${candles.last.timestamp} - Close: \$${candles.last.close}',
      );

      // Test: Precio actual
      double currentPrice = await marketData.getCurrentBTCPrice();
      print('   Precio actual BTC: \$${currentPrice.toStringAsFixed(2)}');
    } else {
      print('❌ No se recibieron datos');
    }
  } catch (e) {
    print('❌ Error en MarketDataService: $e');
  }

  // ============================================
  // TEST 2: Indicadores Técnicos
  // ============================================
  print('\n📊 TEST 2: TechnicalIndicatorsService');
  print('- ' * 30);

  if (candles.isNotEmpty) {
    List<double> closes = candles.map((c) => c.close).toList();
    List<double> highs = candles.map((c) => c.high).toList();
    List<double> lows = candles.map((c) => c.low).toList();

    // Test EMA
    print('Calculando EMA(9), EMA(20), EMA(50)...');
    var emas = TechnicalIndicatorsService.calculateMultipleEMAs(closes, {
      'ema9': 9,
      'ema20': 20,
      'ema50': 50,
    });

    int lastIdx = closes.length - 1;
    double? ema9 = emas['ema9']?[lastIdx];
    double? ema20 = emas['ema20']?[lastIdx];
    double? ema50 = emas['ema50']?[lastIdx];

    print('   EMA9: ${ema9?.toStringAsFixed(2) ?? 'null'}');
    print('   EMA20: ${ema20?.toStringAsFixed(2) ?? 'null'}');
    print('   EMA50: ${ema50?.toStringAsFixed(2) ?? 'null'}');

    if (ema9 != null && ema20 != null && ema50 != null) {
      print(
        '   Alineación: EMA9 > EMA20 > EMA50? ${ema9 > ema20 && ema20 > ema50}',
      );
    }

    // Test ADX
    print('\nCalculando ADX(14)...');
    var adxData = TechnicalIndicatorsService.calculateADX(
      highs,
      lows,
      closes,
      14,
    );
    double? adx = adxData['ADX']?[lastIdx];
    double? plusDI = adxData['+DI']?[lastIdx];
    double? minusDI = adxData['-DI']?[lastIdx];

    print('   ADX: ${adx?.toStringAsFixed(2) ?? 'null'}');
    print('   +DI: ${plusDI?.toStringAsFixed(2) ?? 'null'}');
    print('   -DI: ${minusDI?.toStringAsFixed(2) ?? 'null'}');
    print('   Tendencia fuerte? ${adx != null && adx > 25}');

    // Test Squeeze
    print('\nCalculando Squeeze Momentum...');
    var squeeze = TechnicalIndicatorsService.calculateSqueezeMomentum(
      highs,
      lows,
      closes,
    );
    double? sq = squeeze[lastIdx];
    print('   Squeeze: ${sq?.toStringAsFixed(4) ?? 'null'}');
    print('   Momentum positivo? ${sq != null && sq > 0}');

    // Test RSI
    print('\nCalculando RSI(14)...');
    var rsi = TechnicalIndicatorsService.calculateRSI(closes, 14);
    double? rsiVal = rsi[lastIdx];
    print('   RSI: ${rsiVal?.toStringAsFixed(2) ?? 'null'}');
  }

  // ============================================
  // TEST 3: SignalEngine
  // ============================================
  print('\n🎯 TEST 3: SignalEngine (Estrategia Merino)');
  print('- ' * 30);

  if (candles.length >= 200) {
    try {
      final config = TradingConfig();
      final engine = TradingSignalEngine(
        config: config,
        candles: candles.sublist(candles.length - 200), // Últimas 200 velas
      );

      TradingSignal signal = engine.generateSignal();

      print('✅ Señal generada:');
      print('   Tipo: ${signal.type}');
      print('   Confianza: ${(signal.confidence * 100).toStringAsFixed(1)}%');
      print('   Razón: ${signal.reason}');

      if (signal.entryPrice != null) {
        print('   Entrada: \$${signal.entryPrice!.toStringAsFixed(2)}');
        print(
          '   Stop Loss: \$${signal.stopLoss?.toStringAsFixed(2) ?? 'N/A'}',
        );
        print('   TP1: \$${signal.takeProfit1?.toStringAsFixed(2) ?? 'N/A'}');
        print('   TP2: \$${signal.takeProfit2?.toStringAsFixed(2) ?? 'N/A'}');
        print('   TP3: \$${signal.takeProfit3?.toStringAsFixed(2) ?? 'N/A'}');
      }

      print('\n   Indicadores clave:');
      signal.technicalData.forEach((key, value) {
        if (value is num) {
          print('     $key: ${value.toStringAsFixed(4)}');
        }
      });

      if (signal.detailedReasons.isNotEmpty) {
        print('\n   Detalles:');
        signal.detailedReasons.forEach((r) => print('     • $r'));
      }

      if (signal.warnings.isNotEmpty) {
        print('\n   Advertencias:');
        signal.warnings.forEach((w) => print('     ⚠️ $w'));
      }
    } catch (e) {
      print('❌ Error en SignalEngine: $e');
    }
  } else {
    print(
      '⚠️ Datos insuficientes para SignalEngine (necesita >=200 velas, tiene ${candles.length})',
    );
  }

  // ============================================
  // TEST 4: BacktestingService
  // ============================================
  print('\n📈 TEST 4: BacktestingService');
  print('- ' * 30);

  if (candles.length >= 500) {
    try {
      final config = TradingConfig();
      final backtester = BacktestingService(
        config: config,
        marketData: marketData,
      );

      print('Ejecutando backtest con ${candles.length} velas...');
      BacktestResult result = await backtester.runBacktest(
        candles: candles,
        initialCapital: 10000.0,
        commission: 0.001,
      );

      print('✅ Backtest completado:');
      print(
        '   Capital inicial: \$${result.initialCapital.toStringAsFixed(2)}',
      );
      print('   Capital final: \$${result.finalBalance.toStringAsFixed(2)}');
      print('   Retorno: ${result.totalReturn.toStringAsFixed(2)}%');
      print('   Trades totales: ${result.tradesCount}');
      print('   Win Rate: ${result.winRate.toStringAsFixed(1)}%');
      print('   Profit Factor: ${result.profitFactor.toStringAsFixed(2)}');
      print('   Máx Drawdown: ${result.maxDrawdown.toStringAsFixed(2)}%');
      print('   Sharpe Ratio: ${result.sharpeRatio.toStringAsFixed(2)}');
      print('   Calificación: ${result.grade}');

      if (result.bestTrade != null) {
        print(
          '\n   Mejor trade: +\$${result.bestTrade!.profit.toStringAsFixed(2)} (${result.bestTrade!.profitPercent.toStringAsFixed(2)}%)',
        );
      }
      if (result.worstTrade != null) {
        print(
          '   Peor trade: -\$${result.worstTrade!.loss.toStringAsFixed(2)} (${result.worstTrade!.profitPercent.toStringAsFixed(2)}%)',
        );
      }
    } catch (e) {
      print('❌ Error en BacktestingService: $e');
    }
  } else {
    print('⚠️ Datos insuficientes para backtest (necesita >=500 velas)');
  }

  // ============================================
  // TEST 5: Configuraciones
  // ============================================
  print('\n⚙️  TEST 5: TradingConfig');
  print('- ' * 30);

  final config = TradingConfig();
  print('Config por defecto:');
  print('   Capital: \$${config.totalCapital}');
  print('   Distribución: ${config.capitalAllocation}');
  print(
    '   EMAs: ${config.emaFastPeriod}, ${config.emaMediumPeriod}, ${config.emaSlowPeriod}, ${config.emaLongPeriod}',
  );
  print('   ADX: período ${config.adxPeriod}, umbral ${config.adxThreshold}');
  print(
    '   Riesgo max/trade: ${(config.maxRiskPerTrade * 100).toStringAsFixed(1)}%',
  );
  print(
    '   SL por defecto: ${(config.defaultStopLoss * 100).toStringAsFixed(1)}%',
  );

  print('\n' + '═' * 60);
  print('   TESTS COMPLETADOS');
  print('═' * 60);
}
