#include "include/dbas_sqlite/dbas_sqlite_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "dbas_sqlite_plugin.h"

void DbasSqlitePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  dbas_sqlite::DbasSqlitePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
