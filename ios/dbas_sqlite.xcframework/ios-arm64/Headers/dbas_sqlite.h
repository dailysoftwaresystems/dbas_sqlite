#ifdef _WIN32
#define DLL_EXPORT __declspec(dllexport)
#else
#define DLL_EXPORT __attribute__((visibility("default")))
#endif

#pragma once
#include "sqlite/sqlite3.h"

#ifndef __EMSCRIPTEN__
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif
    typedef struct SQLiteDb {
        sqlite3* db;
        sqlite3_stmt* stmt;
        char* lastError;
        char* fileName;
    } SQLiteDb;

    DLL_EXPORT SQLiteDb* OpenDb(const char* fileName);
    DLL_EXPORT bool IsOpened(SQLiteDb* inst);

    DLL_EXPORT int ExecuteSql(SQLiteDb* inst, const char* sql);

    DLL_EXPORT int PrepareQuery(SQLiteDb* inst, const char* sql);

    DLL_EXPORT int BindText(SQLiteDb* inst, int index, const char* value);
    DLL_EXPORT int BindInt(SQLiteDb* inst, int index, int value);
    DLL_EXPORT int BindFloat(SQLiteDb* inst, int index, float value);
    DLL_EXPORT int BindDouble(SQLiteDb* inst, int index, double value);
    DLL_EXPORT int BindNull(SQLiteDb* inst, int index);
    DLL_EXPORT int BindBlob(SQLiteDb* inst, int index, const void* data, int length);

    DLL_EXPORT int BindNameText(SQLiteDb* inst, const char* name, const char* value);
    DLL_EXPORT int BindNameInt(SQLiteDb* inst, const char* name, int value);
    DLL_EXPORT int BindNameFloat(SQLiteDb* inst, const char* name, float value);
    DLL_EXPORT int BindNameDouble(SQLiteDb* inst, const char* name, double value);
    DLL_EXPORT int BindNameNull(SQLiteDb* inst, const char* name);
    DLL_EXPORT int BindNameBlob(SQLiteDb* inst, const char* name, const void* data, int length);

    DLL_EXPORT int ReadRow(SQLiteDb* inst);
    DLL_EXPORT int IsNull(SQLiteDb* inst, int col_index);
    DLL_EXPORT char* GetColumnText(SQLiteDb* inst, int col_index);
    DLL_EXPORT int GetColumnInt(SQLiteDb* inst, int col_index);
    DLL_EXPORT float GetColumnFloat(SQLiteDb* inst, int col_index);
    DLL_EXPORT double GetColumnDouble(SQLiteDb* inst, int col_index);
    DLL_EXPORT int GetColumnType(SQLiteDb* inst, int col_index);
    DLL_EXPORT const void* GetColumnBlob(SQLiteDb* inst, int index);
    DLL_EXPORT int GetColumnBytes(SQLiteDb* inst, int index);
    DLL_EXPORT char* GetColumnName(SQLiteDb* inst, int index);
    DLL_EXPORT int GetColumnCount(SQLiteDb* inst);

    DLL_EXPORT const char* GetLastDbError(SQLiteDb* inst);
    DLL_EXPORT int GetAffectedRows(SQLiteDb* inst);
    DLL_EXPORT long long GetLastInsertedId(SQLiteDb* inst);

    DLL_EXPORT void CloseReader(SQLiteDb* inst);
    DLL_EXPORT void CloseDb(SQLiteDb* inst);

    // ─── Connection Pool ───

    typedef struct SQLitePool {
        SQLiteDb* writer;
        SQLiteDb** readers;
        bool* readerBusy;
        int readerCount;
        char* fileName;
#ifndef __EMSCRIPTEN__
#ifdef _WIN32
        CRITICAL_SECTION lock;
#else
        pthread_mutex_t lock;
#endif
#endif
    } SQLitePool;

    DLL_EXPORT SQLitePool* CreatePool(const char* fileName, int readerCount);
    DLL_EXPORT SQLiteDb* PoolGetWriter(SQLitePool* pool);
    DLL_EXPORT SQLiteDb* PoolAcquireReader(SQLitePool* pool);
    DLL_EXPORT void PoolReleaseReader(SQLitePool* pool, SQLiteDb* reader);
    DLL_EXPORT void ClosePool(SQLitePool* pool);

#ifdef __cplusplus
}
#endif
