import 'dart:math';
import '../models/trading_models.dart';

/// Servicio para calcular indicadores técnicos
/// Basado en la estrategia de Jaime Merino (TradingLatino)
class TechnicalIndicatorsService {
  // ============================================
  // 1. MEDIAS MÓVILES EXPONENCIALES (EMA)
  // ============================================

  /// Calcula EMA (Exponential Moving Average) para una lista de precios
  ///
  /// [prices] - Lista de precios de cierre (orden: antiguo → reciente)
  /// [period] - Período de la EMA (ej: 9, 20, 50, 200)
  ///
  /// Retorna lista de EMA con misma longitud que [prices]
  /// Los primeros [period-1] valores serán null (no hay suficientes datos)
  static List<double?> calculateEMA(List<double> prices, int period) {
    if (prices.length < period) {
      return List.filled(prices.length, null);
    }

    List<double?> ema = List.filled(prices.length, null);
    double multiplier = 2 / (period + 1);

    // PASO 1: Calcular SMA (Simple Moving Average) para los primeros [period] datos
    double sum = 0.0;
    for (int i = 0; i < period; i++) {
      sum += prices[i];
    }
    double sma = sum / period;
    ema[period - 1] = sma;

    // PASO 2: Calcular EMA recursivamente desde el período [period]
    for (int i = period; i < prices.length; i++) {
      double prevEma = ema[i - 1]!;
      double currentEma = (prices[i] - prevEma) * multiplier + prevEma;
      ema[i] = currentEma;
    }

    return ema;
  }

  /// Calcula múltiples EMAs simultáneamente (eficiente)
  static Map<String, List<double?>> calculateMultipleEMAs(
    List<double> closes,
    Map<String, int> periods,
  ) {
    Map<String, List<double?>> result = {};

    for (var entry in periods.entries) {
      result[entry.key] = calculateEMA(closes, entry.value);
    }

    return result;
  }

  /// Verifica si hay cruce de EMAs (señal de cambio de tendencia)
  static bool hasEMACrossover({
    required List<double?> emaFast,
    required List<double?> emaSlow,
    required int lookback, // cuántas velas atrás revisar (ej: 1 = última vela)
  }) {
    int index = emaFast.length - 1 - lookback;
    if (index < 1) return false;

    // Valores actuales y anteriores
    double? currentFast = emaFast[index];
    double? currentSlow = emaSlow[index];
    double? prevFast = emaFast[index - 1];
    double? prevSlow = emaSlow[index - 1];

    if (currentFast == null ||
        currentSlow == null ||
        prevFast == null ||
        prevSlow == null) {
      return false;
    }

    // Cruce alcista: EMA rápida cruza ARRIBA de la lenta
    bool bullishCross = prevFast <= prevSlow && currentFast > currentSlow;

    // Cruce bajista: EMA rápida cruza ABAJO de la lenta
    bool bearishCross = prevFast >= prevSlow && currentFast < currentSlow;

    return bullishCross || bearishCross;
  }

  /// Verifica alineación de EMAs (tendencia fuerte)
  /// Según Merino: EMA9 > EMA20 > EMA50 = tendencia alcista fuerte
  static bool areEMAsAlignedBullish({
    required List<double?> emaFast, // Ej: EMA9
    required List<double?> emaMedium, // Ej: EMA20
    required List<double?> emaSlow, // Ej: EMA50
    int lookback = 0,
  }) {
    int index = emaFast.length - 1 - lookback;
    if (index < 0) return false;

    double? eFast = emaFast[index];
    double? eMedium = emaMedium[index];
    double? eSlow = emaSlow[index];

    if (eFast == null || eMedium == null || eSlow == null) return false;

    // Tendencia alcista: Fast > Medium > Slow
    return eFast > eMedium && eMedium > eSlow;
  }

