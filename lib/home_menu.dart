// lib/home_menu.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

import 'ble_helper.dart';
import 'device_picker_page.dart';

/// --------------------------------------------------------------
/// Permisos BLE/Ubicación
/// --------------------------------------------------------------
Future<bool> ensureBlePermissions() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return false;

  final scan = await Permission.bluetoothScan.request();
  final conn = await Permission.bluetoothConnect.request();
  final loc = await Permission.location
      .request(); // requerido por varias versiones

  return scan.isGranted && conn.isGranted && (loc.isGranted || loc.isLimited);
}

/// ==============================================================
///                   DASHBOARD ÚNICO (sin pestañas)
/// ==============================================================
class HomeMenu extends StatefulWidget {
  HomeMenu({Key? key}) : super(key: key);

  @override
  State<HomeMenu> createState() => _HomeMenuState();
}

class _HomeMenuState extends State<HomeMenu> {
  late final BleHelper _ble;

  // -------- Eventos (recuadro) ----------
  final List<_RiskEventView> _events = []; // buffer acotado
  _RiskEventView? _current; // último evento relevante
  static const int _maxEvents = 20; // límite dentro del card
  StreamSubscription<String>? _statusSub;

  // -------- SOS ----------
  // Se guardan como número nacional de 10 dígitos (ej. 8991234567)
  String phone1 = '8991234567';
  String phone2 = '8999876543';

  // -------- GPS ----------
  bool _tracking = false;
  Position? _lastPos;
  final List<Position> _history = [];
  static const int _maxHistory = 30;
  StreamSubscription<Position>? _posSub;

  // Google Maps
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  bool _isPushing = false;

