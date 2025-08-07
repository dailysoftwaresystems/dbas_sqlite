add_library(dbas_sqlite STATIC IMPORTED GLOBAL)
set_target_properties(dbas_sqlite PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/dbas_sqlite.xcframework/macos-arm64_x86_64/dbas_sqlite.a"
)

target_link_libraries(dbas_sqlite_flutter PRIVATE dbas_sqlite)

# --- Automatically copy SQLite DYLIB after build ---
if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
  set(SQLITE_DYLIB "${CMAKE_CURRENT_LIST_DIR}/../native_libs/sqlite/macos/a64/dbas_sqlite.dylib")
  set(ARCH a64)
else()
  set(SQLITE_DYLIB "${CMAKE_CURRENT_LIST_DIR}/../native_libs/sqlite/macos/x86/dbas_sqlite.dylib")
  set(ARCH x86)
endif()
set(SQLITE_DYLIB_DEST "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/libs/${ARCH}/dbas_sqlite.dylib")
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/libs/${ARCH}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${SQLITE_DYLIB}" "${SQLITE_DYLIB_DEST}"
)