  static bool areEMAsAlignedBearish({
    required List<double?> emaFast,
    required List<double?> emaMedium,
    required List<double?> emaSlow,
    int lookback = 0,
  }) {
    int index = emaFast.length - 1 - lookback;
    if (index < 0) return false;

    double? eFast = emaFast[index];
    double? eMedium = emaMedium[index];
    double? eSlow = emaSlow[index];

    if (eFast == null || eMedium == null || eSlow == null) return false;

    // Tendencia bajista: Fast < Medium < Slow
    return eFast < eMedium && eMedium < eSlow;
  }

  // ============================================
  // 2. ADX - AVERAGE DIRECTIONAL INDEX
  // ============================================

  /// Calcula ADX, +DI y -DI usando el método de Welles Wilder
  ///
  /// [high] - Lista de máximos
  /// [low] - Lista de mínimos
  /// [close] - Lista de cierres
  /// [period] - Período típico: 14
  ///
  /// Retorna mapa con 'ADX', '+DI', '-DI' (listas con mismos índices que input)
  static Map<String, List<double?>> calculateADX(
    List<double> high,
    List<double> low,
    List<double> close,
    int period,
  ) {
    if (high.length < period + 1) {
      return {
        'ADX': List.filled(high.length, null),
        '+DI': List.filled(high.length, null),
        '-DI': List.filled(high.length, null),
      };
    }

    int n = high.length;
    List<double?> plusDM = List.filled(n, null);
    List<double?> minusDM = List.filled(n, null);
    List<double?> tr = List.filled(n, null);
    List<double?> smoothedPlusDM = List.filled(n, null);
    List<double?> smoothedMinusDM = List.filled(n, null);
    List<double?> smoothedTR = List.filled(n, null);
    List<double?> plusDI = List.filled(n, null);
    List<double?> minusDI = List.filled(n, null);
    List<double?> dx = List.filled(n, null);
    List<double?> adx = List.filled(n, null);

    // PASO 1: Calcular +DM, -DM y TR para cada período
    for (int i = 1; i < n; i++) {
      double upMove = high[i] - high[i - 1];
      double downMove = low[i - 1] - low[i];

      // +DM: movimiento alcista >movimiento bajista y >0
      if (upMove > downMove && upMove > 0) {
        plusDM[i] = upMove;
      } else {
        plusDM[i] = 0.0;
      }

      // -DM: movimiento bajista > movimiento alcista y >0
      if (downMove > upMove && downMove > 0) {
        minusDM[i] = downMove;
      } else {
        minusDM[i] = 0.0;
      }

      // True Range (TR)
      double tr1 = high[i] - low[i];
      double tr2 = (high[i] - close[i - 1]).abs();
      double tr3 = (low[i] - close[i - 1]).abs();
      tr[i] = [tr1, tr2, tr3].reduce((a, b) => a > b ? a : b);
    }

    // PASO 2: Suavizar con Wilder's Moving Average (primer valor = suma simple)
    // Para los primeros [period] períodos (excluyendo el índice 0)
    double sumPlusDM = 0.0;
    double sumMinusDM = 0.0;
    double sumTR = 0.0;

    for (int i = 1; i <= period; i++) {
      sumPlusDM += plusDM[i] ?? 0.0;
      sumMinusDM += minusDM[i] ?? 0.0;
      sumTR += tr[i] ?? 0.0;
    }

    smoothedPlusDM[period] = sumPlusDM;
    smoothedMinusDM[period] = sumMinusDM;
    smoothedTR[period] = sumTR;

    // PASO 3: Continuar suavizado exponencialmente
    for (int i = period + 1; i < n; i++) {
      smoothedPlusDM[i] =
          ((smoothedPlusDM[i - 1] ?? 0) * (period - 1) + (plusDM[i] ?? 0)) /
          period;
      smoothedMinusDM[i] =
          ((smoothedMinusDM[i - 1] ?? 0) * (period - 1) + (minusDM[i] ?? 0)) /
          period;
      smoothedTR[i] =
          ((smoothedTR[i - 1] ?? 0) * (period - 1) + (tr[i] ?? 0)) / period;
    }

    // PASO 4: Calcular +DI y -DI
    for (int i = period; i < n; i++) {
      if ((smoothedTR[i] ?? 0) > 0) {
        plusDI[i] = (smoothedPlusDM[i] ?? 0) / (smoothedTR[i] ?? 1) * 100;
        minusDI[i] = (smoothedMinusDM[i] ?? 0) / (smoothedTR[i] ?? 1) * 100;
      } else {
        plusDI[i] = 0.0;
        minusDI[i] = 0.0;
      }
    }

    // PASO 5: Calcular DX y ADX
    for (int i = period; i < n; i++) {
      double? pdi = plusDI[i];
      double? mdi = minusDI[i];

      if (pdi != null && mdi != null && (pdi + mdi) > 0) {
        dx[i] = (pdi - mdi).abs() / (pdi + mdi) * 100;
      }
    }

    // PASO 6: Suavizar DX para obtener ADX (usando el primer DX como semilla)
    double sumDX = 0.0;
    int dxCount = 0;
    for (int i = period; i < 2 * period; i++) {
      if (dx[i] != null) {
        sumDX += dx[i]!;
        dxCount++;
      }
    }

    if (dxCount > 0) {
      adx[2 * period - 1] = sumDX / dxCount;
    }

    // Continuar suavizado de ADX
    for (int i = 2 * period; i < n; i++) {
      if (dx[i] != null && adx[i - 1] != null) {
        adx[i] = ((adx[i - 1] ?? 0) * (period - 1) + dx[i]!) / period;
      }
    }

    return {'ADX': adx, '+DI': plusDI, '-DI': minusDI};
  }

