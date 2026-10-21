import 'dart:io';

import 'package:flutter/services.dart';

const privateUsageDirectoryChannel = MethodChannel('smart_keys/private_usage');

Future<Directory> privateUsageDirectory() async {
  final path = await privateUsageDirectoryChannel.invokeMethod<String>(
    'getPath',
  );
  if (path == null || path.isEmpty) {
    throw const FileSystemException('Private usage directory is unavailable');
  }
  return Directory(path);
}
