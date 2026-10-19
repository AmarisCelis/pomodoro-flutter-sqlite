import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// Claves de SharedPreferences (minutos).
  static const String claveTrabajo = 'minutos_trabajo';
  static const String claveDescanso = 'minutos_descanso';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _trabajoCtrl = TextEditingController();
  final _descansoCtrl = TextEditingController();

  @override
  void dispose() {
    _trabajoCtrl.dispose();
    _descansoCtrl.dispose();
    super.dispose();
  }

  String? _validar(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Este campo es obligatorio';
    }
    if ((int.tryParse(valor.trim()) ?? 0) <= 0) {
      return 'Debe ser mayor a 0';
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final trabajo = int.parse(_trabajoCtrl.text.trim());
    final descanso = int.parse(_descansoCtrl.text.trim());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.claveTrabajo, trabajo);
    await prefs.setInt(SettingsScreen.claveDescanso, descanso);
    debugPrint('Guardado -> trabajo: $trabajo min, descanso: $descanso min');

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void initState() {
    super.initState();
    _cargarValoresActuales();
  }

  Future<void> _cargarValoresActuales() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _trabajoCtrl.text = (prefs.getInt(SettingsScreen.claveTrabajo) ?? 25).toString();
    _descansoCtrl.text = (prefs.getInt(SettingsScreen.claveDescanso) ?? 5).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Tiempos'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _trabajoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Minutos de Trabajo',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validar,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descansoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Minutos de Descanso',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validar,
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _guardar,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