  /// Obtiene el valor actual de ADX
  static double? getCurrentADX(
    List<double> high,
    List<double> low,
    List<double> close,
    int period, {
    int offset = 0,
  }) {
    var adxData = calculateADX(high, low, close, period);
    int index = adxData['ADX']!.length - 1 - offset;
    if (index < 0) return null;
    return adxData['ADX']![index];
  }

  /// Obtiene la diferencia entre +DI y -DI (directional movement)
  static double? getDMIStrength(
    List<double> high,
    List<double> low,
    List<double> close,
    int period, {
    int offset = 0,
  }) {
    var adxData = calculateADX(high, low, close, period);
    int index = adxData['+DI']!.length - 1 - offset;
    if (index < 0) return null;

    double? plusDI = adxData['+DI']![index];
    double? minusDI = adxData['-DI']![index];

    if (plusDI == null || minusDI == null) return null;

    return plusDI - minusDI; // Positivo = alcista, Negativo = bajista
  }

  // ============================================
  // 3. SQUEEZE MOMENTUM INDICATOR (LazyBear)
  // ============================================

  /// Detecta "squeeze" (contracción de volatilidad) y momentum
  /// Basado en la combinación de Bollinger Bands y Keltner Channels
  ///
  /// [high], [low], [close] - datos OHLC
  /// [bbPeriod] - Período Bollinger Bands (típico: 20)
  /// [bbStdDev] - Desviación estándar BB (típico: 2.0)
  /// [kcPeriod] - Período Keltner Channel (típico: 20)
  /// [kcMultiplier] - Multiplicador KC (típico: 1.5)
  ///
  /// Retorna valores positivos = squeeze alcista, negativos = squeeze bajista
  /// Cero = no squeeze
  static List<double?> calculateSqueezeMomentum(
    List<double> high,
    List<double> low,
    List<double> close, {
    int bbPeriod = 20,
    double bbStdDev = 2.0,
    int kcPeriod = 20,
    double kcMultiplier = 1.5,
  }) {
    if (close.length < bbPeriod) {
      return List.filled(close.length, null);
    }

    int n = close.length;
    List<double?> squeezeValues = List.filled(n, null);

    // Calcular Bollinger Bands
    List<double?> bbUpper = List.filled(n, null);
    List<double?> bbLower = List.filled(n, null);
    List<double?> bbMiddle = List.filled(n, null);

    for (int i = bbPeriod - 1; i < n; i++) {
      List<double> periodCloses = close.sublist(i - bbPeriod + 1, i + 1);
      double mean = periodCloses.reduce((a, b) => a + b) / bbPeriod;
      double stdDev = _calculateStdDev(periodCloses, mean);

      bbMiddle[i] = mean;
      bbUpper[i] = mean + bbStdDev * stdDev;
      bbLower[i] = mean - bbStdDev * stdDev;
    }

    // Calcular Keltner Channels (usando ATR)
    var atrData = calculateATR(high, low, close, kcPeriod);
    List<double?> atr = atrData['ATR']!;

    for (int i = kcPeriod - 1; i < n; i++) {
      double? middleKC = bbMiddle[i]; // Usamos SMA como línea central del KC
      double? currentATR = atr[i];

      if (middleKC != null && currentATR != null) {
        double upperKC = middleKC + currentATR * kcMultiplier;
        double lowerKC = middleKC - currentATR * kcMultiplier;

        // Lógica del Squeeze:
        // Si Bollinger Bands están DENTRO de Keltner Channels = squeeze
        // Si BB salen FUERA de KC = squeeze ha terminado (explosión)

        if (bbUpper[i] != null && bbLower[i] != null) {
          if (bbUpper[i]! < upperKC && bbLower[i]! > lowerKC) {
            // SQUEEZE: BB dentro de KC (volatilidad baja)
            squeezeValues[i] = 0.0;
          } else if (bbUpper[i]! >= upperKC && close[i] > (bbMiddle[i] ?? 0)) {
            // SQUEEZE ALCISTA: BB superior rompe KC superior + precio arriba de media
            squeezeValues[i] = close[i] - (bbUpper[i]!); // Valor positivo
          } else if (bbLower[i]! <= lowerKC && close[i] < (bbMiddle[i] ?? 0)) {
            // SQUEEZE BAJISTA: BB inferior rompe KC inferior + precio abajo de media
            squeezeValues[i] = close[i] - (bbLower[i]!); // Valor negativo
          } else {
            // En transición
            squeezeValues[i] = 0.0;
          }
        }
      }
    }

    return squeezeValues;
  }

