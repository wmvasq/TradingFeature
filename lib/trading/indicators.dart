import 'dart:math';
import 'models.dart';

/// Indicadores técnicos. Todas las series devuelven una lista alineada con la
/// entrada; los índices sin datos suficientes quedan en null.

List<double?> ema(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (values.length < period) return out;

  // Semilla: media simple de las primeras [period] velas
  var prev = values.take(period).reduce((a, b) => a + b) / period;
  out[period - 1] = prev;
  final k = 2 / (period + 1);
  for (var i = period; i < values.length; i++) {
    prev = (values[i] - prev) * k + prev;
    out[i] = prev;
  }
  return out;
}

/// ADX de Welles Wilder (equivalente a ta.dmi de TradingView).
List<double?> adx(List<Candle> c, int period) {
  final n = c.length;
  final out = List<double?>.filled(n, null);
  if (n < 2 * period + 1) return out;

  final tr = List<double>.filled(n, 0);
  final plusDm = List<double>.filled(n, 0);
  final minusDm = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final up = c[i].high - c[i - 1].high;
    final down = c[i - 1].low - c[i].low;
    plusDm[i] = up > down && up > 0 ? up : 0;
    minusDm[i] = down > up && down > 0 ? down : 0;
    tr[i] = _trueRange(c, i);
  }

  // Suavizado de Wilder (RMA) sembrado con la media de las primeras velas
  double rmaSeed(List<double> v) =>
      v.sublist(1, period + 1).reduce((a, b) => a + b) / period;
  var sTr = rmaSeed(tr);
  var sPlus = rmaSeed(plusDm);
  var sMinus = rmaSeed(minusDm);

  final dx = List<double?>.filled(n, null);
  for (var i = period; i < n; i++) {
    if (i > period) {
      sTr = (sTr * (period - 1) + tr[i]) / period;
      sPlus = (sPlus * (period - 1) + plusDm[i]) / period;
      sMinus = (sMinus * (period - 1) + minusDm[i]) / period;
    }
    final plusDi = sTr == 0 ? 0.0 : 100 * sPlus / sTr;
    final minusDi = sTr == 0 ? 0.0 : 100 * sMinus / sTr;
    final sum = plusDi + minusDi;
    dx[i] = sum == 0 ? 0 : 100 * (plusDi - minusDi).abs() / sum;
  }

  var value =
      dx.sublist(period, 2 * period).map((v) => v!).reduce((a, b) => a + b) /
      period;
  out[2 * period - 1] = value;
  for (var i = 2 * period; i < n; i++) {
    value = (value * (period - 1) + dx[i]!) / period;
    out[i] = value;
  }
  return out;
}

/// Squeeze Momentum de LazyBear: regresión lineal de
/// close - media(media(máximo, mínimo), sma(close)) sobre [length] velas.
/// Positivo = momentum alcista, negativo = bajista.
List<double?> squeezeMomentum(List<Candle> c, {int length = 20}) {
  final n = c.length;
  final out = List<double?>.filled(n, null);
  if (n < 2 * length - 1) return out;

  final delta = List<double?>.filled(n, null);
  for (var j = length - 1; j < n; j++) {
    final window = c.sublist(j - length + 1, j + 1);
    final highest = window.map((k) => k.high).reduce(max);
    final lowest = window.map((k) => k.low).reduce(min);
    final sma = window.map((k) => k.close).reduce((a, b) => a + b) / length;
    delta[j] = c[j].close - ((highest + lowest) / 2 + sma) / 2;
  }

  // linreg(delta, length, 0): valor de la recta ajustada en la última vela
  final meanX = (length - 1) / 2;
  var sxx = 0.0;
  for (var t = 0; t < length; t++) {
    sxx += (t - meanX) * (t - meanX);
  }
  for (var i = 2 * length - 2; i < n; i++) {
    var meanY = 0.0;
    for (var t = 0; t < length; t++) {
      meanY += delta[i - length + 1 + t]!;
    }
    meanY /= length;
    var sxy = 0.0;
    for (var t = 0; t < length; t++) {
      sxy += (t - meanX) * (delta[i - length + 1 + t]! - meanY);
    }
    final slope = sxy / sxx;
    out[i] = meanY + slope * (length - 1 - meanX);
  }
  return out;
}

/// ATR simple de las últimas [period] velas.
double atr(List<Candle> c, int period) {
  final n = min(period, c.length - 1);
  var sum = 0.0;
  for (var i = c.length - n; i < c.length; i++) {
    sum += _trueRange(c, i);
  }
  return sum / n;
}

double _trueRange(List<Candle> c, int i) => [
  c[i].high - c[i].low,
  (c[i].high - c[i - 1].close).abs(),
  (c[i].low - c[i - 1].close).abs(),
].reduce(max);
