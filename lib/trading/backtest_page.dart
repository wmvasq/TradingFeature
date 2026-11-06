import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'backtest.dart';
import 'market_data.dart';
import 'models.dart';
import 'setups.dart';
import 'strategies/strategy.dart';

/// Corre el backtest en un isolate para no congelar la pantalla (en web no
/// hay isolates). Es una función de nivel superior a propósito: así el closure
/// que se envía al isolate solo captura estos parámetros y no el `State`.
Future<BacktestReport> _runInBackground({
  required Strategy strategy,
  required List<Candle> candles,
  required String symbol,
  required String assetLabel,
  required String interval,
  required BacktestSettings settings,
}) {
  BacktestReport run() => runBacktest(
    strategy: strategy,
    candles: candles,
    symbol: symbol,
    assetLabel: assetLabel,
    interval: interval,
    settings: settings,
  );
  return kIsWeb ? Future.value(run()) : Isolate.run(run);
}

/// Backtest bajo demanda del activo elegido: período, estrategia y comisión.
class BacktestPage extends StatefulWidget {
  final Asset asset;
  final String interval;
  final Strategy strategy;

  const BacktestPage({
    super.key,
    required this.asset,
    required this.interval,
    required this.strategy,
  });

  @override
  State<BacktestPage> createState() => _BacktestPageState();
}

class _BacktestPageState extends State<BacktestPage> {
  static const _intervals = ['5m', '15m', '1h', '4h', '1d'];
  static const _candleCounts = [1000, 3000, 5000, 10000, 20000];
  static const _fees = [
    (0.0, 'Sin comisión'),
    (0.0002, '0,02 % (maker)'),
    (0.0005, '0,05 % (taker futuros)'),
    (0.001, '0,1 % (spot)'),
  ];

  late String _interval = widget.interval;
  late Strategy _strategy = widget.strategy;
  int _count = 5000;
  double _fee = 0.0005;
  bool _includeWaiting = false;

  // Velas ya bajadas por temporalidad/cantidad: cambiar de estrategia o de
  // comisión no vuelve a descargar.
  final Map<String, List<Candle>> _history = {};
  BacktestReport? _report;
  String? _status;
  String? _error;
  bool _running = false;

  BacktestSettings get _settings =>
      BacktestSettings(feeRate: _fee, includeWaiting: _includeWaiting);

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final window = _settings.window;
      final key = '$_interval|$_count';
      var candles = _history[key];
      if (candles == null) {
        candles = await widget.asset.fetchHistory(
          interval: _interval,
          count: _count + window,
          onProgress: (n) {
            if (mounted) setState(() => _status = 'Descargando velas… $n');
          },
        );
        _history[key] = candles;
      }

      setState(() => _status = 'Evaluando ${candles!.length - window} velas…');
      final report = await _runInBackground(
        strategy: _strategy,
        candles: candles,
        symbol: widget.asset.symbol,
        assetLabel: widget.asset.label,
        interval: _interval,
        settings: _settings,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _running = false;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _running = false;
        _status = null;
      });
    }
  }

  String _durationLabel(int count) {
    final total = intervalDurations[_interval]! * count;
    if (total.inDays >= 2) return '~${total.inDays} días';
    return '~${total.inHours} h';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Backtest · ${widget.asset.label}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildControls(),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.play_arrow),
            label: Text(_running ? 'Ejecutando…' : 'Ejecutar backtest'),
          ),
          if (_running) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            if (_status != null) ...[
              const SizedBox(height: 4),
              Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_report != null && !_running) ...[
            const SizedBox(height: 16),
            _ReportView(report: _report!),
          ],
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final s in strategies)
              ChoiceChip(
                label: Text(s.name),
                selected: s == _strategy,
                onSelected: (_) => setState(() => _strategy = s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                initialValue: _interval,
                decoration: const InputDecoration(
                  labelText: 'Temporalidad',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final i in _intervals)
                    DropdownMenuItem(value: i, child: Text(i)),
                ],
                onChanged: (v) => setState(() => _interval = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _count,
                decoration: const InputDecoration(
                  labelText: 'Período',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final c in _candleCounts)
                    DropdownMenuItem(
                      value: c,
                      child: Text('$c velas (${_durationLabel(c)})'),
                    ),
                ],
                onChanged: (v) => setState(() => _count = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<double>(
          initialValue: _fee,
          decoration: const InputDecoration(
            labelText: 'Comisión por lado',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final (value, label) in _fees)
              DropdownMenuItem(value: value, child: Text(label)),
          ],
          onChanged: (v) => setState(() => _fee = v!),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Operar setups en espera'),
          subtitle: const Text(
            'Como orden límite en la zona (p. ej. el OB de SMC)',
          ),
          value: _includeWaiting,
          onChanged: (v) => setState(() => _includeWaiting = v),
        ),
      ],
    );
  }
}

