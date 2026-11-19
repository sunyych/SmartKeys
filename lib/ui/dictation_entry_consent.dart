import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mobile_appearance.dart';

const dictationConsentPreferenceKey = 'dictation.entry_explained.v5';

Future<bool> ensureDictationEntryExplained(BuildContext context) async {
  final preferences = await SharedPreferences.getInstance();
  if (preferences.getBool(dictationConsentPreferenceKey) == true) return true;
  if (!context.mounted) return false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('dictation-entry-explanation'),
      scrollable: true,
      title: const MobileText('Two ways to speak', '两种语音输入方式'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.graphic_eq),
            title: MobileText('Application voice input', '应用内语音输入'),
            subtitle: MobileText(
              'Runs the selected computer app’s shortcut and follows that app’s microphone and privacy settings.',
              '触发电脑上已选应用的快捷键，并遵循该应用的麦克风和隐私设置。',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.mic_external_on),
            title: MobileText('Local quick dictation', '本地快速听写'),
            subtitle: MobileText(
              'Tap the microphone to quick-start with the selected output. Hold it for output and language settings; after starting, stop from the corner chip, then hold the microphone to change settings. Bluetooth sends English ASCII through the connected keyboard; LumiaKey Desktop supports multilingual dictation and needs the PC companion.',
              '轻点麦克风，即可以选定的方式输出。长按可设置输出和语言。听写开始后，可从角落的状态按钮结束，再长按麦克风修改设置。蓝牙键盘发送英文 ASCII 字符，LumiaKey Desktop 支持多语言听写，需要连接电脑。',
            ),
          ),
          MobileText(
            'Local quick dictation recognizes speech on this phone. Its audio is never sent over the network or saved. Bluetooth English sends printable ASCII key presses and needs a US keyboard layout with English input active. LumiaKey Desktop sends only finalized text over the local network to the PC companion; use it for Chinese and other languages. Application voice input follows the selected computer app’s microphone and privacy settings.',
            '本地快速听写在手机上识别语音，音频不经网络发送，也不保存。蓝牙英文模式发送可打印的 ASCII 按键，需要启用美式键盘布局和英文输入法。中文及其他语言可使用 LumiaKey Desktop，仅将识别完成的文字通过局域网发到电脑。应用内语音输入遵循所选电脑应用的麦克风和隐私设置。',
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('dictation-explanation-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const MobileText('Not now', '暂不使用'),
        ),
        FilledButton(
          key: const ValueKey('dictation-explanation-accept'),
          onPressed: () => Navigator.pop(context, true),
          child: const MobileText('Understood', '我知道了'),
        ),
      ],
    ),
  );
  if (accepted != true) return false;
  await preferences.setBool(dictationConsentPreferenceKey, true);
  return true;
}
