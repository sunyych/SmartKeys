#ifndef LUMIAKEY_INSTALLED_APPS_H_
#define LUMIAKEY_INSTALLED_APPS_H_
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateInstalledAppsChannel(flutter::BinaryMessenger* messenger);
#endif
