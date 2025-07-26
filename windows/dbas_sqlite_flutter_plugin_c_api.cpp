#include "include/dbas_sqlite_flutter/dbas_sqlite_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "dbas_sqlite_flutter_plugin.h"

void DbasSqliteFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  dbas_sqlite_flutter::DbasSqliteFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
