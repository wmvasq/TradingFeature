import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';

/// Gráfico de velas con las zonas, niveles y entrada/SL/TP de la estrategia.
class CandleChart extends StatelessWidget {
  final List<Candle> candles;

  /// Vela en formación (tiempo real), se dibuja a continuación de [candles].
  final Candle? live;
  final StrategyResult? result;
  final int visibleCandles;

  const CandleChart({
    super.key,
    required this.candles,
    this.live,
    this.result,
    this.visibleCandles = 100,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CandlePainter(
        candles: live == null ? candles : [...candles, live!],
        livePrice: live?.close,
        result: result,
        visibleCandles: visibleCandles,
        textColor: Theme.of(context).colorScheme.onSurface,
      ),
      size: Size.infinite,
    );
  }
}

class _CandlePainter extends CustomPainter {
  static const _bull = Color(0xFF26A69A);
  static const _bear = Color(0xFFEF5350);
  static const _axisWidth = 64.0;

  final List<Candle> candles;
  final double? livePrice;
  final StrategyResult? result;
  final int visibleCandles;
  final Color textColor;

  _CandlePainter({
    required this.candles,
    required this.livePrice,
    required this.result,
    required this.visibleCandles,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final start = max(0, candles.length - visibleCandles);
    final visible = candles.sublist(start);
    final chartWidth = size.width - _axisWidth;
    final step = chartWidth / visible.length;

    var hi = visible.map((c) => c.high).reduce(max);
    var lo = visible.map((c) => c.low).reduce(min);
    for (final p in [
      result?.entry,
      result?.stopLoss,
      result?.takeProfit,
      for (final line in result?.lines ?? const <IndicatorLine>[])
        ...line.values.skip(start),
    ]) {
      if (p != null) {
        hi = max(hi, p);
        lo = min(lo, p);
      }
    }
    final pad = (hi - lo) * 0.05;
    hi += pad;
    lo -= pad;

    double y(double price) => size.height * (hi - price) / (hi - lo);
    double x(int index) => (index - start) * step + step / 2;

    _drawPriceAxis(canvas, size, hi, lo, y);

    // Zonas (OB, FVG): desde su vela de origen hasta el borde derecho
    for (final z in result?.zones ?? const <PriceZone>[]) {
      final color = z.bias == Direction.long ? _bull : _bear;
      final left = max(0.0, x(z.startIndex) - step / 2);
      final rect = Rect.fromLTRB(left, y(z.top), chartWidth, y(z.bottom));
      canvas.drawRect(
        rect,
        Paint()..color = color.withValues(alpha: z.label == 'OB' ? 0.25 : 0.12),
      );
      _text(canvas, z.label, Offset(left + 2, rect.top), color, 10);
    }

    // Niveles de estructura (BOS / CHoCH)
    for (final l in result?.levels ?? const <PriceLevel>[]) {
      if (l.toIndex < start) continue;
      final color = l.bias == Direction.long ? _bull : _bear;
      final from = max(0.0, x(l.fromIndex));
      final to = x(l.toIndex);
      _dashedLine(
        canvas,
        Offset(from, y(l.price)),
        Offset(to, y(l.price)),
        color,
      );
      _text(
        canvas,
        l.label,
        Offset((from + to) / 2 - 12, y(l.price) - 13),
        color,
        10,
      );
    }

    // Velas
    final bodyWidth = max(1.0, step * 0.7);
    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final paint = Paint()..color = c.close >= c.open ? _bull : _bear;
      final cx = i * step + step / 2;
      canvas.drawLine(
        Offset(cx, y(c.high)),
        Offset(cx, y(c.low)),
        paint..strokeWidth = 1,
      );
      final top = y(max(c.open, c.close));
      final bottom = y(min(c.open, c.close));
      canvas.drawRect(
        Rect.fromLTRB(
          cx - bodyWidth / 2,
          top,
          cx + bodyWidth / 2,
          max(bottom, top + 1),
        ),
        paint,
      );
    }

    // Indicadores sobre el precio (EMAs...)
    for (final line in result?.lines ?? const <IndicatorLine>[]) {
      final paint = Paint()
        ..color = Color(line.color)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      for (var i = start; i < line.values.length; i++) {
        final v = line.values[i];
        if (v == null) continue;
        final point = Offset(x(i), y(v));
        started
            ? path.lineTo(point.dx, point.dy)
            : path.moveTo(point.dx, point.dy);
        started = true;
      }
      canvas.drawPath(path, paint);
    }
    _drawLegend(canvas, result?.lines ?? const []);

    // Entrada / SL / TP
    final r = result;
    if (r != null && r.status != SetupStatus.none) {
      _priceLine(canvas, size, y, r.entry, 'Entrada', Colors.blue);
      _priceLine(canvas, size, y, r.stopLoss, 'SL', _bear);
      _priceLine(canvas, size, y, r.takeProfit, 'TP', _bull);
    }

    // Precio actual en el eje, del color de la vela en curso
    final price = livePrice;
    if (price != null) {
      final color = candles.last.close >= candles.last.open ? _bull : _bear;
      final py = y(price);
      canvas.drawLine(
        Offset(0, py),
        Offset(chartWidth, py),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      final rect = Rect.fromLTWH(chartWidth, py - 8, _axisWidth, 16);
      canvas.drawRect(rect, Paint()..color = color);
      _text(
        canvas,
        _fmt(price),
        Offset(rect.left + 4, rect.top + 1),
        Colors.white,
        10,
      );
    }
  }

  void _drawPriceAxis(
    Canvas canvas,
    Size size,
    double hi,
    double lo,
    double Function(double) y,
  ) {
    final grid = Paint()
      ..color = textColor.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 0; i <= 5; i++) {
      final price = lo + (hi - lo) * i / 5;
      final py = y(price);
      canvas.drawLine(Offset(0, py), Offset(size.width - _axisWidth, py), grid);
      _text(
        canvas,
        _fmt(price),
        Offset(size.width - _axisWidth + 4, py - 7),
        textColor.withValues(alpha: 0.6),
        10,
      );
    }
  }

  void _priceLine(
    Canvas canvas,
    Size size,
    double Function(double) y,
    double? price,
    String label,
    Color color,
  ) {
    if (price == null) return;
    final py = y(price);
    _dashedLine(
      canvas,
      Offset(0, py),
      Offset(size.width - _axisWidth, py),
      color,
    );
    final rect = Rect.fromLTWH(size.width - _axisWidth, py - 8, _axisWidth, 16);
    canvas.drawRect(rect, Paint()..color = color);
    _text(
      canvas,
      _fmt(price),
      Offset(rect.left + 4, rect.top + 1),
      Colors.white,
      10,
    );
    _text(canvas, label, Offset(4, py - 14), color, 10);
  }

  void _drawLegend(Canvas canvas, List<IndicatorLine> lines) {
    var dx = 4.0;
    for (final line in lines) {
      final color = Color(line.color);
      canvas.drawRect(Rect.fromLTWH(dx, 6, 10, 3), Paint()..color = color);
      _text(canvas, line.label, Offset(dx + 13, 0), color, 10);
      dx += 13 + line.label.length * 6.5 + 10;
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    final length = (b - a).distance;
    if (length == 0) return;
    final dir = (b - a) / length;
    for (var d = 0.0; d < length; d += dash * 2) {
      canvas.drawLine(a + dir * d, a + dir * min(d + dash, length), paint);
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  static String _fmt(double v) => v.toStringAsFixed(v >= 100 ? 1 : 4);

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candles != candles ||
      old.livePrice != livePrice ||
      old.result != result ||
      old.textColor != textColor;
}