  @override
  void initState() {
    super.initState();
    _ble = BleHelper();

    // Diferir permisos + autoconexión para evitar jank inicial
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await ensureBlePermissions()) {
        try {
          await _ble.connect();
        } catch (_) {}
      }
      _listenBleStatus(); // empieza a escuchar mensajes BLE
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _posSub?.cancel();
    _ble.dispose();
    super.dispose();
  }

  void _listenBleStatus() {
    _statusSub?.cancel();
    _statusSub = _ble.statusStream.listen((msg) async {
      // Formatos esperados:
      // "OBS|27.3"  => evento de obstáculo con distancia en cm
      // "SOS|1"     => botón SOS del bastón
      final parts = msg.split('|');
      if (parts.length != 2) return;
      final t = parts[0].trim().toUpperCase();
      final v = parts[1].trim();

      if (t == 'OBS') {
        final dist = double.tryParse(v) ?? 0;
        final level = dist < 10
            ? _RiskLevel.critico
            : (dist < 20 ? _RiskLevel.alto : _RiskLevel.medio);

        final ev = _RiskEventView(
          title: 'Obstáculo cercano',
          detail: 'Obstáculo a ${dist.toStringAsFixed(1)} cm',
          level: level,
          time: DateTime.now(),
        );

        setState(() {
          _current = ev;
          _events.insert(0, ev);
          if (_events.length > _maxEvents) {
            _events.removeRange(_maxEvents, _events.length);
          }
        });
      } else if (t == 'SOS') {
        // Al recibir SOS desde el bastón mandamos WhatsApp en cascada
        await _startCascadeWhatsApp();
      }
    });
  }

  // ===================== LLAMADAS =====================

  /// Intenta hacer llamada directa al número (10 dígitos) usando FlutterPhoneDirectCaller
  Future<bool> _callNumber(String number) async {
    try {
      final res = await FlutterPhoneDirectCaller.callNumber(number);
      final ok = res ?? false;
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo iniciar la llamada directa'),
          ),
        );
      }
      return ok;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al intentar llamar')),
        );
      }
      return false;
    }
  }

  /// Llama primero al contacto 1 y, si falla, al 2
  Future<void> _startCascadeCall() async {
    final ok1 = await _callNumber(phone1);
    if (!ok1) {
      await _callNumber(phone2);
    }
  }

  // ===================== WHATSAPP + UBICACIÓN =====================

  /// Obtiene ubicación actual (para SOS) pidiendo permisos si hace falta
  Future<Position?> _getCurrentPositionForSOS() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso de ubicación denegado')),
        );
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      // también actualizamos el estado de la tarjeta GPS
      setState(() {
        _lastPos = pos;
        _history.insert(0, pos);
        if (_history.length > _maxHistory) {
          _history.removeRange(_maxHistory, _history.length);
        }
      });
      await _moveMapToLastPos();
      return pos;
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la ubicación')),
      );
      return null;
    }
  }

  /// Abre WhatsApp con mensaje de ubicación para un teléfono nacional (10 dígitos)
  Future<bool> _sendWhatsAppTo(String nationalPhone) async {
    final pos = await _getCurrentPositionForSOS();
    final bool hasLocation = pos != null;

    final String message;
    if (hasLocation) {
      final lat = pos!.latitude;
      final lng = pos.longitude;
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      message = 'EMERGENCIA 🚨\nEsta es mi ubicación actual:\n$mapsUrl';
    } else {
      message =
          'EMERGENCIA 🚨\nIntenté compartir mi ubicación, pero no se pudo obtener desde el dispositivo.';
    }

    // WhatsApp necesita formato internacional → para México: 52 + 10 dígitos
    final waPhone = '52$nationalPhone';
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$waPhone?text=$encoded');

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
      return ok;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al abrir WhatsApp')),
        );
      }
      return false;
    }
  }

  /// Envía por WhatsApp primero a contacto 1 y, si falla, a contacto 2
  Future<void> _startCascadeWhatsApp() async {
    final ok1 = await _sendWhatsAppTo(phone1);
    if (!ok1) {
      await _sendWhatsAppTo(phone2);
    }
  }

  Future<void> _editPhone(int index) async {
    final current = index == 1 ? phone1 : phone2;
    final controller = TextEditingController(text: current);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Editar contacto $index'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Número (10 dígitos)',
              hintText: 'Ej. 8991234567',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                Navigator.pop(ctx, value.isEmpty ? null : value);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        if (index == 1) {
          phone1 = result;
        } else {
          phone2 = result;
        }
      });
    }
  }

  // ===================== GPS (historial / mapa) =====================
  Future<void> _toggleTracking() async {
    if (_tracking) {
      await _posSub?.cancel();
      setState(() {
        _tracking = false;
      });
      return;
    }

    // Pedir permisos de ubicación
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación denegado')),
      );
      return;
    }

    // Última ubicación inicial
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _lastPos = pos;
        _history.insert(0, pos);
        if (_history.length > _maxHistory) {
          _history.removeRange(_maxHistory, _history.length);
        }
      });
      await _moveMapToLastPos();
    } catch (_) {}

    // Stream de ubicaciones
    _posSub?.cancel();
    _posSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 5, // metros
          ),
        ).listen((pos) async {
          setState(() {
            _lastPos = pos;
            _history.insert(0, pos);
            if (_history.length > _maxHistory) {
              _history.removeRange(_maxHistory, _history.length);
            }
          });
          await _moveMapToLastPos();
        });

    setState(() => _tracking = true);
  }

  Future<void> _moveMapToLastPos() async {
    if (_lastPos == null) return;
    if (!_mapController.isCompleted) return;

    final controller = await _mapController.future;
    final target = LatLng(_lastPos!.latitude, _lastPos!.longitude);
    controller.animateCamera(CameraUpdate.newLatLng(target));
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartCane Dashboard'),
        actions: [
          StreamBuilder<bool>(
            stream: _ble.connectionStream,
            initialData: _ble.isConnected,
            builder: (ctx, snap) {
              final ok = snap.data ?? false;
              return IconButton(
                tooltip: ok ? 'Conectado' : 'Reconectar',
                icon: Icon(
                  ok ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                ),
                onPressed: () async {
                  if (await ensureBlePermissions()) {
                    try {
                      await _ble.connect();
                    } catch (_) {}
                  }
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Agregar dispositivo',
            icon: const Icon(Icons.add_link),
            onPressed: () async {
              if (_isPushing) return;
              setState(() => _isPushing = true);
              try {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DevicePickerPage(ble: _ble),
                  ),
                );
              } finally {
                if (mounted) setState(() => _isPushing = false);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _connectionBanner(),
          _eventsCard(),
          const SizedBox(height: 16),
          _sosCard(),
          const SizedBox(height: 16),
          _gpsCard(),
        ],
      ),
    );
  }

  Widget _connectionBanner() {
    return StreamBuilder<bool>(
      stream: _ble.connectionStream,
      initialData: _ble.isConnected,
      builder: (context, snap) {
        final ok = snap.data ?? false;
        final bg = (ok ? Colors.green : Colors.red).withOpacity(0.12);
        final fg = ok ? Colors.green[800] : Colors.red[800];

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                ok ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: fg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? 'Conectado a SmartCane'
                      : 'Desconectado. Buscando dispositivo…',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _eventsCard() {
    final levelColor = _current == null
        ? Colors.grey
        : _levelToColor(_current!.level);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Row(
              children: [
                Icon(Icons.sensors, color: levelColor),
                const SizedBox(width: 8),
                const Text(
                  'Eventos (Riesgos)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_current != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _levelToText(_current!.level),
                      style: TextStyle(
                        color: levelColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Estado actual
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: levelColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _current == null
                  ? const Text('Sin eventos aún. Acerca un objeto al sensor.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _current!.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(_current!.detail),
                        const SizedBox(height: 6),
                        Text(
                          _fmtTime(_current!.time),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 12),

            // Lista interna con altura fija (no crece la página)
            SizedBox(
              height: 220,
              child: _events.isEmpty
                  ? const Center(child: Text('Aún no hay historial.'))
                  : ListView.separated(
                      itemCount: _events.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _events[i];
                        final c = _levelToColor(e.level);
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: c.withOpacity(0.15),
                            child: Icon(Icons.sensors, color: c, size: 18),
                          ),
                          title: Text(e.title),
                          subtitle: Text('${e.detail}\n${_fmtTime(e.time)}'),
                          isThreeLine: true,
                          trailing: Text(
                            _levelToText(e.level),
                            style: TextStyle(
                              color: c,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sosCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.warning_amber, color: Colors.redAccent),
                SizedBox(width: 8),
                Text(
                  'SOS (Llamada + WhatsApp)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Contacto 1
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person),
              title: const Text('Contacto 1'),
              subtitle: Text(phone1),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone),
                    tooltip: 'Llamar directo',
                    onPressed: () => _callNumber(phone1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat),
                    tooltip: 'WhatsApp',
                    onPressed: () => _sendWhatsAppTo(phone1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Editar',
                    onPressed: () => _editPhone(1),
                  ),
                ],
              ),
            ),

            // Contacto 2
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: const Text('Contacto 2'),
              subtitle: Text(phone2),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone),
                    tooltip: 'Llamar directo',
                    onPressed: () => _callNumber(phone2),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat),
                    tooltip: 'WhatsApp',
                    onPressed: () => _sendWhatsAppTo(phone2),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Editar',
                    onPressed: () => _editPhone(2),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Botones grandes
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startCascadeCall,
                icon: const Icon(Icons.phone_forwarded),
                label: const Text('Llamar en cascada (1 → 2)'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startCascadeWhatsApp,
                icon: const Icon(Icons.send),
                label: const Text('Enviar ubicación por WhatsApp (1 → 2)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 8),
            const Text(
              'WhatsApp: el mensaje se prepara con tu ubicación, pero siempre debes presionar "Enviar" dentro de WhatsApp (no se puede mandar totalmente automático).',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gpsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.location_on, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text(
                  'Ubicación (historial del móvil)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _toggleTracking,
                  icon: Icon(_tracking ? Icons.pause : Icons.play_arrow),
                  label: Text(_tracking ? 'Detener' : 'Iniciar rastreo'),
                ),
                const SizedBox(width: 10),
                if (_lastPos != null)
                  Flexible(
                    child: Text(
                      'Última: ${_lastPos!.latitude.toStringAsFixed(5)}, ${_lastPos!.longitude.toStringAsFixed(5)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Google Maps integrado
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _lastPos?.latitude ?? 19.432608, // CDMX default
                      _lastPos?.longitude ?? -99.133209,
                    ),
                    zoom: 15,
                  ),
                  markers: _lastPos == null
                      ? {}
                      : {
                          Marker(
                            markerId: const MarkerId('last'),
                            position: LatLng(
                              _lastPos!.latitude,
                              _lastPos!.longitude,
                            ),
                            infoWindow: const InfoWindow(
                              title: 'Última ubicación',
                            ),
                          ),
                        },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  onMapCreated: (controller) {
                    if (!_mapController.isCompleted) {
                      _mapController.complete(controller);
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 200,
              child: _history.isEmpty
                  ? const Center(child: Text('Sin historial todavía.'))
                  : ListView.separated(
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _history[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place),
                          title: Text(
                            '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                          ),
                          subtitle: Text(
                            _fmtTime(p.timestamp ?? DateTime.now()),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------- helpers UI -----------------
  Color _levelToColor(_RiskLevel l) {
    switch (l) {
      case _RiskLevel.bajo:
        return Colors.green;
      case _RiskLevel.medio:
        return Colors.orange;
      case _RiskLevel.alto:
        return Colors.deepOrange;
      case _RiskLevel.critico:
        return Colors.red;
    }
  }

  String _levelToText(_RiskLevel l) {
    switch (l) {
      case _RiskLevel.bajo:
        return 'Bajo';
      case _RiskLevel.medio:
        return 'Medio';
      case _RiskLevel.alto:
        return 'Alto';
      case _RiskLevel.critico:
        return 'Crítico';
    }
  }

  String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final mo = t.month.toString().padLeft(2, '0');
    return '$h:$m  $d/$mo';
  }
}

/// Modelo simple solo para la vista
class _RiskEventView {
  final String title;
  final String detail;
  final _RiskLevel level;
  final DateTime time;

  _RiskEventView({
    required this.title,
    required this.detail,
    required this.level,
    required this.time,
  });
}

enum _RiskLevel { bajo, medio, alto, critico }
