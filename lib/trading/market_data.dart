import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'models.dart';

/// Fuente de velas. Todas las implementaciones usan APIs públicas sin API key
/// que permiten CORS, así que funcionan también en web.
abstract class MarketDataSource {
  /// Devuelve velas cerradas, de la más antigua a la más reciente.
  /// La vela en curso se descarta para que la señal no cambie mientras se forma.
  /// Con [startTime] devuelve hasta [limit] velas a partir de esa hora en vez
  /// de las más recientes.
  Future<List<Candle>> fetchCandles({
    required String symbol,
    required String interval,
    int limit = 500,
    DateTime? startTime,
  });

  /// Vela en curso en tiempo real por WebSocket. Emite cada actualización y,
  /// cuando la vela cierra, una última con `closed: true`.
  /// Si la conexión se cae, reconecta sola mientras haya alguien escuchando.
  Stream<LiveCandle> watchCandle({
    required String symbol,
    required String interval,
  });
}

class LiveCandle {
  final Candle candle;
  final bool closed;

  const LiveCandle(this.candle, {required this.closed});
}

const Map<String, Duration> intervalDurations = {
  '5m': Duration(minutes: 5),
  '15m': Duration(minutes: 15),
  '1h': Duration(hours: 1),
  '4h': Duration(hours: 4),
  '1d': Duration(days: 1),
};

class Asset {
  final String label;
  final String symbol;
  final MarketDataSource source;

  const Asset(this.label, this.symbol, this.source);
}

final _binanceSpot = BinanceSource(
  'https://api.binance.com/api/v3',
  'wss://stream.binance.com:9443/ws',
);
final _binanceFutures = BinanceSource(
  'https://fapi.binance.com/fapi/v1',
  // Los streams de mercado de futuros viven en /market/ws (en /ws no llegan)
  'wss://fstream.binance.com/market/ws',
);
final _hyperliquid = HyperliquidSource();

final List<Asset> assets = [
  Asset('BTC', 'BTCUSDT', _binanceSpot),
  Asset('ETH', 'ETHUSDT', _binanceSpot),
  Asset('SOL', 'SOLUSDT', _binanceSpot),
  Asset('BNB', 'BNBUSDT', _binanceSpot),
  Asset('XRP', 'XRPUSDT', _binanceSpot),
  Asset('ADA', 'ADAUSDT', _binanceSpot),
  Asset('DOGE', 'DOGEUSDT', _binanceSpot),
  Asset('Oro (XAU)', 'XAUUSDT', _binanceFutures),
  Asset('Nasdaq 100', 'xyz:XYZ100', _hyperliquid),
  Asset('S&P 500', 'xyz:SP500', _hyperliquid),
];

/// Binance spot o futuros USDⓈ-M (mismo formato de klines).
class BinanceSource implements MarketDataSource {
  static const int maxLimit = 1000;

  final String baseUrl;
  final String wsUrl;
  final http.Client _http;

  BinanceSource(this.baseUrl, this.wsUrl, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  @override
  Future<List<Candle>> fetchCandles({
    required String symbol,
    required String interval,
    int limit = 500,
    DateTime? startTime,
  }) async {
    final uri = Uri.parse('$baseUrl/klines').replace(
      queryParameters: {
        'symbol': symbol,
        'interval': interval,
        // +1 para compensar la vela abierta que se descarta
        'limit': '${(limit + 1).clamp(1, maxLimit)}',
        if (startTime != null)
          'startTime': '${startTime.millisecondsSinceEpoch}',
      },
    );

    final response = await _http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Binance ${response.statusCode}: ${response.body}');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final data = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final k in data.cast<List<dynamic>>())
        if ((k[6] as num) < now)
          Candle(
            openTime: DateTime.fromMillisecondsSinceEpoch(
              (k[0] as num).toInt(),
            ),
            open: double.parse(k[1] as String),
            high: double.parse(k[2] as String),
            low: double.parse(k[3] as String),
            close: double.parse(k[4] as String),
            volume: double.parse(k[5] as String),
          ),
    ];
  }

  @override
  Stream<LiveCandle> watchCandle({
    required String symbol,
    required String interval,
  }) {
    return _reconnectingSocket(
      Uri.parse('$wsUrl/${symbol.toLowerCase()}@kline_$interval'),
      parse: (json) {
        final k = json['k'] as Map<String, dynamic>?;
        if (k == null) return const [];
        return [
          LiveCandle(
            Candle(
              openTime: DateTime.fromMillisecondsSinceEpoch(
                (k['t'] as num).toInt(),
              ),
              open: double.parse(k['o'] as String),
              high: double.parse(k['h'] as String),
              low: double.parse(k['l'] as String),
              close: double.parse(k['c'] as String),
              volume: double.parse(k['v'] as String),
            ),
            closed: k['x'] as bool,
          ),
        ];
      },
    );
  }
}

