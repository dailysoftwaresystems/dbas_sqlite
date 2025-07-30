add_library(dbas_sqlite STATIC IMPORTED GLOBAL)
set_target_properties(dbas_sqlite PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/dbas_sqlite.xcframework/macos-arm64/dbas_sqlite.a"
)

target_link_libraries(dbas_sqlite_flutter PRIVATE dbas_sqlite)
