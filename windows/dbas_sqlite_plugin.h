#ifndef FLUTTER_PLUGIN_DBAS_SQLITE_PLUGIN_H_
#define FLUTTER_PLUGIN_DBAS_SQLITE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace dbas_sqlite {

class DbasSqlitePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DbasSqlitePlugin();

  virtual ~DbasSqlitePlugin();

  // Disallow copy and assign.
  DbasSqlitePlugin(const DbasSqlitePlugin&) = delete;
  DbasSqlitePlugin& operator=(const DbasSqlitePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace dbas_sqlite

#endif  // FLUTTER_PLUGIN_DBAS_SQLITE_PLUGIN_H_
