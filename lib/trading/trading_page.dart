import 'dart:async';
import 'package:flutter/material.dart';
import 'candle_chart.dart';
import 'market_data.dart';
import 'models.dart';
import 'setup_repository.dart';
import 'setups.dart';
import 'setups_page.dart';
import 'strategies/strategy.dart';

/// Pantalla única: activo + temporalidad + estrategia → ¿hay entrada?
class TradingPage extends StatefulWidget {
  const TradingPage({super.key});

  @override
  State<TradingPage> createState() => _TradingPageState();
}

class _TradingPageState extends State<TradingPage> {
  static const _intervals = ['5m', '15m', '1h', '4h', '1d'];

  Asset _asset = assets.first;
  String _interval = '1h';
  Strategy _strategy = strategies.first;

  List<Candle> _candles = [];
  StrategyResult? _result;
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  // Tiempo real: la vela en formación se dibuja, pero la estrategia solo se
  // re-evalúa cuando cierra (así la señal no aparece y desaparece).
  StreamSubscription<LiveCandle>? _liveSubscription;
  Candle? _live;
  DateTime? _reloadedForGap;

  final SetupRepository _setups = SqfliteSetupRepository();
  // Keys de setups ya guardados en esta sesión (para el estado del botón)
  final Set<String> _savedKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_requestId;
    _liveSubscription?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _live = null;
    });
    try {
      final candles = await _asset.source.fetchCandles(
        symbol: _asset.symbol,
        interval: _interval,
      );
      // Si el usuario cambió de activo mientras cargaba, ignorar esta respuesta
      if (!mounted || request != _requestId) return;
      setState(() {
        _candles = candles;
        _result = _strategy.evaluate(candles);
        _loading = false;
      });
      _autoSaveEntry();
      _liveSubscription = _asset.source
          .watchCandle(symbol: _asset.symbol, interval: _interval)
          .listen(_onLiveCandle);
    } catch (e) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _onLiveCandle(LiveCandle update) {
    final candle = update.candle;
    final lastClosed = _candles.last.openTime;
    if (!candle.openTime.isAfter(lastClosed)) return;

    // Si falta alguna vela cerrada (p. ej. tras una reconexión), recargar
    // el historial una vez en lugar de seguir con un hueco.
    final expected = lastClosed.add(intervalDurations[_interval]!);
    if (candle.openTime != expected && _reloadedForGap != candle.openTime) {
      _reloadedForGap = candle.openTime;
      _load();
      return;
    }

    setState(() {
      if (update.closed) {
        _candles = [..._candles.skip(1), candle];
        _result = _strategy.evaluate(_candles);
        _live = null;
      } else {
        _live = candle;
      }
    });
    if (update.closed) _autoSaveEntry();
  }

  /// El setup actual listo para guardar (null si no tiene niveles).
  SavedSetup? _currentSetup(SetupOrigin origin) {
    final result = _result;
    if (result == null || _candles.isEmpty) return null;
    return SavedSetup.fromResult(
      result: result,
      symbol: _asset.symbol,
      assetLabel: _asset.label,
      interval: _interval,
      strategy: _strategy.name,
      signalTime: _candles.last.openTime,
      origin: origin,
    );
  }

  /// Las entradas se guardan solas; los setups en espera, con el botón.
  Future<void> _autoSaveEntry() async {
    if (_result?.status != SetupStatus.entry) return;
    final setup = _currentSetup(SetupOrigin.auto);
    if (setup == null || _savedKeys.contains(setup.key)) return;
    final inserted = await _setups.save(setup);
    if (!mounted) return;
    setState(() => _savedKeys.add(setup.key));
    if (inserted) {
      _showMessage(
        '${setup.isLong ? 'LONG' : 'SHORT'} ${setup.assetLabel} '
        '${setup.interval} guardado en Setups',
      );
    }
  }

  Future<void> _saveManually() async {
    final setup = _currentSetup(SetupOrigin.manual);
    if (setup == null) return;
    final inserted = await _setups.save(setup);
    if (!mounted) return;
    setState(() => _savedKeys.add(setup.key));
    _showMessage(inserted ? 'Setup guardado' : 'Ese setup ya estaba guardado');
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: SnackBarAction(label: 'Ver', onPressed: _openSetups),
      ),
    );
  }

  void _openSetups() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SetupsPage(repository: _setups)),
    );
  }

  void _selectStrategy(Strategy strategy) {
    setState(() {
      _strategy = strategy;
      // Las velas ya están cargadas: solo se re-evalúa
      if (_candles.isNotEmpty) _result = strategy.evaluate(_candles);
    });
    _autoSaveEntry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trading'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Setups guardados',
            onPressed: _openSetups,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSelectors(),
            const SizedBox(height: 12),
            if (_error != null)
              _ErrorBox(message: _error!, onRetry: _load)
            else if (_result == null)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _StatusCard(
                result: _result!,
                loading: _loading,
                saved: _savedKeys.contains(
                  _currentSetup(SetupOrigin.manual)?.key,
                ),
                onSave: _currentSetup(SetupOrigin.manual) == null
                    ? null
                    : _saveManually,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 340,
                child: CandleChart(
                  candles: _candles,
                  live: _live,
                  result: _result,
                ),
              ),
              const SizedBox(height: 4),
              _buildLiveInfo(),
              const SizedBox(height: 12),
              _ConditionsList(conditions: _result!.conditions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectors() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<Asset>(
                initialValue: _asset,
                decoration: const InputDecoration(
                  labelText: 'Activo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final a in assets)
                    DropdownMenuItem(value: a, child: Text(a.label)),
                ],
                onChanged: (v) {
                  if (v == null || v == _asset) return;
                  _asset = v;
                  _load();
                },
              ),
            ),
            const SizedBox(width: 12),
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
                onChanged: (v) {
                  if (v == null || v == _interval) return;
                  _interval = v;
                  _load();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final s in strategies)
              ChoiceChip(
                label: Text(s.name),
                tooltip: s.description,
                selected: s == _strategy,
                onSelected: (_) => _selectStrategy(s),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveInfo() {
    final small = Theme.of(context).textTheme.bodySmall;
    final live = _live;
    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: live != null ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 6),
        Text(
          live != null
              ? 'En vivo · ${live.close.toStringAsFixed(live.close >= 100 ? 2 : 4)}'
              : 'Conectando…',
          style: small,
        ),
        const Spacer(),
        Text(
          'Señal: vela cerrada ${_formatTime(_candles.last.openTime)}',
          style: small,
        ),
      ],
    );
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _StatusCard extends StatelessWidget {
  final StrategyResult result;
  final bool loading;
  final bool saved;

  /// null si el resultado no tiene niveles que guardar.
  final VoidCallback? onSave;

  const _StatusCard({
    required this.result,
    required this.loading,
    required this.saved,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (result.status) {
      SetupStatus.entry => (
        result.direction == Direction.short ? Colors.red : Colors.green,
        Icons.check_circle,
      ),
      SetupStatus.waiting => (Colors.orange, Icons.hourglass_top),
      SetupStatus.none => (Colors.grey, Icons.block),
    };
    final rr = result.riskReward;

    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    switch (result.status) {
                      SetupStatus.entry => result.summary,
                      SetupStatus.waiting => 'Sin entrada todavía',
                      SetupStatus.none => 'Sin entrada',
                    },
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (result.status != SetupStatus.entry) ...[
              const SizedBox(height: 4),
              Text(result.summary),
            ],
            if (result.status != SetupStatus.none && result.entry != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _level('Entrada', result.entry!),
                  _level('SL', result.stopLoss!),
                  _level('TP', result.takeProfit!),
                  if (rr != null) Text('R:R ${rr.toStringAsFixed(2)}'),
                ],
              ),
            ],
            if (onSave != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: saved
                    ? const Chip(
                        avatar: Icon(Icons.bookmark, size: 18),
                        label: Text('Guardado'),
                      )
                    : OutlinedButton.icon(
                        onPressed: onSave,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Guardar setup'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _level(String label, double value) =>
      Text('$label ${value.toStringAsFixed(value >= 100 ? 2 : 4)}');
}

class _ConditionsList extends StatelessWidget {
  final List<Condition> conditions;

  const _ConditionsList({required this.conditions});

  @override
  Widget build(BuildContext context) {
    if (conditions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in conditions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  c.met ? Icons.check : Icons.close,
                  size: 18,
                  color: c.met
                      ? Colors.green
                      : (c.required ? Colors.red : Colors.grey),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.required ? c.label : '${c.label} (opcional)',
                    style: c.required
                        ? null
                        : const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('No se pudieron cargar las velas:\n$message'),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
