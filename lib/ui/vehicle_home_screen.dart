import 'package:flutter/material.dart';

import 'fuel_form_screen.dart';
import 'fuel_tab.dart';
import 'maintenance_tab.dart';
import 'model_stats_screen.dart';
import 'overview_tab.dart';
import 'service_form_screen.dart';
import 'task_form_screen.dart';
import 'vehicle_data.dart';
import 'vehicle_form_screen.dart';

/// หน้าหลักของรถหนึ่งคัน แบ่งเป็นสามแท็บ: ภาพรวม / น้ำมัน / บำรุงรักษา
///
/// โหลดข้อมูลที่ระดับนี้ที่เดียวแล้วส่งลงไปให้ทุกแท็บ
/// เพื่อไม่ให้แต่ละแท็บยิงคิวรีซ้ำและเห็นตัวเลขไม่ตรงกัน
class VehicleHomeScreen extends StatefulWidget {
  const VehicleHomeScreen({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  State<VehicleHomeScreen> createState() => _VehicleHomeScreenState();
}

class _VehicleHomeScreenState extends State<VehicleHomeScreen> {
  late Future<VehicleData?> _future;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _future = loadVehicleData(widget.vehicleId);
  }

  // ต้องใช้ body แบบวงเล็บปีกกา ไม่ใช่ arrow เพราะ arrow จะคืนค่า Future
  // ที่ได้จากการกำหนดค่าออกไป แล้ว setState จะ throw ทันที
  void _reload() {
    setState(() {
      _future = loadVehicleData(widget.vehicleId);
    });
  }

  Future<void> _openForm(Widget screen) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (changed == true) _reload();
  }

  void _openModelStats(VehicleData data) {
    final vehicle = data.vehicle;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModelStatsScreen(
          modelId: vehicle.modelId!,
          modelName: [vehicle.make, vehicle.model]
              .where((s) => s != null && s.isNotEmpty)
              .join(' '),
        ),
      ),
    );
  }

  Future<void> _editVehicle(VehicleData data) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VehicleFormScreen(vehicle: data.vehicle)),
    );
    if (changed != true) return;

    // ถ้ารถถูกลบไป หน้านี้ก็ไม่มีอะไรให้แสดงแล้ว
    final still = await loadVehicleData(widget.vehicleId);
    if (!mounted) return;
    if (still == null) {
      Navigator.of(context).pop();
    } else {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VehicleData?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('ไม่พบข้อมูลรถคันนี้')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(data.vehicle.name),
            actions: [
              IconButton(
                onPressed: () => _editVehicle(data),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'แก้ไขข้อมูลรถ',
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'add-task':
                      _openForm(TaskFormScreen(vehicleId: data.vehicle.id));
                    case 'model-stats':
                      _openModelStats(data);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'add-task',
                    child: Text('เพิ่มรายการบำรุงรักษา'),
                  ),
                  PopupMenuItem(
                    value: 'model-stats',
                    // ต้องรู้ว่าเป็นรถรุ่นไหนก่อน ถึงจะเทียบกับคันอื่นรุ่นเดียวกันได้
                    enabled: data.vehicle.modelId != null,
                    child: const Text('สถิติของรถรุ่นนี้'),
                  ),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: switch (_index) {
              0 => OverviewTab(data: data, onChanged: _reload),
              1 => FuelTab(data: data, onChanged: _reload),
              _ => MaintenanceTab(data: data, onChanged: _reload),
            },
          ),
          floatingActionButton: _fab(data),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'ภาพรวม',
              ),
              NavigationDestination(
                icon: Icon(Icons.local_gas_station_outlined),
                selectedIcon: Icon(Icons.local_gas_station),
                label: 'น้ำมัน',
              ),
              NavigationDestination(
                icon: Icon(Icons.build_outlined),
                selectedIcon: Icon(Icons.build),
                label: 'บำรุงรักษา',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _fab(VehicleData data) {
    if (_index == 2) {
      return FloatingActionButton.extended(
        onPressed: () => _openForm(ServiceFormScreen(data: data)),
        icon: const Icon(Icons.add_task),
        label: const Text('บันทึกที่ทำแล้ว'),
      );
    }
    return FloatingActionButton.extended(
      onPressed: () => _openForm(FuelFormScreen(data: data)),
      icon: const Icon(Icons.local_gas_station),
      label: const Text('เติมน้ำมัน'),
    );
  }
}
