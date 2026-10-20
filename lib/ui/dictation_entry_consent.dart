import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const dictationConsentPreferenceKey = 'dictation.entry_explained.v1';

Future<bool> ensureDictationEntryExplained(BuildContext context) async {
  final preferences = await SharedPreferences.getInstance();
  if (preferences.getBool(dictationConsentPreferenceKey) == true) return true;
  if (!context.mounted) return false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('dictation-entry-explanation'),
      scrollable: true,
      title: const Text('Two ways to speak'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.graphic_eq),
            title: Text('Application voice input'),
            subtitle: Text(
              'Runs the selected computer app’s shortcut and follows that app’s microphone and privacy settings.',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.mic_external_on),
            title: Text('Local quick dictation'),
            subtitle: Text(
              'Recognizes speech on this phone and sends text to the connected computer.',
            ),
          ),
          Text(
            'Only Local quick dictation guarantees on-device recognition. It sends finalized text only.',
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('dictation-explanation-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const ValueKey('dictation-explanation-accept'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Understood'),
        ),
      ],
    ),
  );
  if (accepted != true) return false;
  await preferences.setBool(dictationConsentPreferenceKey, true);
  return true;
}
