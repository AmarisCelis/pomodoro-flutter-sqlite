import 'package:flutter/material.dart';

import '../services/sync_service.dart';

/// Inicio de sesión en la API y sincronización manual.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _sesionIniciada = false;
  bool _ocupado = false;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final url = await SyncService.instance.obtenerUrl();
    final sesion = await SyncService.instance.haySesion();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = url;
      _sesionIniciada = sesion;
    });
  }

  /// Ejecuta una acción de red mostrando el estado de carga y el resultado.
  Future<void> _ejecutar(Future<String> Function() accion) async {
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      final resultado = await accion();
      if (mounted) setState(() => _mensaje = resultado);
    } on SyncException catch (e) {
      if (mounted) setState(() => _mensaje = e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;
    await _ejecutar(() async {
      await SyncService.instance.iniciarSesion(
        url: _urlCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (mounted) setState(() => _sesionIniciada = true);
      return 'Sesión iniciada. Ya puedes sincronizar.';
    });
  }

  Future<void> _cerrarSesion() async {
    await SyncService.instance.cerrarSesion();
    if (!mounted) return;
    setState(() {
      _sesionIniciada = false;
      _mensaje = 'Sesión cerrada en este equipo.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Dirección de la API',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || !v.trim().startsWith('http'))
                      ? 'Escribe una URL que empiece con http'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _ocupado ? null : _iniciarSesion,
                  child: const Text('Iniciar sesión'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: (_ocupado || !_sesionIniciada)
                      ? null
                      : () => _ejecutar(SyncService.instance.sincronizar),
                  child: const Text('Sincronizar ahora'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: (_ocupado || !_sesionIniciada)
                      ? null
                      : _cerrarSesion,
                  child: const Text('Cerrar sesión en este equipo'),
                ),
                const SizedBox(height: 16),
                if (_ocupado) const LinearProgressIndicator(),
                if (_mensaje != null)
                  Text(_mensaje!, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