/// Hyperliquid: perpetuos de índices (Nasdaq, S&P 500...) en el dex "xyz".
class HyperliquidSource implements MarketDataSource {
  static const _url = 'https://api.hyperliquid.xyz/info';
  static const _wsUrl = 'wss://api.hyperliquid.xyz/ws';

  final http.Client _http;

  HyperliquidSource({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  @override
  Future<List<Candle>> fetchCandles({
    required String symbol,
    required String interval,
    int limit = 500,
    DateTime? startTime,
  }) async {
    final step = intervalDurations[interval];
    if (step == null) {
      throw ArgumentError('Temporalidad no soportada: $interval');
    }

    final now = DateTime.now();
    final response = await _http.post(
      Uri.parse(_url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': 'candleSnapshot',
        'req': {
          'coin': symbol,
          'interval': interval,
          'startTime': (startTime ?? now.subtract(step * (limit + 1)))
              .millisecondsSinceEpoch,
        },
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Hyperliquid ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    final candles = [
      for (final k in data.cast<Map<String, dynamic>>())
        if ((k['T'] as num) < now.millisecondsSinceEpoch) _parseCandle(k),
    ];
    if (candles.length <= limit) return candles;
    return startTime != null
        ? candles.sublist(0, limit)
        : candles.sublist(candles.length - limit);
  }

  @override
  Stream<LiveCandle> watchCandle({
    required String symbol,
    required String interval,
  }) {
    // Hyperliquid no marca el cierre: una vela se da por cerrada cuando
    // llega la primera actualización de la siguiente.
    Candle? current;
    return _reconnectingSocket(
      Uri.parse(_wsUrl),
      subscribe: {
        'method': 'subscribe',
        'subscription': {
          'type': 'candle',
          'coin': symbol,
          'interval': interval,
        },
      },
      // El servidor cierra conexiones sin mensajes durante 60 s
      keepAlive: {'method': 'ping'},
      parse: (json) {
        if (json['channel'] != 'candle') return const [];
        final data = json['data'];
        final updates = <LiveCandle>[];
        for (final k in data is List ? data : [data]) {
          final candle = _parseCandle(k as Map<String, dynamic>);
          final previous = current;
          if (previous != null && candle.openTime.isAfter(previous.openTime)) {
            updates.add(LiveCandle(previous, closed: true));
          }
          current = candle;
          updates.add(LiveCandle(candle, closed: false));
        }
        return updates;
      },
    );
  }

  static Candle _parseCandle(Map<String, dynamic> k) => Candle(
    openTime: DateTime.fromMillisecondsSinceEpoch((k['t'] as num).toInt()),
    open: double.parse(k['o'] as String),
    high: double.parse(k['h'] as String),
    low: double.parse(k['l'] as String),
    close: double.parse(k['c'] as String),
    volume: double.parse(k['v'] as String),
  );
}

/// Conexión WebSocket que se reabre sola a los 3 s si se cae o falla.
/// Se cierra definitivamente cuando se cancela la suscripción al stream.
Stream<T> _reconnectingSocket<T>(
  Uri uri, {
  required Iterable<T> Function(Map<String, dynamic> json) parse,
  Map<String, dynamic>? subscribe,
  Map<String, dynamic>? keepAlive,
}) {
  late final StreamController<T> controller;
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  Timer? keepAliveTimer;
  Timer? retryTimer;
  var cancelled = false;

  void connect() {
    if (cancelled) return;
    final ws = WebSocketChannel.connect(uri);
    channel = ws;

    ws.ready.then((_) {
      if (subscribe != null) ws.sink.add(jsonEncode(subscribe));
      if (keepAlive != null) {
        keepAliveTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => ws.sink.add(jsonEncode(keepAlive)),
        );
      }
    }, onError: (_) {}); // el fallo también llega como cierre del stream

    subscription = ws.stream.listen(
      (message) {
        try {
          final json = jsonDecode(message as String);
          if (json is Map<String, dynamic>) parse(json).forEach(controller.add);
        } catch (_) {
          // Mensaje inesperado: se ignora
        }
      },
      onError: (_) {},
      onDone: () {
        keepAliveTimer?.cancel();
        if (!cancelled) retryTimer = Timer(const Duration(seconds: 3), connect);
      },
    );
  }

  controller = StreamController<T>(
    onListen: connect,
    onCancel: () {
      cancelled = true;
      keepAliveTimer?.cancel();
      retryTimer?.cancel();
      subscription?.cancel();
      channel?.sink.close();
    },
  );
  return controller.stream;
}
