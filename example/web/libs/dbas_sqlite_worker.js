'use strict';

importScripts('dbas_sqlite.js');

let wrapper = null;
const pools = new Map();

self.onmessage = async function (e) {
    const { id, method, args } = e.data;
    try {
        const result = await handleMessage(method, args || {});
        self.postMessage({ id, result });
    } catch (error) {
        self.postMessage({ id, error: error.message || String(error) });
    }
};

async function handleMessage(method, args) {
    switch (method) {
        // ── Lifecycle ──
        case 'initialize':
            wrapper = await initPersistentFS(args.dbName);
            return true;

        case 'databaseExists':
            return wrapper.databaseExists();

        case 'openDb':
            return wrapper.openDb();

        case 'isOpened':
            return wrapper.isOpened(args.dbPtr) === 1;

        case 'closeDb':
            wrapper.closeDb(args.dbPtr);
            return true;

        // ── Execute SQL (fire-and-forget style) ──
        case 'executeSql': {
            const rc = wrapper.executeSql(args.dbPtr, args.sql);
            return {
                rc,
                affectedRows: wrapper.getAffectedRows(args.dbPtr),
                lastInsertedId: wrapper.getLastInsertedId(args.dbPtr),
                lastError: wrapper.getLastDbError(args.dbPtr),
            };
        }

        // ── Prepare Query ──
        case 'prepareQuery': {
            const rc = wrapper.prepareQuery(args.dbPtr, args.sql);
            let columnCount = 0;
            const columnNames = [];
            if (rc === 0) {
                columnCount = wrapper.getColumnCount(args.dbPtr);
                for (let i = 0; i < columnCount; i++) {
                    columnNames.push(wrapper.getColumnName(args.dbPtr, i));
                }
            }
            return {
                rc,
                columnCount,
                columnNames,
                lastError: wrapper.getLastDbError(args.dbPtr),
            };
        }

        // ── Read Row (with buffered binds) ──
        case 'readRow': {
            if (args.binds && args.binds.length > 0) {
                for (const bind of args.binds) {
                    const bindRc = applyBind(args.dbPtr, bind);
                    if (bindRc !== 0) {
                        return {
                            status: -1,
                            columns: null,
                            columnCount: 0,
                            affectedRows: 0,
                            lastInsertedId: 0,
                            lastError: wrapper.getLastDbError(args.dbPtr),
                            bindError: true,
                        };
                    }
                }
            }

            const status = wrapper.readRow(args.dbPtr);
            let columns = null;
            let columnCount = wrapper.getColumnCount(args.dbPtr);

            if (status === 100) {
                columns = [];
                for (let i = 0; i < columnCount; i++) {
                    const type = wrapper.getColumnType(args.dbPtr, i);
                    const isNull = wrapper.isNull(args.dbPtr, i) === 1;
                    let value = null;
                    if (!isNull) {
                        switch (type) {
                            case 1: value = wrapper.getColumnInt(args.dbPtr, i); break;
                            case 2: value = wrapper.getColumnDouble(args.dbPtr, i); break;
                            case 4: {
                                const blob = wrapper.getColumnBlob(args.dbPtr, i);
                                value = blob ? Array.from(blob) : null;
                                break;
                            }
                            default: value = wrapper.getColumnText(args.dbPtr, i); break;
                        }
                    }
                    columns.push({ type, isNull, value });
                }
            }

            return {
                status,
                columns,
                columnCount,
                affectedRows: wrapper.getAffectedRows(args.dbPtr),
                lastInsertedId: wrapper.getLastInsertedId(args.dbPtr),
                lastError: wrapper.getLastDbError(args.dbPtr),
            };
        }

        // ── Reader Management ──
        case 'closeReader':
            wrapper.closeReader(args.dbPtr);
            return true;

        // ── File Operations ──
        case 'attachDb':
            wrapper.attachDb(new Uint8Array(args.content));
            return true;

        case 'streamCopyDb':
            await wrapper.streamCopyDb(args.destName);
            return true;

        case 'dropDb':
            await wrapper.dropDb();
            return true;

        case 'getContent': {
            const data = wrapper.module.FS.readFile(wrapper.dbPath);
            return Array.from(data);
        }

        // ── Connection Pool ──
        case 'createPool': {
            const pool = wrapper.createPool(args.size);
            pools.set(pool.poolPtr, pool);
            return { poolPtr: pool.poolPtr, writerPtr: pool.writer };
        }

        case 'closePool': {
            const pool = pools.get(args.poolPtr);
            if (pool) {
                pool.close();
                pools.delete(args.poolPtr);
            }
            return true;
        }

        default:
            throw new Error('Unknown method: ' + method);
    }
}

function applyBind(dbPtr, bind) {
    switch (bind.method) {
        case 'bindNull': return wrapper.bindNull(dbPtr, bind.index);
        case 'bindInt': return wrapper.bindInt(dbPtr, bind.index, bind.value);
        case 'bindFloat': return wrapper.bindFloat(dbPtr, bind.index, bind.value);
        case 'bindDouble': return wrapper.bindDouble(dbPtr, bind.index, bind.value);
        case 'bindText': return wrapper.bindText(dbPtr, bind.index, bind.value);
        case 'bindBlob': return wrapper.bindBlob(dbPtr, bind.index, new Uint8Array(bind.value));
        case 'bindNameNull': return wrapper.bindNameNull(dbPtr, bind.name);
        case 'bindNameInt': return wrapper.bindNameInt(dbPtr, bind.name, bind.value);
        case 'bindNameFloat': return wrapper.bindNameFloat(dbPtr, bind.name, bind.value);
        case 'bindNameDouble': return wrapper.bindNameDouble(dbPtr, bind.name, bind.value);
        case 'bindNameText': return wrapper.bindNameText(dbPtr, bind.name, bind.value);
        case 'bindNameBlob': return wrapper.bindNameBlob(dbPtr, bind.name, new Uint8Array(bind.value));
        default: return 0;
    }
}