  /// Alternativa más simple: Solo detecta si hay squeeze (sin momentum direccional)
  static List<bool> calculateSimpleSqueeze(
    List<double> close,
    List<double> bbUpper,
    List<double> bbLower,
    List<double> kcUpper,
    List<double> kcLower,
  ) {
    int n = close.length;
    List<bool> squeeze = List.filled(n, false);

    for (int i = 0; i < n; i++) {
      if (bbUpper[i] != null &&
          bbLower[i] != null &&
          kcUpper[i] != null &&
          kcLower[i] != null) {
        // Squeeze = Bollinger Bands completamente dentro de Keltner Channels
        squeeze[i] = bbUpper[i]! < kcUpper[i]! && bbLower[i]! > kcLower[i]!;
      }
    }

    return squeeze;
  }

  // ============================================
  // 4. ATR - AVERAGE TRUE RANGE (para stop loss dinámico)
  // ============================================

  static Map<String, List<double?>> calculateATR(
    List<double> high,
    List<double> low,
    List<double> close,
    int period,
  ) {
    if (high.length < period + 1) {
      return {'ATR': List.filled(high.length, null)};
    }

    int n = high.length;
    List<double?> trueRange = List.filled(n, null);
    List<double?> atr = List.filled(n, null);

    // Calcular True Range para cada vela
    for (int i = 1; i < n; i++) {
      double tr1 = high[i] - low[i];
      double tr2 = (high[i] - close[i - 1]).abs();
      double tr3 = (low[i] - close[i - 1]).abs();
      trueRange[i] = [tr1, tr2, tr3].reduce((a, b) => a > b ? a : b);
    }

    // Suavizar con Wilder's MA
    double sumTR = 0.0;
    for (int i = 1; i <= period; i++) {
      sumTR += trueRange[i] ?? 0.0;
    }
    atr[period] = sumTR / period;

    // Continuar suavizado
    for (int i = period + 1; i < n; i++) {
      atr[i] =
          ((atr[i - 1] ?? 0) * (period - 1) + (trueRange[i] ?? 0)) / period;
    }

    return {'ATR': atr};
  }

