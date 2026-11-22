import { createHash, randomBytes } from 'node:crypto';
import { mkdirSync, statSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export const CONTAINER_TYPES = [
    'armadio',
    'scatolone',
    'libreria',
    'cassetto',
] as const;

export type ContainerType = (typeof CONTAINER_TYPES)[number];

export interface HouseRecord {
    id: number;
    name: string;
    createdAt: string;
    updatedAt: string;
}

export interface RoomRecord {
    id: number;
    name: string;
    houseId: number;
    createdAt: string;
    updatedAt: string;
}

export interface ContainerRecord {
    id: number;
    name: string;
    type: ContainerType;
    roomId: number;
    notes: string;
    createdAt: string;
    updatedAt: string;
}

export interface ItemRecord {
    id: number;
    name: string;
    category: string;
    shortDescription: string;
    notes: string;
    photoPath: string | null;
    containerId: number;
    insertedAt: string;
    updatedAt: string;
    quantity: number;
}

export interface EnrichedItemRecord extends ItemRecord {
    containerName: string;
    containerType: ContainerType;
    roomId: number;
    roomName: string;
    houseId: number;
    houseName: string;
}

export interface QuickScanDestination {
    houseId: number;
    roomId: number;
    containerId: number;
}

export interface InventoryExport {
    version: number;
    exportedAt: string;
    houses: HouseRecord[];
    rooms: RoomRecord[];
    containers: ContainerRecord[];
    items: ItemRecord[];
    state: Record<string, string>;
}

export interface InventoryStats {
    houses: number;
    rooms: number;
    containers: number;
    distinctItems: number;
    totalQuantity: number;
    dbSizeBytes: number;
    dbPath: string;
}

export interface ScanLogRecord {
    id: number;
    createdAt: string;
    provider: string;
    usedFallback: boolean;
    latencyMs: number;
    itemsCount: number;
    status: 'ok' | 'error';
    errorCode: string | null;
}

export type ApiTokenScope = 'read' | 'write';

export interface ApiTokenRecord {
    id: number;
    name: string;
    prefix: string;
    scope: ApiTokenScope;
    createdAt: string;
    lastUsedAt: string | null;
}

export interface CreatedApiToken extends ApiTokenRecord {
    token: string;
}

export interface TreeContainer extends ContainerRecord {
    itemCount: number;
    totalQuantity: number;
}

export interface TreeRoom extends RoomRecord {
    containers: TreeContainer[];
}

export interface TreeHouse extends HouseRecord {
    rooms: TreeRoom[];
}

export interface ImportSummary {
    dryRun: boolean;
    housesAdded: number;
    roomsAdded: number;
    containersAdded: number;
    itemsAdded: number;
}

export class InventoryNotFoundError extends Error {}
export class InventoryValidationError extends Error {}

const containerTypeSet = new Set<string>(CONTAINER_TYPES);

export function isContainerType(value: unknown): value is ContainerType {
    return typeof value === 'string' && containerTypeSet.has(value);
}

export class InventoryDatabase {
    private readonly db: DatabaseSync;
    private readonly dbPath: string;

    constructor(dbPath: string = ':memory:') {
        this.dbPath = dbPath;
        if (dbPath !== ':memory:') {
            mkdirSync(dirname(dbPath), { recursive: true });
        }

        this.db = new DatabaseSync(dbPath);
        if (dbPath !== ':memory:') {
            this.db.exec('PRAGMA journal_mode = WAL;');
        }
        this.db.exec('PRAGMA foreign_keys = ON;');
        this.db.exec('PRAGMA busy_timeout = 5000;');
        this.initializeSchema();
    }

    private initializeSchema(): void {
        this.db.exec(`
            CREATE TABLE IF NOT EXISTS houses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS rooms (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                house_id INTEGER NOT NULL REFERENCES houses(id) ON DELETE CASCADE,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_rooms_house_id ON rooms(house_id);

            CREATE TABLE IF NOT EXISTS containers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL CHECK(type IN ('armadio', 'scatolone', 'libreria', 'cassetto')),
                room_id INTEGER NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
                notes TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_containers_room_id ON containers(room_id);

            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                short_description TEXT NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                photo_path TEXT,
                container_id INTEGER NOT NULL REFERENCES containers(id) ON DELETE CASCADE,
                inserted_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                quantity INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0)
            );

            CREATE INDEX IF NOT EXISTS idx_items_container_id ON items(container_id);
            CREATE INDEX IF NOT EXISTS idx_items_category ON items(category);

            CREATE TABLE IF NOT EXISTS app_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS scan_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL,
                provider TEXT NOT NULL,
                used_fallback INTEGER NOT NULL DEFAULT 0,
                latency_ms INTEGER NOT NULL DEFAULT 0,
                items_count INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL CHECK(status IN ('ok', 'error')),
                error_code TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_scan_logs_created_at ON scan_logs(created_at DESC);

            CREATE TABLE IF NOT EXISTS api_tokens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                prefix TEXT NOT NULL,
                token_hash TEXT NOT NULL UNIQUE,
                scope TEXT NOT NULL CHECK(scope IN ('read', 'write')),
                created_at TEXT NOT NULL,
                last_used_at TEXT
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
                name,
                category,
                short_description,
                notes,
                content='items',
                content_rowid='id',
                tokenize='unicode61 remove_diacritics 2'
            );

            CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
                INSERT INTO items_fts(rowid, name, category, short_description, notes)
                VALUES (new.id, new.name, new.category, new.short_description, new.notes);
            END;

            CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
                INSERT INTO items_fts(items_fts, rowid, name, category, short_description, notes)
                VALUES ('delete', old.id, old.name, old.category, old.short_description, old.notes);
            END;

            CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
                INSERT INTO items_fts(items_fts, rowid, name, category, short_description, notes)
                VALUES ('delete', old.id, old.name, old.category, old.short_description, old.notes);
                INSERT INTO items_fts(rowid, name, category, short_description, notes)
                VALUES (new.id, new.name, new.category, new.short_description, new.notes);
            END;
        `);
    }

    ping(): boolean {
        const row = this.db.prepare('SELECT 1 AS ok').get() as { ok?: number } | undefined;
        return row?.ok === 1;
    }

    close(): void {
        this.db.close();
    }

    // ---- Houses ----

    listHouses(): HouseRecord[] {
        const rows = this.db
            .prepare('SELECT id, name, created_at, updated_at FROM houses ORDER BY id ASC')
            .all() as unknown as RawHouseRow[];
        return rows.map(mapHouseRow);
    }

    getHouse(id: number): HouseRecord | null {
        const row = this.db
            .prepare('SELECT id, name, created_at, updated_at FROM houses WHERE id = ?')
            .get(id) as RawHouseRow | undefined;
        return row ? mapHouseRow(row) : null;
    }

    createHouse(name: string): HouseRecord {
        const cleanName = requireNonEmptyString(name, 'name');
        const now = new Date().toISOString();
        const result = this.db
            .prepare('INSERT INTO houses (name, created_at, updated_at) VALUES (?, ?, ?)')
            .run(cleanName, now, now);
        return {
            id: Number(result.lastInsertRowid),
            name: cleanName,
            createdAt: now,
            updatedAt: now,
        };
    }

    updateHouse(id: number, input: { name: string }): HouseRecord {
        const existing = this.getHouse(id);
        if (!existing) {
            throw new InventoryNotFoundError(`House ${id} not found.`);
        }
        const cleanName = requireNonEmptyString(input.name, 'name');
        const now = new Date().toISOString();
        this.db
            .prepare('UPDATE houses SET name = ?, updated_at = ? WHERE id = ?')
            .run(cleanName, now, id);
        return { ...existing, name: cleanName, updatedAt: now };
    }

    deleteHouse(id: number): void {
        const result = this.db.prepare('DELETE FROM houses WHERE id = ?').run(id);
        if (result.changes === 0) {
            throw new InventoryNotFoundError(`House ${id} not found.`);
        }
    }

    // ---- Rooms ----

    listRooms(houseId?: number): RoomRecord[] {
        const rows = (
            houseId === undefined
                ? this.db
                      .prepare(
                          'SELECT id, name, house_id, created_at, updated_at FROM rooms ORDER BY id ASC',
                      )
                      .all()
                : this.db
                      .prepare(
                          'SELECT id, name, house_id, created_at, updated_at FROM rooms WHERE house_id = ? ORDER BY id ASC',
                      )
                      .all(houseId)
        ) as unknown as RawRoomRow[];
        return rows.map(mapRoomRow);
    }

    getRoom(id: number): RoomRecord | null {
        const row = this.db
            .prepare(
                'SELECT id, name, house_id, created_at, updated_at FROM rooms WHERE id = ?',
            )
            .get(id) as RawRoomRow | undefined;
        return row ? mapRoomRow(row) : null;
    }

    createRoom(input: { name: string; houseId: number }): RoomRecord {
        const cleanName = requireNonEmptyString(input.name, 'name');
        if (!this.getHouse(input.houseId)) {
            throw new InventoryNotFoundError(`House ${input.houseId} not found.`);
        }
        const now = new Date().toISOString();
        const result = this.db
            .prepare(
                'INSERT INTO rooms (name, house_id, created_at, updated_at) VALUES (?, ?, ?, ?)',
            )
            .run(cleanName, input.houseId, now, now);
        return {
            id: Number(result.lastInsertRowid),
            name: cleanName,
            houseId: input.houseId,
            createdAt: now,
            updatedAt: now,
        };
    }

    updateRoom(id: number, input: { name?: string; houseId?: number }): RoomRecord {
        const existing = this.getRoom(id);
        if (!existing) {
            throw new InventoryNotFoundError(`Room ${id} not found.`);
        }
        const name =
            input.name !== undefined
                ? requireNonEmptyString(input.name, 'name')
                : existing.name;
        const houseId = input.houseId ?? existing.houseId;
        if (houseId !== existing.houseId && !this.getHouse(houseId)) {
            throw new InventoryNotFoundError(`House ${houseId} not found.`);
        }
        const now = new Date().toISOString();
        this.db
            .prepare('UPDATE rooms SET name = ?, house_id = ?, updated_at = ? WHERE id = ?')
            .run(name, houseId, now, id);
        return { ...existing, name, houseId, updatedAt: now };
    }

    deleteRoom(id: number): void {
        const result = this.db.prepare('DELETE FROM rooms WHERE id = ?').run(id);
        if (result.changes === 0) {
            throw new InventoryNotFoundError(`Room ${id} not found.`);
        }
    }

    // ---- Containers ----

    listContainers(roomId?: number): ContainerRecord[] {
        const rows = (
            roomId === undefined
                ? this.db
                      .prepare(
                          'SELECT id, name, type, room_id, notes, created_at, updated_at FROM containers ORDER BY id ASC',
                      )
                      .all()
                : this.db
                      .prepare(
                          'SELECT id, name, type, room_id, notes, created_at, updated_at FROM containers WHERE room_id = ? ORDER BY id ASC',
                      )
                      .all(roomId)
        ) as unknown as RawContainerRow[];
        return rows.map(mapContainerRow);
    }

    getContainer(id: number): ContainerRecord | null {
        const row = this.db
            .prepare(
                'SELECT id, name, type, room_id, notes, created_at, updated_at FROM containers WHERE id = ?',
            )
            .get(id) as RawContainerRow | undefined;
        return row ? mapContainerRow(row) : null;
    }

    createContainer(input: {
        name: string;
        type: ContainerType;
        roomId: number;
        notes?: string;
    }): ContainerRecord {
        const cleanName = requireNonEmptyString(input.name, 'name');
        if (!isContainerType(input.type)) {
            throw new InventoryValidationError(
                `type must be one of: ${CONTAINER_TYPES.join(', ')}.`,
            );
        }
        if (!this.getRoom(input.roomId)) {
            throw new InventoryNotFoundError(`Room ${input.roomId} not found.`);
        }
        const notes = (input.notes ?? '').trim();
        const now = new Date().toISOString();
        const result = this.db
            .prepare(
                'INSERT INTO containers (name, type, room_id, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
            )
            .run(cleanName, input.type, input.roomId, notes, now, now);
        return {
            id: Number(result.lastInsertRowid),
            name: cleanName,
            type: input.type,
            roomId: input.roomId,
            notes,
            createdAt: now,
            updatedAt: now,
        };
    }

    updateContainer(
        id: number,
        input: { name?: string; type?: ContainerType; roomId?: number; notes?: string },
    ): ContainerRecord {
        const existing = this.getContainer(id);
        if (!existing) {
            throw new InventoryNotFoundError(`Container ${id} not found.`);
        }
        const name =
            input.name !== undefined
                ? requireNonEmptyString(input.name, 'name')
                : existing.name;
        const type = input.type ?? existing.type;
        if (!isContainerType(type)) {
            throw new InventoryValidationError(
                `type must be one of: ${CONTAINER_TYPES.join(', ')}.`,
            );
        }
        const roomId = input.roomId ?? existing.roomId;
        if (roomId !== existing.roomId && !this.getRoom(roomId)) {
            throw new InventoryNotFoundError(`Room ${roomId} not found.`);
        }
        const notes = input.notes !== undefined ? input.notes.trim() : existing.notes;
        const now = new Date().toISOString();
        this.db
            .prepare(
                'UPDATE containers SET name = ?, type = ?, room_id = ?, notes = ?, updated_at = ? WHERE id = ?',
            )
            .run(name, type, roomId, notes, now, id);
        return { ...existing, name, type, roomId, notes, updatedAt: now };
    }

    deleteContainer(id: number): void {
        const result = this.db.prepare('DELETE FROM containers WHERE id = ?').run(id);
        if (result.changes === 0) {
            throw new InventoryNotFoundError(`Container ${id} not found.`);
        }
    }

    getOrCreateQuickScanContainer(): QuickScanDestination {
        return this.withTransaction(() => {
            const now = new Date().toISOString();
            const firstHouse = this.db
                .prepare('SELECT id FROM houses ORDER BY id ASC LIMIT 1')
                .get() as { id: number } | undefined;

            let houseId: number;
            if (!firstHouse) {
                const insertedHouse = this.db
                    .prepare('INSERT INTO houses (name, created_at, updated_at) VALUES (?, ?, ?)')
                    .run('La mia casa', now, now);
                houseId = Number(insertedHouse.lastInsertRowid);
                this.db
                    .prepare(
                        'INSERT INTO app_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
                    )
                    .run('activeHouseId', String(houseId));
            } else {
                houseId = Number(firstHouse.id);
            }

            const firstRoom = this.db
                .prepare('SELECT id FROM rooms WHERE house_id = ? ORDER BY id ASC LIMIT 1')
                .get(houseId) as { id: number } | undefined;

            const roomId = firstRoom
                ? Number(firstRoom.id)
                : Number(
                      this.db
                          .prepare(
                              'INSERT INTO rooms (name, house_id, created_at, updated_at) VALUES (?, ?, ?, ?)',
                          )
                          .run('Ingresso', houseId, now, now).lastInsertRowid,
                  );

            const firstContainer = this.db
                .prepare('SELECT id FROM containers WHERE room_id = ? ORDER BY id ASC LIMIT 1')
                .get(roomId) as { id: number } | undefined;

            const containerId = firstContainer
                ? Number(firstContainer.id)
                : Number(
                      this.db
                          .prepare(
                              'INSERT INTO containers (name, type, room_id, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
                          )
                          .run('Da ordinare', 'scatolone', roomId, '', now, now).lastInsertRowid,
                  );

            return { houseId, roomId, containerId };
        });
    }

    // ---- Items ----

    listItems(containerId?: number): ItemRecord[] {
        const rows = (
            containerId === undefined
                ? this.db
                      .prepare(
                          `SELECT id, name, category, short_description, notes, photo_path, container_id, inserted_at, updated_at, quantity
                           FROM items
                           ORDER BY inserted_at DESC, id DESC`,
                      )
                      .all()
                : this.db
                      .prepare(
                          `SELECT id, name, category, short_description, notes, photo_path, container_id, inserted_at, updated_at, quantity
                           FROM items
                           WHERE container_id = ?
                           ORDER BY inserted_at DESC, id DESC`,
                      )
                      .all(containerId)
        ) as unknown as RawItemRow[];
        return rows.map(mapItemRow);
    }

    getItem(id: number): EnrichedItemRecord | null {
        const row = this.db
            .prepare(
                `SELECT
                    i.id, i.name, i.category, i.short_description, i.notes, i.photo_path,
                    i.container_id, i.inserted_at, i.updated_at, i.quantity,
                    c.name AS container_name, c.type AS container_type,
                    r.id AS room_id, r.name AS room_name,
                    h.id AS house_id, h.name AS house_name
                 FROM items i
                 JOIN containers c ON c.id = i.container_id
                 JOIN rooms r ON r.id = c.room_id
                 JOIN houses h ON h.id = r.house_id
                 WHERE i.id = ?`,
            )
            .get(id) as RawEnrichedItemRow | undefined;
        return row ? mapEnrichedItemRow(row) : null;
    }

    createItem(input: {
        name: string;
        category: string;
        shortDescription: string;
        notes?: string;
        photoPath?: string | null;
        containerId: number;
        insertedAt?: string;
        quantity?: number;
    }): ItemRecord {
        const name = requireNonEmptyString(input.name, 'name');
        const category = requireNonEmptyString(input.category, 'category');
        const shortDescription = (input.shortDescription ?? '').trim();
        const notes = (input.notes ?? '').trim();
        const quantity = input.quantity ?? 1;
        if (!Number.isInteger(quantity) || quantity <= 0) {
            throw new InventoryValidationError('quantity must be a positive integer.');
        }
        if (!this.getContainer(input.containerId)) {
            throw new InventoryNotFoundError(`Container ${input.containerId} not found.`);
        }
        const now = new Date().toISOString();
        const insertedAt = input.insertedAt ?? now;
        const photoPath = input.photoPath ?? null;

        const result = this.db
            .prepare(
                `INSERT INTO items
                    (name, category, short_description, notes, photo_path, container_id, inserted_at, updated_at, quantity)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            )
            .run(
                name,
                category,
                shortDescription,
                notes,
                photoPath,
                input.containerId,
                insertedAt,
                now,
                quantity,
            );

        return {
            id: Number(result.lastInsertRowid),
            name,
            category,
            shortDescription,
            notes,
            photoPath,
            containerId: input.containerId,
            insertedAt,
            updatedAt: now,
            quantity,
        };
    }

    updateItem(
        id: number,
        input: {
            name?: string;
            category?: string;
            shortDescription?: string;
            notes?: string;
            photoPath?: string | null;
            containerId?: number;
            quantity?: number;
        },
    ): EnrichedItemRecord {
        const existing = this.getItem(id);
        if (!existing) {
            throw new InventoryNotFoundError(`Item ${id} not found.`);
        }
        const name =
            input.name !== undefined
                ? requireNonEmptyString(input.name, 'name')
                : existing.name;
        const category =
            input.category !== undefined
                ? requireNonEmptyString(input.category, 'category')
                : existing.category;
        const shortDescription =
            input.shortDescription !== undefined
                ? input.shortDescription.trim()
                : existing.shortDescription;
        const notes = input.notes !== undefined ? input.notes.trim() : existing.notes;
        const photoPath =
            input.photoPath !== undefined ? input.photoPath : existing.photoPath;
        const containerId = input.containerId ?? existing.containerId;
        if (containerId !== existing.containerId && !this.getContainer(containerId)) {
            throw new InventoryNotFoundError(`Container ${containerId} not found.`);
        }
        const quantity = input.quantity ?? existing.quantity;
        if (!Number.isInteger(quantity) || quantity <= 0) {
            throw new InventoryValidationError('quantity must be a positive integer.');
        }

        const now = new Date().toISOString();
        this.db
            .prepare(
                `UPDATE items
                 SET name = ?, category = ?, short_description = ?, notes = ?, photo_path = ?,
                     container_id = ?, quantity = ?, updated_at = ?
                 WHERE id = ?`,
            )
            .run(
                name,
                category,
                shortDescription,
                notes,
                photoPath,
                containerId,
                quantity,
                now,
                id,
            );

        const updated = this.getItem(id);
        if (!updated) {
            throw new InventoryNotFoundError(`Item ${id} not found.`);
        }
        return updated;
    }

    incrementItemQuantity(id: number, amount: number): EnrichedItemRecord {
        if (!Number.isInteger(amount) || amount <= 0) {
            throw new InventoryValidationError('amount must be a positive integer.');
        }
        const now = new Date().toISOString();
        const result = this.db
            .prepare(
                'UPDATE items SET quantity = quantity + ?, updated_at = ? WHERE id = ?',
            )
            .run(amount, now, id);
        if (result.changes === 0) {
            throw new InventoryNotFoundError(`Item ${id} not found.`);
        }
        const updated = this.getItem(id);
        if (!updated) {
            throw new InventoryNotFoundError(`Item ${id} not found.`);
        }
        return updated;
    }

    deleteItem(id: number): void {
        const result = this.db.prepare('DELETE FROM items WHERE id = ?').run(id);
        if (result.changes === 0) {
            throw new InventoryNotFoundError(`Item ${id} not found.`);
        }
    }

    // ---- Search ----

    searchItems(options: {
        q?: string;
        houseId?: number;
        category?: string;
    }): EnrichedItemRecord[] {
        const query = (options.q ?? '').trim();
        const category = options.category?.trim();
        const houseId = options.houseId;

        if (query.length === 0 && !category && houseId === undefined) {
            return [];
        }

        const whereClauses: string[] = [];
        const params: Array<string | number> = [];

        if (query.length > 0) {
            const ftsQuery = buildFtsPrefixQuery(query);
            const likePattern = `%${query.toLowerCase()}%`;
            if (ftsQuery) {
                whereClauses.push(`(
                    i.id IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)
                    OR lower(i.name) LIKE ?
                    OR lower(i.category) LIKE ?
                    OR lower(i.short_description) LIKE ?
                    OR lower(i.notes) LIKE ?
                    OR lower(c.name) LIKE ?
                    OR lower(r.name) LIKE ?
                )`);
                params.push(
                    ftsQuery,
                    likePattern,
                    likePattern,
                    likePattern,
                    likePattern,
                    likePattern,
                    likePattern,
                );
            } else {
                whereClauses.push(`(
                    lower(i.name) LIKE ?
                    OR lower(i.category) LIKE ?
                    OR lower(i.short_description) LIKE ?
                    OR lower(i.notes) LIKE ?
                    OR lower(c.name) LIKE ?
                    OR lower(r.name) LIKE ?
                )`);
                params.push(
                    likePattern,
                    likePattern,
                    likePattern,
                    likePattern,
                    likePattern,
                    likePattern,
                );
            }
        }

        if (houseId !== undefined) {
            whereClauses.push('h.id = ?');
            params.push(houseId);
        }

        if (category) {
            whereClauses.push('lower(i.category) = ?');
            params.push(category.toLowerCase());
        }

        const whereSql =
            whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';

        const rows = this.db
            .prepare(
                `SELECT
                    i.id, i.name, i.category, i.short_description, i.notes, i.photo_path,
                    i.container_id, i.inserted_at, i.updated_at, i.quantity,
                    c.name AS container_name, c.type AS container_type,
                    r.id AS room_id, r.name AS room_name,
                    h.id AS house_id, h.name AS house_name
                 FROM items i
                 JOIN containers c ON c.id = i.container_id
                 JOIN rooms r ON r.id = c.room_id
                 JOIN houses h ON h.id = r.house_id
                 ${whereSql}
                 ORDER BY i.inserted_at DESC, i.id DESC`,
            )
            .all(...params) as unknown as RawEnrichedItemRow[];

        return rows.map(mapEnrichedItemRow);
    }

    // ---- App State & Export ----

    getState(key: string): string | null {
        const cleanKey = requireNonEmptyString(key, 'key');
        const row = this.db
            .prepare('SELECT value FROM app_state WHERE key = ?')
            .get(cleanKey) as { value: string } | undefined;
        return row ? row.value : null;
    }

    setState(key: string, value: string): void {
        const cleanKey = requireNonEmptyString(key, 'key');
        this.db
            .prepare(
                'INSERT INTO app_state (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
            )
            .run(cleanKey, value);
    }

    exportAll(): InventoryExport {
        const stateRows = this.db
            .prepare('SELECT key, value FROM app_state ORDER BY key ASC')
            .all() as Array<{ key: string; value: string }>;
        const state: Record<string, string> = {};
        for (const row of stateRows) {
            state[row.key] = row.value;
        }
        return {
            version: 1,
            exportedAt: new Date().toISOString(),
            houses: this.listHouses(),
            rooms: this.listRooms(),
            containers: this.listContainers(),
            items: this.listItems(),
            state,
        };
    }

    // ---- Admin: Stats, Tree, Settings, Logs, Tokens, Maintenance ----

    listEnrichedItems(): EnrichedItemRecord[] {
        const rows = this.db
            .prepare(
                `SELECT
                    i.id, i.name, i.category, i.short_description, i.notes, i.photo_path,
                    i.container_id, i.inserted_at, i.updated_at, i.quantity,
                    c.name AS container_name, c.type AS container_type,
                    r.id AS room_id, r.name AS room_name,
                    h.id AS house_id, h.name AS house_name
                 FROM items i
                 JOIN containers c ON c.id = i.container_id
                 JOIN rooms r ON r.id = c.room_id
                 JOIN houses h ON h.id = r.house_id
                 ORDER BY i.inserted_at DESC, i.id DESC`,
            )
            .all() as unknown as RawEnrichedItemRow[];
        return rows.map(mapEnrichedItemRow);
    }

    getStats(): InventoryStats {
        const counts = this.db
            .prepare(
                `SELECT
                    (SELECT COUNT(*) FROM houses) AS houses,
                    (SELECT COUNT(*) FROM rooms) AS rooms,
                    (SELECT COUNT(*) FROM containers) AS containers,
                    (SELECT COUNT(*) FROM items) AS distinct_items,
                    (SELECT COALESCE(SUM(quantity), 0) FROM items) AS total_quantity`,
            )
            .get() as {
            houses: number;
            rooms: number;
            containers: number;
            distinct_items: number;
            total_quantity: number;
        };

        let dbSizeBytes = 0;
        if (this.dbPath !== ':memory:') {
            try {
                dbSizeBytes = statSync(this.dbPath).size;
            } catch {
                dbSizeBytes = 0;
            }
        }

        return {
            houses: Number(counts.houses),
            rooms: Number(counts.rooms),
            containers: Number(counts.containers),
            distinctItems: Number(counts.distinct_items),
            totalQuantity: Number(counts.total_quantity),
            dbSizeBytes,
            dbPath: this.dbPath,
        };
    }

    getTree(): TreeHouse[] {
        const houses = this.listHouses();
        const rooms = this.listRooms();
        const containers = this.listContainers();
        const itemAggs = this.db
            .prepare(
                `SELECT container_id, COUNT(*) AS item_count, COALESCE(SUM(quantity), 0) AS total_quantity
                 FROM items
                 GROUP BY container_id`,
            )
            .all() as Array<{
            container_id: number;
            item_count: number;
            total_quantity: number;
        }>;

        const aggByContainer = new Map<
            number,
            { itemCount: number; totalQuantity: number }
        >();
        for (const row of itemAggs) {
            aggByContainer.set(Number(row.container_id), {
                itemCount: Number(row.item_count),
                totalQuantity: Number(row.total_quantity),
            });
        }

        const containersByRoom = new Map<number, TreeContainer[]>();
        for (const container of containers) {
            const agg = aggByContainer.get(container.id) ?? {
                itemCount: 0,
                totalQuantity: 0,
            };
            const list = containersByRoom.get(container.roomId) ?? [];
            list.push({ ...container, ...agg });
            containersByRoom.set(container.roomId, list);
        }

        const roomsByHouse = new Map<number, TreeRoom[]>();
        for (const room of rooms) {
            const list = roomsByHouse.get(room.houseId) ?? [];
            list.push({
                ...room,
                containers: containersByRoom.get(room.id) ?? [],
            });
            roomsByHouse.set(room.houseId, list);
        }

        return houses.map((house) => ({
            ...house,
            rooms: roomsByHouse.get(house.id) ?? [],
        }));
    }

    getSettings(): Record<string, string> {
        const rows = this.db
            .prepare('SELECT key, value FROM app_settings ORDER BY key ASC')
            .all() as Array<{ key: string; value: string }>;
        const settings: Record<string, string> = {};
        for (const row of rows) {
            settings[row.key] = row.value;
        }
        return settings;
    }

    setSetting(key: string, value: string): void {
        const cleanKey = requireNonEmptyString(key, 'key');
        const now = new Date().toISOString();
        this.db
            .prepare(
                `INSERT INTO app_settings (key, value, updated_at)
                 VALUES (?, ?, ?)
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
            )
            .run(cleanKey, value, now);
    }

    deleteSetting(key: string): void {
        const cleanKey = requireNonEmptyString(key, 'key');
        this.db.prepare('DELETE FROM app_settings WHERE key = ?').run(cleanKey);
    }

    logScan(entry: {
        provider: string;
        usedFallback: boolean;
        latencyMs: number;
        itemsCount: number;
        status: 'ok' | 'error';
        errorCode?: string | null;
    }): ScanLogRecord {
        const now = new Date().toISOString();
        const latencyMs = Math.max(0, Math.round(entry.latencyMs));
        const itemsCount = Math.max(0, Math.round(entry.itemsCount));
        const errorCode = entry.errorCode ?? null;
        const result = this.db
            .prepare(
                `INSERT INTO scan_logs
                    (created_at, provider, used_fallback, latency_ms, items_count, status, error_code)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
            )
            .run(
                now,
                entry.provider,
                entry.usedFallback ? 1 : 0,
                latencyMs,
                itemsCount,
                entry.status,
                errorCode,
            );

        // Keep at most the most recent 200 scan logs to keep the DB tidy
        this.db.exec(
            'DELETE FROM scan_logs WHERE id NOT IN (SELECT id FROM scan_logs ORDER BY id DESC LIMIT 200)',
        );

        return {
            id: Number(result.lastInsertRowid),
            createdAt: now,
            provider: entry.provider,
            usedFallback: entry.usedFallback,
            latencyMs,
            itemsCount,
            status: entry.status,
            errorCode,
        };
    }

    listScanLogs(limit: number = 50): ScanLogRecord[] {
        const safeLimit = Math.min(200, Math.max(1, Math.floor(limit)));
        const rows = this.db
            .prepare(
                `SELECT id, created_at, provider, used_fallback, latency_ms, items_count, status, error_code
                 FROM scan_logs
                 ORDER BY id DESC
                 LIMIT ?`,
            )
            .all(safeLimit) as Array<{
            id: number;
            created_at: string;
            provider: string;
            used_fallback: number;
            latency_ms: number;
            items_count: number;
            status: 'ok' | 'error';
            error_code: string | null;
        }>;
        return rows.map((row) => ({
            id: Number(row.id),
            createdAt: row.created_at,
            provider: row.provider,
            usedFallback: Boolean(row.used_fallback),
            latencyMs: Number(row.latency_ms),
            itemsCount: Number(row.items_count),
            status: row.status,
            errorCode: row.error_code,
        }));
    }

    createApiToken(input: {
        name: string;
        scope: ApiTokenScope;
    }): CreatedApiToken {
        const cleanName = requireNonEmptyString(input.name, 'name');
        if (input.scope !== 'read' && input.scope !== 'write') {
            throw new InventoryValidationError('scope must be "read" or "write".');
        }
        const rawToken = `hs_${randomBytes(24).toString('hex')}`;
        const prefix = rawToken.slice(0, 11);
        const tokenHash = createHash('sha256').update(rawToken, 'utf8').digest('hex');
        const now = new Date().toISOString();

        const result = this.db
            .prepare(
                `INSERT INTO api_tokens (name, prefix, token_hash, scope, created_at, last_used_at)
                 VALUES (?, ?, ?, ?, ?, NULL)`,
            )
            .run(cleanName, prefix, tokenHash, input.scope, now);

        return {
            id: Number(result.lastInsertRowid),
            name: cleanName,
            prefix,
            scope: input.scope,
            createdAt: now,
            lastUsedAt: null,
            token: rawToken,
        };
    }

    listApiTokens(): ApiTokenRecord[] {
        const rows = this.db
            .prepare(
                'SELECT id, name, prefix, scope, created_at, last_used_at FROM api_tokens ORDER BY id DESC',
            )
            .all() as Array<{
            id: number;
            name: string;
            prefix: string;
            scope: ApiTokenScope;
            created_at: string;
            last_used_at: string | null;
        }>;
        return rows.map((row) => ({
            id: Number(row.id),
            name: row.name,
            prefix: row.prefix,
            scope: row.scope,
            createdAt: row.created_at,
            lastUsedAt: row.last_used_at,
        }));
    }

    revokeApiToken(id: number): void {
        const result = this.db.prepare('DELETE FROM api_tokens WHERE id = ?').run(id);
        if (result.changes === 0) {
            throw new InventoryNotFoundError(`Token ${id} not found.`);
        }
    }

    verifyApiToken(rawToken: string): ApiTokenRecord | null {
        const tokenHash = createHash('sha256').update(rawToken, 'utf8').digest('hex');
        const row = this.db
            .prepare(
                'SELECT id, name, prefix, scope, created_at, last_used_at FROM api_tokens WHERE token_hash = ?',
            )
            .get(tokenHash) as
            | {
                  id: number;
                  name: string;
                  prefix: string;
                  scope: ApiTokenScope;
                  created_at: string;
                  last_used_at: string | null;
              }
            | undefined;
        if (!row) {
            return null;
        }
        const now = new Date().toISOString();
        this.db
            .prepare('UPDATE api_tokens SET last_used_at = ? WHERE id = ?')
            .run(now, row.id);
        return {
            id: Number(row.id),
            name: row.name,
            prefix: row.prefix,
            scope: row.scope,
            createdAt: row.created_at,
            lastUsedAt: now,
        };
    }

    importInventory(
        payload: unknown,
        options: { dryRun?: boolean } = {},
    ): ImportSummary {
        if (typeof payload !== 'object' || payload === null) {
            throw new InventoryValidationError('Import payload must be a JSON object.');
        }
        const raw = payload as Record<string, unknown>;
        const houses = Array.isArray(raw.houses) ? raw.houses : [];
        const rooms = Array.isArray(raw.rooms) ? raw.rooms : [];
        const containers = Array.isArray(raw.containers) ? raw.containers : [];
        const items = Array.isArray(raw.items) ? raw.items : [];

        const validatedHouses: Array<{ oldId: number; name: string }> = [];
        const houseIds = new Set<number>();
        for (let idx = 0; idx < houses.length; idx++) {
            const entry = houses[idx];
            if (typeof entry !== 'object' || entry === null) {
                throw new InventoryValidationError(`houses[${idx}] must be an object.`);
            }
            const record = entry as Record<string, unknown>;
            const oldId = requireStrictPositiveInt(record.id, `houses[${idx}].id`);
            if (houseIds.has(oldId)) {
                throw new InventoryValidationError(`houses[${idx}].id (${oldId}) is duplicated.`);
            }
            if (typeof record.name !== 'string') {
                throw new InventoryValidationError(`houses[${idx}].name must be a string.`);
            }
            const name = requireNonEmptyString(record.name, `houses[${idx}].name`);
            houseIds.add(oldId);
            validatedHouses.push({ oldId, name });
        }

        const validatedRooms: Array<{ oldId: number; name: string; oldHouseId: number }> = [];
        const roomIds = new Set<number>();
        for (let idx = 0; idx < rooms.length; idx++) {
            const entry = rooms[idx];
            if (typeof entry !== 'object' || entry === null) {
                throw new InventoryValidationError(`rooms[${idx}] must be an object.`);
            }
            const record = entry as Record<string, unknown>;
            const oldId = requireStrictPositiveInt(record.id, `rooms[${idx}].id`);
            if (roomIds.has(oldId)) {
                throw new InventoryValidationError(`rooms[${idx}].id (${oldId}) is duplicated.`);
            }
            const houseId = requireStrictPositiveInt(
                record.houseId,
                `rooms[${idx}].houseId`,
            );
            if (!houseIds.has(houseId)) {
                throw new InventoryValidationError(
                    `rooms[${idx}].houseId (${houseId}) references unknown house.`,
                );
            }
            if (typeof record.name !== 'string') {
                throw new InventoryValidationError(`rooms[${idx}].name must be a string.`);
            }
            const name = requireNonEmptyString(record.name, `rooms[${idx}].name`);
            roomIds.add(oldId);
            validatedRooms.push({ oldId, name, oldHouseId: houseId });
        }

        const validatedContainers: Array<{
            oldId: number;
            name: string;
            type: ContainerType;
            oldRoomId: number;
            notes: string;
        }> = [];
        const containerIds = new Set<number>();
        for (let idx = 0; idx < containers.length; idx++) {
            const entry = containers[idx];
            if (typeof entry !== 'object' || entry === null) {
                throw new InventoryValidationError(
                    `containers[${idx}] must be an object.`,
                );
            }
            const record = entry as Record<string, unknown>;
            const oldId = requireStrictPositiveInt(
                record.id,
                `containers[${idx}].id`,
            );
            if (containerIds.has(oldId)) {
                throw new InventoryValidationError(
                    `containers[${idx}].id (${oldId}) is duplicated.`,
                );
            }
            const roomId = requireStrictPositiveInt(
                record.roomId,
                `containers[${idx}].roomId`,
            );
            if (!roomIds.has(roomId)) {
                throw new InventoryValidationError(
                    `containers[${idx}].roomId (${roomId}) references unknown room.`,
                );
            }
            if (typeof record.name !== 'string') {
                throw new InventoryValidationError(
                    `containers[${idx}].name must be a string.`,
                );
            }
            const name = requireNonEmptyString(record.name, `containers[${idx}].name`);
            const type = record.type;
            if (!isContainerType(type)) {
                throw new InventoryValidationError(
                    `containers[${idx}].type is invalid.`,
                );
            }
            const notes = typeof record.notes === 'string' ? record.notes : '';
            containerIds.add(oldId);
            validatedContainers.push({ oldId, name, type, oldRoomId: roomId, notes });
        }

        const validatedItems = items.map((entry, idx) => {
            if (typeof entry !== 'object' || entry === null) {
                throw new InventoryValidationError(`items[${idx}] must be an object.`);
            }
            const record = entry as Record<string, unknown>;
            const containerId = requireStrictPositiveInt(
                record.containerId,
                `items[${idx}].containerId`,
            );
            if (!containerIds.has(containerId)) {
                throw new InventoryValidationError(
                    `items[${idx}].containerId (${containerId}) references unknown container.`,
                );
            }
            if (typeof record.name !== 'string') {
                throw new InventoryValidationError(`items[${idx}].name must be a string.`);
            }
            if (typeof record.category !== 'string') {
                throw new InventoryValidationError(
                    `items[${idx}].category must be a string.`,
                );
            }
            const name = requireNonEmptyString(record.name, `items[${idx}].name`);
            const category = requireNonEmptyString(
                record.category,
                `items[${idx}].category`,
            );
            const quantity =
                record.quantity === undefined
                    ? 1
                    : requireStrictPositiveInt(record.quantity, `items[${idx}].quantity`);
            return {
                name,
                category,
                shortDescription:
                    typeof record.shortDescription === 'string'
                        ? record.shortDescription
                        : '',
                notes: typeof record.notes === 'string' ? record.notes : '',
                photoPath:
                    typeof record.photoPath === 'string' ? record.photoPath : null,
                oldContainerId: containerId,
                insertedAt:
                    typeof record.insertedAt === 'string'
                        ? record.insertedAt
                        : new Date().toISOString(),
                quantity,
            };
        });

        if (options.dryRun) {
            return {
                dryRun: true,
                housesAdded: validatedHouses.length,
                roomsAdded: validatedRooms.length,
                containersAdded: validatedContainers.length,
                itemsAdded: validatedItems.length,
            };
        }

        return this.withTransaction(() => {
            const houseMap = new Map<number, number>();
            for (const h of validatedHouses) {
                const created = this.createHouse(h.name);
                houseMap.set(h.oldId, created.id);
            }

            const roomMap = new Map<number, number>();
            for (const r of validatedRooms) {
                const created = this.createRoom({
                    name: r.name,
                    houseId: houseMap.get(r.oldHouseId)!,
                });
                roomMap.set(r.oldId, created.id);
            }

            const containerMap = new Map<number, number>();
            for (const c of validatedContainers) {
                const created = this.createContainer({
                    name: c.name,
                    type: c.type,
                    roomId: roomMap.get(c.oldRoomId)!,
                    notes: c.notes,
                });
                containerMap.set(c.oldId, created.id);
            }

            for (const item of validatedItems) {
                this.createItem({
                    name: item.name,
                    category: item.category,
                    shortDescription: item.shortDescription,
                    notes: item.notes,
                    photoPath: item.photoPath,
                    containerId: containerMap.get(item.oldContainerId)!,
                    insertedAt: item.insertedAt,
                    quantity: item.quantity,
                });
            }

            return {
                dryRun: false,
                housesAdded: validatedHouses.length,
                roomsAdded: validatedRooms.length,
                containersAdded: validatedContainers.length,
                itemsAdded: validatedItems.length,
            };
        });
    }

    checkIntegrity(): { ok: boolean; messages: string[] } {
        const rows = this.db.prepare('PRAGMA integrity_check').all() as Array<{
            integrity_check: string;
        }>;
        const messages = rows.map((row) => String(row.integrity_check));
        return {
            ok: messages.length === 1 && messages[0] === 'ok',
            messages,
        };
    }

    rebuildFts(): void {
        this.db.exec("INSERT INTO items_fts(items_fts) VALUES('rebuild');");
    }

    createBackupFile(targetPath: string): void {
        const escaped = targetPath.replace(/'/g, "''");
        this.db.exec(`VACUUM INTO '${escaped}'`);
    }

    private withTransaction<T>(fn: () => T): T {
        this.db.exec('BEGIN IMMEDIATE');
        try {
            const value = fn();
            this.db.exec('COMMIT');
            return value;
        } catch (error) {
            this.db.exec('ROLLBACK');
            throw error;
        }
    }
}

interface RawHouseRow {
    id: number;
    name: string;
    created_at: string;
    updated_at: string;
}

interface RawRoomRow {
    id: number;
    name: string;
    house_id: number;
    created_at: string;
    updated_at: string;
}

interface RawContainerRow {
    id: number;
    name: string;
    type: ContainerType;
    room_id: number;
    notes: string;
    created_at: string;
    updated_at: string;
}

interface RawItemRow {
    id: number;
    name: string;
    category: string;
    short_description: string;
    notes: string;
    photo_path: string | null;
    container_id: number;
    inserted_at: string;
    updated_at: string;
    quantity: number;
}

interface RawEnrichedItemRow extends RawItemRow {
    container_name: string;
    container_type: ContainerType;
    room_id: number;
    room_name: string;
    house_id: number;
    house_name: string;
}

function mapHouseRow(row: RawHouseRow): HouseRecord {
    return {
        id: Number(row.id),
        name: row.name,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    };
}

function mapRoomRow(row: RawRoomRow): RoomRecord {
    return {
        id: Number(row.id),
        name: row.name,
        houseId: Number(row.house_id),
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    };
}

function mapContainerRow(row: RawContainerRow): ContainerRecord {
    return {
        id: Number(row.id),
        name: row.name,
        type: row.type,
        roomId: Number(row.room_id),
        notes: row.notes,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    };
}

function mapItemRow(row: RawItemRow): ItemRecord {
    return {
        id: Number(row.id),
        name: row.name,
        category: row.category,
        shortDescription: row.short_description,
        notes: row.notes,
        photoPath: row.photo_path,
        containerId: Number(row.container_id),
        insertedAt: row.inserted_at,
        updatedAt: row.updated_at,
        quantity: Number(row.quantity),
    };
}

function mapEnrichedItemRow(row: RawEnrichedItemRow): EnrichedItemRecord {
    return {
        ...mapItemRow(row),
        containerName: row.container_name,
        containerType: row.container_type,
        roomId: Number(row.room_id),
        roomName: row.room_name,
        houseId: Number(row.house_id),
        houseName: row.house_name,
    };
}

function requireNonEmptyString(value: string, fieldName: string): string {
    const trimmed = typeof value === 'string' ? value.trim() : '';
    if (trimmed.length === 0) {
        throw new InventoryValidationError(`${fieldName} must be a non-empty string.`);
    }
    return trimmed;
}

function requireStrictPositiveInt(value: unknown, fieldName: string): number {
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || value <= 0) {
        throw new InventoryValidationError(`${fieldName} must be a positive integer.`);
    }
    return value;
}

function buildFtsPrefixQuery(query: string): string | null {
    const tokens = query
        .split(/\s+/)
        .map((token) => token.replace(/[^\p{L}\p{N}_-]+/gu, ''))
        .filter((token) => token.length > 0);
    if (tokens.length === 0) {
        return null;
    }
    return tokens.map((token) => `"${token}"*`).join(' AND ');
}
