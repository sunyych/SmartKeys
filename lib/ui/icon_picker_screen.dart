import 'package:flutter/material.dart';

import '../icons/icon_catalog.dart';

class IconPickerScreen extends StatefulWidget {
  const IconPickerScreen({super.key, this.selectedId});

  final String? selectedId;

  @override
  State<IconPickerScreen> createState() => _IconPickerScreenState();
}

class _IconPickerScreenState extends State<IconPickerScreen> {
  static final Set<String> favorites = {};
  static final List<String> recent = [];

  String query = '';
  String? category;

  @override
  Widget build(BuildContext context) {
    final categories = BuiltinIconCatalog.entries
        .map((entry) => entry.category)
        .toSet();
    final entries = BuiltinIconCatalog.entries.where((entry) {
      final matchesCategory = category == null || entry.category == category;
      final needle = query.trim().toLowerCase();
      return matchesCategory &&
          (needle.isEmpty ||
              entry.label.toLowerCase().contains(needle) ||
              entry.id.toLowerCase().contains(needle));
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Built-in Icons'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Clear'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              hintText: 'Search semantic icon names',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: category == null,
                  onSelected: (_) => setState(() => category = null),
                ),
                if (recent.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Recent'),
                    selected: category == '__recent',
                    onSelected: (_) => setState(() => category = '__recent'),
                  ),
                ],
                if (favorites.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Favorites'),
                    selected: category == '__favorites',
                    onSelected: (_) => setState(() => category = '__favorites'),
                  ),
                ],
                ...categories.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: FilterChip(
                      label: Text(item),
                      selected: category == item,
                      onSelected: (_) => setState(() => category = item),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisExtent: 118,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _filteredSpecial(entries).length,
              itemBuilder: (context, index) {
                final entry = _filteredSpecial(entries)[index];
                final selected = entry.id == widget.selectedId;
                return InkWell(
                  onTap: () {
                    recent
                      ..remove(entry.id)
                      ..insert(0, entry.id);
                    if (recent.length > 12) recent.removeLast();
                    Navigator.pop(context, entry.id);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : const Color(0xFF151E2A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2B394C)),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(entry.icon, size: 34),
                              const SizedBox(height: 7),
                              Text(
                                entry.label,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton(
                            tooltip: 'Favorite',
                            iconSize: 18,
                            onPressed: () => setState(() {
                              if (!favorites.add(entry.id)) {
                                favorites.remove(entry.id);
                              }
                            }),
                            icon: Icon(
                              favorites.contains(entry.id)
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<BuiltinIconDefinition> _filteredSpecial(
    List<BuiltinIconDefinition> normal,
  ) {
    if (category == '__recent') {
      return recent
          .map(BuiltinIconCatalog.find)
          .whereType<BuiltinIconDefinition>()
          .toList();
    }
    if (category == '__favorites') {
      return BuiltinIconCatalog.entries
          .where((entry) => favorites.contains(entry.id))
          .toList();
    }
    return normal;
  }
}
