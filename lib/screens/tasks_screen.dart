import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';

/// CRUD de tareas (OBJ-02).
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _tareas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final tareas = await _db.listarTareas();
    if (!mounted) return;
    setState(() {
      _tareas = tareas;
      _cargando = false;
    });
  }

  Future<void> _editar([Map<String, dynamic>? tarea]) async {
    final controller = TextEditingController(text: tarea?['titulo'] as String?);
    final titulo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tarea == null ? 'Nueva tarea' : 'Editar tarea'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Título'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    final t = titulo?.trim() ?? '';
    if (t.isEmpty) return;

    if (tarea == null) {
      await _db.insertarTarea({
        'id': const Uuid().v4(),
        'titulo': t,
        'completada': 0,
        'pomodoros_estimados': 1,
      });
    } else {
      await _db.actualizarTarea({'id': tarea['id'], 'titulo': t});
    }
    await _cargar();
  }

  Future<void> _alternar(Map<String, dynamic> tarea, bool? valor) async {
    await _db.actualizarTarea(
        {'id': tarea['id'], 'completada': (valor ?? false) ? 1 : 0});
    await _cargar();
  }

  Future<void> _eliminar(Map<String, dynamic> tarea) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text(
            '¿Eliminar "${tarea['titulo']}"? También se borrarán sus sesiones.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await _db.eliminarTarea(tarea['id'] as String);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tareas'), centerTitle: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editar(),
        tooltip: 'Nueva tarea',
        child: const Icon(Icons.add),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _tareas.isEmpty
              ? const Center(child: Text('No hay tareas. Agrega una con +'))
              : ListView.builder(
                  itemCount: _tareas.length,
                  itemBuilder: (_, i) {
                    final t = _tareas[i];
                    final hecha = (t['completada'] as int) == 1;
                    return ListTile(
                      leading: Checkbox(
                          value: hecha, onChanged: (v) => _alternar(t, v)),
                      title: Text(
                        t['titulo'] as String,
                        style: hecha
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                      onTap: () => _editar(t),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Eliminar',
                        onPressed: () => _eliminar(t),
                      ),
                    );
                  },
                ),
    );
  }
}
