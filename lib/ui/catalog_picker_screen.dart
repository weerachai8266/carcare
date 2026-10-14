import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../models/car_catalog.dart';

/// รายการหนึ่งบรรทัดในหน้าเลือก ใช้ร่วมกันทั้งหน้าเลือกยี่ห้อและหน้าเลือกรุ่น
class _PickerItem {
  final String id;
  final String title;

  /// หัวข้อกลุ่ม เช่น ประเภทตัวถัง — null คือไม่จัดกลุ่ม
  final String? group;

  /// ข้อความที่ใช้เทียบตอนค้นหา
  final String searchText;

  final bool isCustom;

  const _PickerItem({
    required this.id,
    required this.title,
    this.group,
    required this.searchText,
    this.isCustom = false,
  });
}

/// หน้าเลือกยี่ห้อรถ คืน [CarMake] ที่เลือก หรือ null ถ้ากดย้อนกลับ
class MakePickerScreen extends StatelessWidget {
  const MakePickerScreen({super.key, this.selectedId});

  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final repo = CatalogRepository();

    return _CatalogPicker(
      title: 'เลือกยี่ห้อรถ',
      searchHint: 'ค้นหายี่ห้อ เช่น Toyota, โตโยต้า',
      selectedId: selectedId,
      addLabel: (text) => 'เพิ่มยี่ห้อ "$text"',
      load: () async {
        final makes = await repo.makes();
        return [
          for (final make in makes)
            _PickerItem(
              id: make.id,
              title: make.name,
              searchText: make.searchText,
              isCustom: make.isCustom,
            ),
        ];
      },
      onAdd: (text) async {
        final make = await repo.addCustomMake(text);
        return make.id;
      },
      resolve: (id) async => await repo.makeById(id),
    );
  }
}

/// หน้าเลือกรุ่นรถของยี่ห้อหนึ่ง คืน [CarModel] ที่เลือก
class ModelPickerScreen extends StatelessWidget {
  const ModelPickerScreen({
    super.key,
    required this.makeId,
    required this.makeName,
    this.selectedId,
  });

  final String makeId;
  final String makeName;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final repo = CatalogRepository();

    return _CatalogPicker(
      title: 'เลือกรุ่น $makeName',
      searchHint: 'ค้นหารุ่น',
      selectedId: selectedId,
      addLabel: (text) => 'เพิ่มรุ่น "$text"',
      load: () async {
        final models = await repo.modelsOfMake(makeId);
        return [
          for (final model in models)
            _PickerItem(
              id: model.id,
              title: model.name,
              group: model.isCustom ? 'เพิ่มเอง' : model.bodyType,
              searchText: model.name.toLowerCase(),
              isCustom: model.isCustom,
            ),
        ];
      },
      onAdd: (text) async {
        final model = await repo.addCustomModel(makeId: makeId, name: text);
        return model.id;
      },
      resolve: (id) async => await repo.modelById(id),
    );
  }
}

/// รายการค้นหาได้ + ปุ่มเพิ่มเอง ใช้ร่วมกันทั้งสองหน้า
class _CatalogPicker extends StatefulWidget {
  const _CatalogPicker({
    required this.title,
    required this.searchHint,
    required this.load,
    required this.onAdd,
    required this.resolve,
    required this.addLabel,
    this.selectedId,
  });

  final String title;
  final String searchHint;
  final String? selectedId;
  final Future<List<_PickerItem>> Function() load;

  /// เพิ่มรายการใหม่แล้วคืน id ของแถวที่ได้
  final Future<String> Function(String text) onAdd;

  /// แปลง id เป็นอ็อบเจ็กต์ที่จะส่งกลับให้หน้าก่อนหน้า
  final Future<Object?> Function(String id) resolve;

  final String Function(String text) addLabel;

  @override
  State<_CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<_CatalogPicker> {
  final _searchController = TextEditingController();
  late Future<List<_PickerItem>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pick(String id) async {
    final value = await widget.resolve(id);
    if (mounted) Navigator.of(context).pop(value);
  }

  Future<void> _add(String text) async {
    final id = await widget.onAdd(text);
    await _pick(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_PickerItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snapshot.data ?? const <_PickerItem>[];
                final query = _query.toLowerCase();
                final matches = query.isEmpty
                    ? all
                    : all.where((i) => i.searchText.contains(query)).toList();

                // ให้เพิ่มเองได้ก็ต่อเมื่อพิมพ์ชื่อที่ยังไม่มีเป๊ะ ๆ ในรายการ
                final canAdd = _query.isNotEmpty &&
                    !all.any((i) => i.title.toLowerCase() == query);

                if (matches.isEmpty && !canAdd) {
                  return Center(
                    child: Text('ไม่พบรายการที่ค้นหา',
                        style: theme.textTheme.bodyMedium),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    if (canAdd)
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: Text(widget.addLabel(_query)),
                        subtitle: const Text('ใช้เมื่อไม่มีในรายการ'),
                        onTap: () => _add(_query),
                      ),
                    ..._buildGrouped(matches, theme),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// แทรกหัวข้อกลุ่มเมื่อกลุ่มเปลี่ยน — รายการถูกเรียงตามกลุ่มมาแล้วจาก repository
  List<Widget> _buildGrouped(List<_PickerItem> items, ThemeData theme) {
    final widgets = <Widget>[];
    String? currentGroup;

    for (final item in items) {
      if (item.group != null && item.group != currentGroup) {
        currentGroup = item.group;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            currentGroup!,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ));
      }

      widgets.add(ListTile(
        title: Text(item.title),
        trailing: item.id == widget.selectedId
            ? Icon(Icons.check, color: theme.colorScheme.primary)
            : (item.isCustom ? const Icon(Icons.person_outline, size: 18) : null),
        onTap: () => _pick(item.id),
      ));
    }
    return widgets;
  }
}
