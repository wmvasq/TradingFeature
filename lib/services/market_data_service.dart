import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trading_models.dart';

/// Servicio para obtener datos de mercado de Bitcoin desde múltiples exchanges
class MarketDataService {
  // ============================================
  // BINANCE PUBLIC API (Recomendado)
  // ============================================
  static const String _binanceBaseUrl = 'https://api.binance.com/api/v3';

  /// Obtiene datos OHLCV (velas) de BTC/USDT desde Binance
  ///
  /// [interval] - '1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h', '6h', '8h', '12h', '1d', '3d', '1w', '1M'
  /// [limit] - Número de velas a obtener (máx 1000 por request)
  ///
  /// Retorna lista de velas ordenadas cronológicamente (más antigua primero)
  Future<List<Candle>> fetchBinanceKlines({
    required String symbol, // Ej: 'BTCUSDT'
    required String interval,
    int limit = 500,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    try {
      // Construir URL con parámetros
      final uri = Uri.parse('$_binanceBaseUrl/klines').replace(
        queryParameters: {
          'symbol': symbol,
          'interval': interval,
          'limit': limit.toString(),
          if (startTime != null)
            'startTime': startTime.millisecondsSinceEpoch.toString(),
          if (endTime != null)
            'endTime': endTime.millisecondsSinceEpoch.toString(),
        },
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);

        // Convertir cada vela de Binance a objeto Candle
        List<Candle> candles = data.map((rawCandle) {
          return Candle.fromBinance(rawCandle as List<dynamic>, interval);
        }).toList();

        // Ordenar por timestamp (ascendente)
        candles.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        return candles;
      } else {
        throw Exception(
          'Binance API Error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Obtiene el precio actual de BTC/USDT
  Future<double> getCurrentBTCPrice() async {
    try {
      final response = await http.get(
        Uri.parse('$_binanceBaseUrl/ticker/price?symbol=BTCUSDT'),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        return double.parse(data['price']);
      } else {
        throw Exception('Failed to fetch current price');
      }
    } catch (e) {
      // Si falla Binance, intentar con CoinGecko como respaldo
      return _getCoinGeckoPrice();
    }
  }

  /// Obtiene precio desde CoinGecko (respaldo)
  Future<double> _getCoinGeckoPrice() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd',
        ),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        return (data['bitcoin']['usd'] as num).toDouble();
      } else {
        throw Exception('CoinGecko API Error');
      }
    } catch (e) {
      throw Exception('Failed to fetch price from all sources: $e');
    }
  }

  /// Obtiene datos de 24h para BTC
  Future<Map<String, dynamic>> getBTC24hStats() async {
    try {
      final response = await http.get(
        Uri.parse('$_binanceBaseUrl/ticker/24hr?symbol=BTCUSDT'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to fetch 24h stats');
      }
    } catch (e) {
      rethrow;
    }
  }

  // ============================================
  // COINGECKO API (respaldo y datos adicionales)
  // ============================================
  static const String _coingeckoBaseUrl = 'https://api.coingecko.com/api/v3';

  /// Obtiene datos históricos de BTC desde CoinGecko (máx 2000 días)
  Future<List<Candle>> fetchCoinGeckoOHLCV({
    required int days,
    String vsCurrency = 'usd',
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_coingeckoBaseUrl/coins/bitcoin/ohlc?vs_currency=$vsCurrency&days=$days',
        ),
      );

      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);

        // CoinGecko devuelve: [timestamp, open, high, low, close]
        List<Candle> candles = data.map((item) {
          List<dynamic> ohlc = item as List<dynamic>;
          return Candle(
            open: (ohlc[1] as num).toDouble(),
            high: (ohlc[2] as num).toDouble(),
            low: (ohlc[3] as num).toDouble(),
            close: (ohlc[4] as num).toDouble(),
            volume: 0, // CoinGecko no da volumen en este endpoint
            timestamp: DateTime.fromMillisecondsSinceEpoch(ohlc[0] as int),
            interval: '1d',
          );
        }).toList();

        return candles;
      } else {
        throw Exception('CoinGecko OHLCV Error ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // ============================================
  // UTILIDADES
  // ============================================

  /// Verifica si los datos están actualizados (última vela cerrada)
  bool isDataFresh(List<Candle> candles, String interval) {
    if (candles.isEmpty) return false;

    final lastCandle = candles.last;
    final now = DateTime.now();

    switch (interval) {
      case '1m':
        return now.difference(lastCandle.timestamp).inMinutes < 2;
      case '5m':
        return now.difference(lastCandle.timestamp).inMinutes < 6;
      case '15m':
        return now.difference(lastCandle.timestamp).inMinutes < 16;
      case '1h':
        return now.difference(lastCandle.timestamp).inHours < 2;
      case '4h':
        return now.difference(lastCandle.timestamp).inHours < 5;
      case '1d':
        return now.difference(lastCandle.timestamp).inDays < 2;
      default:
        return now.difference(lastCandle.timestamp).inHours < 1;
    }
  }

  /// Obtiene múltiples timeframes simultáneamente
  Future<Map<String, List<Candle>>> fetchMultipleTimeframes({
    required String symbol,
    required List<String> intervals,
    int limitPerInterval = 200,
  }) async {
    Map<String, List<Candle>> result = {};

    // Ejecutar todas las peticiones en paralelo
    await Future.wait(
      intervals.map((interval) async {
        try {
          List<Candle> candles = await fetchBinanceKlines(
            symbol: symbol,
            interval: interval,
            limit: limitPerInterval,
          );
          result[interval] = candles;
        } catch (e) {
          result[interval] = [];
        }
      }),
    );

    return result;
  }

  /// Obtiene datos con reintentos automáticos
  Future<List<Candle>> fetchWithRetry({
    required String symbol,
    required String interval,
    int maxRetries = 3,
    int limit = 500,
  }) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < maxRetries) {
      try {
        return await fetchBinanceKlines(
          symbol: symbol,
          interval: interval,
          limit: limit,
        );
      } catch (e) {
        lastError = e as Exception;
        attempts++;
        if (attempts < maxRetries) {
          // Esperar exponencialmente: 1s, 2s, 4s
          await Future.delayed(Duration(seconds: 1 << attempts));
        }
      }
    }

    throw Exception('Failed after $maxRetries retries: $lastError');
  }

  /// Obtiene el volumen total de trading de BTC en las últimas 24h
  Future<double> getBTC24hVolume() async {
    try {
      final stats = await getBTC24hStats();
      return (stats['volume'] as num).toDouble();
    } catch (e) {
      return 0.0;
    }
  }
}
