// lib/device_picker_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_helper.dart';

class DevicePickerPage extends StatefulWidget {
  const DevicePickerPage({Key? key, required this.ble}) : super(key: key);
  final BleHelper ble;

  @override
  State<DevicePickerPage> createState() => _DevicePickerPageState();
}

class _DevicePickerPageState extends State<DevicePickerPage> {
  final List<ScanResult> _found = [];
  StreamSubscription<List<ScanResult>>? _sub;
  bool _scanning = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSub();
    FlutterBluePlus.stopScan().ignore();
    super.dispose();
  }

  void _setStateSafe(VoidCallback fn) {
    if (!_disposed && mounted) setState(fn);
  }

  Future<void> _cancelSub() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
  }

  Future<void> _startScan() async {
    _found.clear();
    _setStateSafe(() => _scanning = true);

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    _sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (!_found.any((e) => e.device.remoteId == r.device.remoteId)) {
          _found.add(r);
        }
      }
      _setStateSafe(() {});
    }, onDone: () {
      _setStateSafe(() => _scanning = false);
    }, onError: (_) {
      _setStateSafe(() => _scanning = false);
    });
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _cancelSub();
    _setStateSafe(() => _scanning = false);
  }

  Future<void> _connectTo(ScanResult r) async {
    await _stopScan();
    await widget.ble.connect(
      nameFilter: r.device.platformName.isNotEmpty
          ? r.device.platformName
          : null,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agregar dispositivo'),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Volver a escanear',
            ),
        ],
      ),
      body: _found.isEmpty
          ? const Center(
              child: Text(
                'Buscando dispositivos BLE cercanos...\n'
                'Asegúrate de encender tu ESP32',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              itemCount: _found.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _found[i];
                final name = r.device.platformName.isNotEmpty
                    ? r.device.platformName
                    : '(Sin nombre)';
                return ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(name),
                  subtitle:
                      Text('${r.device.remoteId.str}  •  RSSI ${r.rssi}'),
                  trailing: ElevatedButton(
                    onPressed: () => _connectTo(r),
                    child: const Text('Conectar'),
                  ),
                  onTap: () => _connectTo(r),
                );
              },
            ),
    );
  }
}
