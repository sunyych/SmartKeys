import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const dictationConsentPreferenceKey = 'dictation.entry_explained.v4';

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
              'Bluetooth English types ASCII through the connected keyboard without PC software. LumiaKey Desktop supports multilingual dictation and needs the PC companion.',
            ),
          ),
          Text(
            'Local quick dictation recognizes speech on this phone. Its audio is never sent over the network or saved. Bluetooth English sends printable ASCII key presses and needs a US keyboard layout with English input active. LumiaKey Desktop sends only finalized text over the local network to the PC companion; use it for Chinese and other languages. Application voice input follows the selected computer app’s microphone and privacy settings.',
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
