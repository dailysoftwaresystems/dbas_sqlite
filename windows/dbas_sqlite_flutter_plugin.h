#ifndef FLUTTER_PLUGIN_DBAS_SQLITE_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_DBAS_SQLITE_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace dbas_sqlite_flutter {

class DbasSqliteFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DbasSqliteFlutterPlugin();

  virtual ~DbasSqliteFlutterPlugin();

  // Disallow copy and assign.
  DbasSqliteFlutterPlugin(const DbasSqliteFlutterPlugin&) = delete;
  DbasSqliteFlutterPlugin& operator=(const DbasSqliteFlutterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace dbas_sqlite_flutter

#endif  // FLUTTER_PLUGIN_DBAS_SQLITE_FLUTTER_PLUGIN_H_