  static double? getCurrentATR(
    List<double> high,
    List<double> low,
    List<double> close,
    int period, {
    int offset = 0,
  }) {
    var atrData = calculateATR(high, low, close, period);
    int index = atrData['ATR']!.length - 1 - offset;
    if (index < 0) return null;
    return atrData['ATR']![index];
  }

  // ============================================
  // 5. RSI - RELATIVE STRENGTH INDEX
  // ============================================

  static List<double?> calculateRSI(List<double> close, int period) {
    if (close.length < period + 1) {
      return List.filled(close.length, null);
    }

    int n = close.length;
    List<double?> rsi = List.filled(n, null);
    List<double> changes = [];

    // Calcular cambios
    for (int i = 1; i < n; i++) {
      changes.add(close[i] - close[i - 1]);
    }

    // Separar ganancias y pérdidas
    List<double> gains = changes.map((c) => c > 0 ? c : 0.0).toList();
    List<double> losses = changes.map((c) => c < 0 ? -c : 0.0).toList();

    // Primera media simple
    double avgGain = gains.sublist(0, period).reduce((a, b) => a + b) / period;
    double avgLoss = losses.sublist(0, period).reduce((a, b) => a + b) / period;

    if (avgLoss == 0) {
      rsi[period] = 100.0;
    } else {
      double rs = avgGain / avgLoss;
      rsi[period] = 100.0 - (100.0 / (1.0 + rs));
    }

    // Continuar con EMA
    for (int i = period + 1; i < n; i++) {
      avgGain = ((avgGain * (period - 1)) + gains[i - 1]) / period;
      avgLoss = ((avgLoss * (period - 1)) + losses[i - 1]) / period;

      if (avgLoss == 0) {
        rsi[i] = 100.0;
      } else {
        double rs = avgGain / avgLoss;
        rsi[i] = 100.0 - (100.0 / (1.0 + rs));
      }
    }

    return rsi;
  }

  // ============================================
  // 6. MACD - MOVING AVERAGE CONVERGENCE DIVERGENCE
  // ============================================

  static Map<String, List<double?>> calculateMACD(
    List<double> close, {
    int fastPeriod = 12,
    int slowPeriod = 26,
    int signalPeriod = 9,
  }) {
    List<double?> emaFast = calculateEMA(close, fastPeriod);
    List<double?> emaSlow = calculateEMA(close, slowPeriod);

    int n = close.length;
    List<double?> macdLine = List.filled(n, null);
    List<double?> signalLine = List.filled(n, null);
    List<double?> histogram = List.filled(n, null);

    // Calcular línea MACD
    for (int i = 0; i < n; i++) {
      if (emaFast[i] != null && emaSlow[i] != null) {
        macdLine[i] = emaFast[i]! - emaSlow[i]!;
      }
    }

    // Calcular línea de señal (EMA del MACD)
    List<double> validMacd = macdLine.whereType<double>().toList();
    if (validMacd.length >= signalPeriod) {
      List<double?> signal = calculateEMA(validMacd, signalPeriod);
      // Alinear con el índice original
      int offset = n - validMacd.length;
      for (int i = 0; i < signal.length; i++) {
        signalLine[i + offset] = signal[i];
      }
    }

    // Calcular histograma
    for (int i = 0; i < n; i++) {
      if (macdLine[i] != null && signalLine[i] != null) {
        histogram[i] = macdLine[i]! - signalLine[i]!;
      }
    }

    return {'MACD': macdLine, 'Signal': signalLine, 'Histogram': histogram};
  }

  // ============================================
  // UTILIDADES
  // ============================================

  static double _calculateStdDev(List<double> values, [double? mean]) {
    if (values.isEmpty) return 0.0;
    double m = mean ?? values.reduce((a, b) => a + b) / values.length;
    double sumSquaredDifferences = 0.0;
    for (double value in values) {
      sumSquaredDifferences += (value - m) * (value - m);
    }
    return sqrt(sumSquaredDifferences / values.length);
  }
}
