import 'package:flutter/services.dart';

/// Executes a small, fixed set of OS-level actions in an expected Vibe app.
///
/// The phone supplies only an app ID and an allowlisted action suffix. Native
/// code verifies the foreground app and owns the actual glyph and OS action.
class VibeSystemTools {
  VibeSystemTools({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'lumiakeys/vibe_system_tools';
  static const _apps = {'codex', 'claude', 'cursor'};
  static const _actions = {
    'comma',
    'period',
    'exclamation',
    'quote',
    'screenshot',
  };

  final MethodChannel _channel;

  Future<void> execute(String appId, String actionId) async {
    if (!_apps.contains(appId)) {
      throw const FormatException('Unsupported Vibe app.');
    }
    if (!_actions.contains(actionId)) {
      throw const FormatException('Unsupported Vibe system action.');
    }
    final result = await _channel.invokeMapMethod<String, Object?>('execute', {
      'appId': appId,
      'actionId': actionId,
    });
    final status = result?['status'];
    if (status != 'delivered' && status != 'launched') {
      throw PlatformException(
        code: 'vibe_action_rejected',
        message: result?['reason']?.toString() ?? 'The action was rejected.',
      );
    }
  }
}
