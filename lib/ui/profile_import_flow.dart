import 'package:flutter/material.dart';

import '../app.dart';
import '../icons/icon_catalog.dart';
import '../models/config.dart';

Future<bool> installSharedProfile(
  BuildContext context,
  ProfileConfig profile,
) async {
  final controller = SmartKeysScope.of(context);
  String? replaceProfileId;
  if (!controller.canAddProfile) {
    replaceProfileId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Replace a profile'),
              subtitle: Text(
                'The free version keeps up to $freeProfileLimit profiles. '
                'Choose the slot to replace with ${profile.name}.',
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: controller.orderedProfiles
                    .map(
                      (existing) => ListTile(
                        key: ValueKey('replace-profile-${existing.id}'),
                        leading: Icon(
                          BuiltinIconCatalog.find(
                                existing.profileIcon.value,
                              )?.icon ??
                              Icons.dashboard_customize_outlined,
                        ),
                        title: Text(existing.name),
                        subtitle:
                            existing.id == controller.config.activeProfileId
                            ? const Text('Currently active')
                            : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(sheetContext, existing.id),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
    if (replaceProfileId == null || !context.mounted) return false;
  }
  await controller.importProfile(profile, replaceProfileId: replaceProfileId);
  return true;
}
