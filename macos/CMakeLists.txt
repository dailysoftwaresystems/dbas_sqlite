add_library(dbas_sqlite_native STATIC IMPORTED GLOBAL)
set_target_properties(dbas_sqlite_native PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/dbas_sqlite.xcframework/macos-arm64_x86_64/dbas_sqlite.a"
)

# `dbas_sqlite` is the plugin target Flutter injects (matches `name:` in
# pubspec.yaml). Renamed the imported static lib above to `dbas_sqlite_native`
# so it doesn't collide with the Flutter-injected plugin target.
target_link_libraries(dbas_sqlite PRIVATE dbas_sqlite_native)

# --- Automatically copy SQLite DYLIB after build ---
if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
  set(ARCH a64)
else()
  set(ARCH x86)
endif()
set(SQLITE_DYLIB "${CMAKE_CURRENT_LIST_DIR}/libs/${ARCH}/dbas_sqlite.dylib")
set(SQLITE_DYLIB_DEST "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/libs/${ARCH}/dbas_sqlite.dylib")
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/libs/${ARCH}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${SQLITE_DYLIB}" "${SQLITE_DYLIB_DEST}"
)
