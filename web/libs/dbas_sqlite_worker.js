'use strict';

importScripts('dbas_sqlite.js');

const wrappers = new Map();
const streamStates = new Map();
const dbPtrs = new Map();
const closedDbs = new Set();

function getWrapper(dbName) {
    const w = wrappers.get(dbName);
    if (!w) throw new Error('DB not initialized: ' + dbName);
    return w;
}

function getStreamState(dbName) {
    return streamStates.get(dbName) || { handle: null, offset: 0 };
}

function setStreamState(dbName, state) {
    streamStates.set(dbName, state);
}

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
        case 'initDb': {
            // Re-init if wrapper doesn't exist OR if the DB was closed
            // (stale wrapper with freed SQLite handle needs replacement).
            if (!wrappers.has(args.dbName) || closedDbs.has(args.dbName)) {
                const w = await initPersistentFS(args.dbName);
                wrappers.set(args.dbName, w);
                closedDbs.delete(args.dbName);
            }
            return true;
        }

        case 'databaseExists':
            return getWrapper(args.dbName).databaseExists();

        case 'openDb': {
            const w = getWrapper(args.dbName);
            const ptr = w.openDb();
            dbPtrs.set(args.dbName, ptr);
            return ptr;
        }

        case 'isOpened':
            return getWrapper(args.dbName).isOpened(args.dbPtr) === 1;

        case 'closeDb': {
            const w = getWrapper(args.dbName);
            w.closeDb(args.dbPtr);
            dbPtrs.delete(args.dbName);
            closedDbs.add(args.dbName);
            return true;
        }

        // Full cleanup: close DB + destroy wrapper so next initDb creates fresh module
        case 'deinitDb': {
            const ptr = dbPtrs.get(args.dbName);
            if (ptr) {
                try { wrappers.get(args.dbName)?.closeDb(ptr); } catch (e) {
                    console.warn('deinitDb: closeDb failed for ' + args.dbName + ':', e.message);
                }
                dbPtrs.delete(args.dbName);
            }
            wrappers.delete(args.dbName);
            streamStates.delete(args.dbName);
            closedDbs.delete(args.dbName);
            return true;
        }

        // ── Execute SQL (fire-and-forget style) ──
        case 'executeSql': {
            const w = getWrapper(args.dbName);
            const rc = w.executeSql(args.dbPtr, args.sql);
            return {
                rc,
                affectedRows: w.getAffectedRows(args.dbPtr),
                lastInsertedId: w.getLastInsertedId(args.dbPtr),
                lastError: w.getLastDbError(args.dbPtr),
            };
        }

        // ── Prepare Query ──
        case 'prepareQuery': {
            const w = getWrapper(args.dbName);
            const rc = w.prepareQuery(args.dbPtr, args.sql);
            let columnCount = 0;
            const columnNames = [];
            if (rc === 0) {
                columnCount = w.getColumnCount(args.dbPtr);
                for (let i = 0; i < columnCount; i++) {
                    columnNames.push(w.getColumnName(args.dbPtr, i));
                }
            }
            return {
                rc,
                columnCount,
                columnNames,
                lastError: w.getLastDbError(args.dbPtr),
            };
        }

        // ── Read Row (with buffered binds) ──
        case 'readRow': {
            const w = getWrapper(args.dbName);
            if (args.binds && args.binds.length > 0) {
                for (const bind of args.binds) {
                    const bindRc = applyBind(w, args.dbPtr, bind);
                    if (bindRc !== 0) {
                        return {
                            status: -1,
                            columns: null,
                            columnCount: 0,
                            affectedRows: 0,
                            lastInsertedId: 0,
                            lastError: w.getLastDbError(args.dbPtr),
                            bindError: true,
                        };
                    }
                }
            }

            const status = w.readRow(args.dbPtr);
            let columns = null;
            let columnCount = w.getColumnCount(args.dbPtr);

            if (status === 100) {
                columns = [];
                for (let i = 0; i < columnCount; i++) {
                    const type = w.getColumnType(args.dbPtr, i);
                    const isNull = w.isNull(args.dbPtr, i) === 1;
                    let value = null;
                    if (!isNull) {
                        switch (type) {
                            case 1: value = w.getColumnInt(args.dbPtr, i); break;
                            case 2: value = w.getColumnDouble(args.dbPtr, i); break;
                            case 4: {
                                const blob = w.getColumnBlob(args.dbPtr, i);
                                value = blob ? Array.from(blob) : null;
                                break;
                            }
                            default: value = w.getColumnText(args.dbPtr, i); break;
                        }
                    }
                    columns.push({ type, isNull, value });
                }
            }

            return {
                status,
                columns,
                columnCount,
                affectedRows: w.getAffectedRows(args.dbPtr),
                lastInsertedId: w.getLastInsertedId(args.dbPtr),
                lastError: w.getLastDbError(args.dbPtr),
            };
        }

        // ── Reader Management ──
        case 'closeReader':
            getWrapper(args.dbName).closeReader(args.dbPtr);
            return true;

        // ── File Operations ──
        case 'attachDb':
            getWrapper(args.dbName).attachDb(new Uint8Array(args.content));
            return true;

        // ── Streamed attach (begin/chunk/end protocol) ──
        case 'beginStreamAttach': {
            const w = getWrapper(args.dbName);
            const ss = getStreamState(args.dbName);
            if (ss.handle !== null) {
                console.warn('beginStreamAttach: closing stale stream handle for ' + args.dbName);
                try { w.module.FS.close(ss.handle); } catch (closeErr) {
                    console.warn('beginStreamAttach: failed to close stale handle:', closeErr.message);
                }
            }
            setStreamState(args.dbName, {
                handle: w.module.FS.open(w.dbPath, 'w+'),
                offset: 0
            });
            return true;
        }

        case 'streamAttachChunk': {
            const w = getWrapper(args.dbName);
            const ss = getStreamState(args.dbName);
            if (ss.handle === null) throw new Error('No active stream attach for ' + args.dbName + '. Call beginStreamAttach first.');
            const data = new Uint8Array(args.bytes);
            const written = w.module.FS.write(ss.handle, data, 0, data.length, ss.offset);
            if (written !== data.length) {
                throw new Error('streamAttachChunk: short write (' + written + ' of ' + data.length + ' bytes at offset ' + ss.offset + ')');
            }
            ss.offset += data.length;
            setStreamState(args.dbName, ss);
            return true;
        }

        case 'endStreamAttach': {
            const w = getWrapper(args.dbName);
            const ss = getStreamState(args.dbName);
            if (ss.handle === null) throw new Error('No active stream attach for ' + args.dbName + '. Call beginStreamAttach first.');
            try {
                w.module.FS.close(ss.handle);
            } finally {
                setStreamState(args.dbName, { handle: null, offset: 0 });
            }
            return true;
        }

        case 'abortStreamAttach': {
            const w = getWrapper(args.dbName);
            const ss = getStreamState(args.dbName);
            const errors = [];
            if (ss.handle !== null) {
                try { w.module.FS.close(ss.handle); } catch (closeErr) { errors.push('close: ' + closeErr.message); }
                setStreamState(args.dbName, { handle: null, offset: 0 });
                try { w.module.FS.unlink(w.dbPath); } catch (unlinkErr) { errors.push('unlink: ' + unlinkErr.message); }
            }
            if (errors.length > 0) {
                console.warn('abortStreamAttach cleanup issues:', errors.join('; '));
            }
            return true;
        }

        case 'streamCopyDb':
            await getWrapper(args.dbName).streamCopyDb(args.destName);
            return true;

        case 'dropDb':
            await getWrapper(args.dbName).dropDb();
            return true;

        case 'getContent': {
            const w = getWrapper(args.dbName);
            const data = w.module.FS.readFile(w.dbPath);
            return Array.from(data);
        }

        default:
            throw new Error('Unknown method: ' + method);
    }
}

function applyBind(w, dbPtr, bind) {
    switch (bind.method) {
        case 'bindNull': return w.bindNull(dbPtr, bind.index);
        case 'bindInt': return w.bindInt(dbPtr, bind.index, bind.value);
        case 'bindFloat': return w.bindFloat(dbPtr, bind.index, bind.value);
        case 'bindDouble': return w.bindDouble(dbPtr, bind.index, bind.value);
        case 'bindText': return w.bindText(dbPtr, bind.index, bind.value);
        case 'bindBlob': return w.bindBlob(dbPtr, bind.index, new Uint8Array(bind.value));
        case 'bindNameNull': return w.bindNameNull(dbPtr, bind.name);
        case 'bindNameInt': return w.bindNameInt(dbPtr, bind.name, bind.value);
        case 'bindNameFloat': return w.bindNameFloat(dbPtr, bind.name, bind.value);
        case 'bindNameDouble': return w.bindNameDouble(dbPtr, bind.name, bind.value);
        case 'bindNameText': return w.bindNameText(dbPtr, bind.name, bind.value);
        case 'bindNameBlob': return w.bindNameBlob(dbPtr, bind.name, new Uint8Array(bind.value));
        default: throw new Error('Unknown bind method: ' + bind.method);
    }
}
