import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Length-prefixed JSON → at-shield-service (127.0.0.1:47830).
///
/// ponytail: one TCP connection per call. Avoids StreamSink-closed races
/// from a long-lived socket while the engine warms WFP filters.
class ShieldRpc {
  static const _host = '127.0.0.1';
  static const _port = 47830;

  bool _online = false;
  bool get isConnected => _online;

  Future<bool> connect({Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final s = await Socket.connect(_host, _port, timeout: timeout);
      await s.close();
      _online = true;
      return true;
    } catch (_) {
      _online = false;
      return false;
    }
  }

  Future<void> close() async {
    _online = false;
  }

  Future<Map<String, dynamic>> call(Map<String, dynamic> cmd) async {
    Socket? sock;
    try {
      sock = await Socket.connect(
        _host,
        _port,
        timeout: const Duration(seconds: 2),
      );
      final body = utf8.encode(jsonEncode(cmd));
      final header = ByteData(4)..setUint32(0, body.length, Endian.little);
      sock.add(header.buffer.asUint8List());
      sock.add(body);
      await sock.flush();

      final respBytes = await _readFrame(sock).timeout(const Duration(seconds: 8));
      _online = true;
      return jsonDecode(utf8.decode(respBytes)) as Map<String, dynamic>;
    } catch (e) {
      _online = false;
      return {
        'ok': 'error',
        'data': {'message': 'serviço offline'},
      };
    } finally {
      try {
        await sock?.close();
      } catch (_) {}
    }
  }

  static Future<Uint8List> _readFrame(Socket socket) async {
    final buffer = <int>[];
    await for (final chunk in socket) {
      buffer.addAll(chunk);
      if (buffer.length < 4) continue;
      final len = ByteData.sublistView(Uint8List.fromList(buffer.sublist(0, 4)))
          .getUint32(0, Endian.little);
      if (len == 0 || len > 8 * 1024 * 1024) {
        throw StateError('bad frame length $len');
      }
      if (buffer.length >= 4 + len) {
        return Uint8List.fromList(buffer.sublist(4, 4 + len));
      }
    }
    throw StateError('connection closed before full frame');
  }
}
