// lib/ble_helper.dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// UUIDs (deben coincidir con tu sketch del ESP32)
const String _svcUuid    = '12345678-1234-1234-1234-1234567890ab';
const String _statusUuid = '12345678-1234-1234-1234-1234567890ac'; // NOTIFY
const String _ctrlUuid   = '12345678-1234-1234-1234-1234567890ae'; // READ/WRITE

class BleHelper {
  BluetoothDevice? _dev;
  BluetoothCharacteristic? _chStatus;
  BluetoothCharacteristic? _chCtrl;

  final _statusStreamCtrl = StreamController<String>.broadcast();
  final _connStreamCtrl   = StreamController<bool>.broadcast();

  bool _connected = false;

  /// Streams públicos
  Stream<String> get statusStream => _statusStreamCtrl.stream; // ej: "OBS|27.3"
  Stream<bool>   get connectionStream => _connStreamCtrl.stream;
  bool get isConnected => _connected;

  /// Conecta escaneando el dispositivo.
  /// Si [nameFilter] viene del picker, conecta exactamente a ese nombre;
  /// si es null, por defecto busca un nombre que contenga "SmartCane".
  Future<void> connect({String? nameFilter}) async {
    try {
      // Limpia estado previo
      await disconnect();

      // Asegúrate que BT esté encendido
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        // intenta encender (en iOS/Android moderno no se puede programáticamente)
        // Se confía en que el usuario lo enciende desde la UI del SO.
      }

      // --- Escaneo ---
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

      late final StreamSubscription<List<ScanResult>> sub;
      final completer = Completer<void>();

      sub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          final name = r.device.platformName;
          final matches = (nameFilter != null && nameFilter.isNotEmpty)
              ? (name == nameFilter)
              : name.contains('SmartCane');

          if (matches) {
            await FlutterBluePlus.stopScan();
            await sub.cancel();

            _dev = r.device;

            // Conexión (timeout amplio por si tarda)
            await _dev!.connect(timeout: const Duration(seconds: 35));

            // Descubre servicios / características
            final services = await _dev!.discoverServices();
            final service = services.firstWhere(
              (s) => s.uuid.str.toLowerCase() == _svcUuid,
              orElse: () => throw Exception('Servicio $_svcUuid no encontrado'),
            );

            for (final c in service.characteristics) {
              final id = c.uuid.str.toLowerCase();
              if (id == _statusUuid) _chStatus = c;
              if (id == _ctrlUuid)   _chCtrl   = c;
            }

            // Suscríbete a NOTIFY de status
            if (_chStatus != null && _chStatus!.properties.notify) {
              await _chStatus!.setNotifyValue(true);
              _chStatus!.onValueReceived.listen((bytes) {
                final msg = String.fromCharCodes(bytes);
                _statusStreamCtrl.add(msg);
              });
            }

            _connected = true;
            _connStreamCtrl.add(true);
            completer.complete();
            return;
          }
        }
      });

      // Espera a que se complete la conexión o termine el tiempo de escaneo
      await completer.future.timeout(const Duration(seconds: 8), onTimeout: () async {
        try {
          await FlutterBluePlus.stopScan();
          await sub.cancel();
        } catch (_) {}
        if (!_connected) {
          _connStreamCtrl.add(false);
          throw Exception('No se encontró el dispositivo (¿SmartCane encendido y cerca?)');
        }
      });
    } catch (e) {
      _connected = false;
      _connStreamCtrl.add(false);
      rethrow;
    }
  }

  /// Desconecta si está conectado
  Future<void> disconnect() async {
    try {
      if (_dev != null) {
        await _dev!.disconnect();
      }
    } catch (_) {
      // ignora
    } finally {
      _dev = null;
      _chStatus = null;
      _chCtrl = null;
      if (_connected) {
        _connected = false;
        _connStreamCtrl.add(false);
      }
    }
  }

  /// Envía umbral de distancia al ESP32: "TH:<cm>"
  Future<void> setThreshold(int cm) async {
    if (_chCtrl == null) return;
    final payload = 'TH:$cm';
    await _writeAscii(_chCtrl!, payload);
  }

  /// Activa/desactiva sensores en el ESP32: "EN:1" / "EN:0"
  Future<void> setEnabled(bool enabled) async {
    if (_chCtrl == null) return;
    final payload = enabled ? 'EN:1' : 'EN:0';
    await _writeAscii(_chCtrl!, payload);
  }

  /// Escribe texto ASCII a una característica (maneja write / writeWithoutResponse)
  Future<void> _writeAscii(BluetoothCharacteristic ch, String text) async {
    final bytes = text.codeUnits;
    if (ch.properties.writeWithoutResponse) {
      await ch.write(bytes, withoutResponse: true);
    } else {
      await ch.write(bytes, withoutResponse: false);
    }
  }

  void dispose() {
    _statusStreamCtrl.close();
    _connStreamCtrl.close();
    // Nota: no llamamos disconnect() aquí para no cortar si el objeto
    // se recicla; haz disconnect() desde quien sea dueño del helper si quieres.
  }
}