class _ReportView extends StatelessWidget {
  final BacktestReport report;

  const _ReportView({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final fee = r.settings.feeRate;
    final avgFeeR = r.closed.isEmpty
        ? 0.0
        : r.closed.map((t) => t.feeR(fee)).reduce((a, b) => a + b) /
              r.closed.length;
    final netColor = r.netR >= 0 ? Colors.green : Colors.red;
    final winRate = r.winRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${r.strategy} · ${r.assetLabel} ${r.interval} · '
          '${_date(r.from)} → ${_date(r.to)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _stat('Resultado neto', _r(r.netR), color: netColor, big: true),
                _stat('Bruto (sin comisión)', _r(r.grossR)),
                _stat('Trades', '${r.closed.length}'),
                _stat(
                  'Win rate',
                  winRate == null
                      ? '—'
                      : '${(winRate * 100).toStringAsFixed(0)}%',
                ),
                _stat(
                  'Promedio por trade',
                  r.averageNetR == null ? '—' : _r(r.averageNetR!),
                ),
                _stat(
                  'Profit factor',
                  r.profitFactor?.toStringAsFixed(2) ?? '—',
                ),
                _stat(
                  'Máx. drawdown',
                  '-${r.maxDrawdownR.toStringAsFixed(1)} R',
                ),
                _stat('Peor racha', '${r.maxLosingStreak} pérdidas'),
                _stat(
                  'Comisión media',
                  '${avgFeeR.toStringAsFixed(2)} R/trade',
                ),
                if (r.expired > 0) _stat('Expirados', '${r.expired}'),
              ],
            ),
          ),
        ),
        if (avgFeeR >= 0.3)
          Card(
            color: Colors.orange.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '⚠️ La comisión cuesta ${avgFeeR.toStringAsFixed(2)} R por '
                'trade: el stop es muy corto respecto al precio en esta '
                'temporalidad. Prueba una temporalidad mayor o comisión maker.',
              ),
            ),
          ),
        if (r.closed.length < 30)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Menos de 30 trades: muestra chica, el resultado puede ser suerte.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        if (r.equity.length >= 2) ...[
          const SizedBox(height: 12),
          Text(
            'Curva de resultado (R neto acumulado)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _EquityPainter(
                r.equity,
                lineColor: netColor,
                axisColor: Theme.of(context).colorScheme.onSurface,
              ),
              size: Size.infinite,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Trades (más recientes primero)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final t in r.trades.reversed.take(200)) _TradeTile(t, fee),
      ],
    );
  }

  static String _r(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} R';

  static String _date(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';

  Widget _stat(String label, String value, {Color? color, bool big = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: big ? 24 : 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      );
}

class _TradeTile extends StatelessWidget {
  final BacktestTrade trade;
  final double feeRate;

  const _TradeTile(this.trade, this.feeRate);

  @override
  Widget build(BuildContext context) {
    final s = trade.setup;
    final net = trade.netR(feeRate);
    final (label, color) = switch (s.state) {
      SetupState.won || SetupState.lost => (
        '${net! >= 0 ? '+' : ''}${net.toStringAsFixed(2)} R',
        net >= 0 ? Colors.green : Colors.red,
      ),
      SetupState.expired => ('Expirado', Colors.grey),
      _ => ('Abierto', Colors.blue),
    };
    String two(int v) => v.toString().padLeft(2, '0');
    final t = s.signalTime;
    final p = s.entry >= 100 ? 2 : 4;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        s.direction == Direction.long ? Icons.north_east : Icons.south_east,
        color: s.direction == Direction.long ? Colors.green : Colors.red,
      ),
      title: Text(
        '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)} · '
        'E ${s.entry.toStringAsFixed(p)}',
      ),
      subtitle: Text(
        'SL ${s.stopLoss.toStringAsFixed(p)} · TP ${s.takeProfit.toStringAsFixed(p)}',
      ),
      trailing: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EquityPainter extends CustomPainter {
  final List<double> equity;
  final Color lineColor;
  final Color axisColor;

  _EquityPainter(
    this.equity, {
    required this.lineColor,
    required this.axisColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final values = [0.0, ...equity];
    final hi = values.reduce(max);
    final lo = values.reduce(min);
    final range = max(hi - lo, 1e-9);
    double y(double v) => size.height * (hi - v) / range;
    double x(int i) => size.width * i / (values.length - 1);

    // Línea de cero
    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()
        ..color = axisColor.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '${hi.toStringAsFixed(1)} R / ${lo.toStringAsFixed(1)} R',
        style: TextStyle(color: axisColor.withValues(alpha: 0.6), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(4, 0));
  }

  @override
  bool shouldRepaint(_EquityPainter old) =>
      old.equity != equity || old.lineColor != lineColor;
}
