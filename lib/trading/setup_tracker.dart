import 'market_data.dart';
import 'setup_repository.dart';
import 'setups.dart';

/// Actualiza los setups activos (en espera o abiertos) con las velas cerradas
/// desde la última revisión y guarda los cambios.
class SetupTracker {
  /// Páginas de velas por grupo en cada actualización (1000 velas cada una).
  static const _maxPages = 10;

  final SetupRepository repository;

  SetupTracker(this.repository);

  Future<List<SavedSetup>> refresh() async {
    final setups = await repository.all();
    final groups = <String, List<SavedSetup>>{};
    for (final s in setups.where((s) => !s.state.isFinal)) {
      groups.putIfAbsent('${s.symbol}|${s.interval}', () => []).add(s);
    }

    for (final group in groups.values) {
      final first = group.first;
      final asset = assets.where((a) => a.symbol == first.symbol).firstOrNull;
      if (asset == null) continue;
      try {
        await _trackGroup(asset, first.interval, group);
      } catch (_) {
        // Sin conexión o error de la API: se reintenta en la próxima actualización
      }
    }
    return repository.all();
  }

  Future<void> _trackGroup(
    Asset asset,
    String interval,
    List<SavedSetup> group,
  ) async {
    var active = group;
    var from = active
        .map((s) => s.checkedUntil)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    for (var page = 0; page < _maxPages && active.isNotEmpty; page++) {
      final candles = await asset.source.fetchCandles(
        symbol: asset.symbol,
        interval: interval,
        limit: 1000,
        startTime: from.add(const Duration(milliseconds: 1)),
      );
      if (candles.isEmpty) break;

      final stillActive = <SavedSetup>[];
      for (final s in active) {
        final updated = trackSetup(s, candles);
        if (updated.checkedUntil != s.checkedUntil) {
          await repository.update(updated);
        }
        if (!updated.state.isFinal) stillActive.add(updated);
      }
      active = stillActive;
      from = candles.last.openTime;
      // Página incompleta: ya llegamos a la vela más reciente
      if (candles.length < 900) break;
    }
  }
}
