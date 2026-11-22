import { Router, type Request, type Response } from 'express';

import {
    InventoryDatabase,
    InventoryNotFoundError,
    InventoryValidationError,
    isContainerType,
    type ContainerType,
} from '../db.js';

export function createInventoryRouter(db: InventoryDatabase): Router {
    const router = Router();

    // ---- Houses ----

    router.get('/houses', (_request: Request, response: Response) => {
        response.json({ houses: db.listHouses() });
    });

    router.post('/houses', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const body = requireObject(request.body);
            const name = requireStringField(body, 'name');
            const created = db.createHouse(name);
            response.status(201).json(created);
        });
    });

    router.patch('/houses/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            const body = requireObject(request.body);
            const name = requireStringField(body, 'name');
            response.json(db.updateHouse(id, { name }));
        });
    });

    router.delete('/houses/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            db.deleteHouse(id);
            response.status(204).end();
        });
    });

    // ---- Rooms ----

    router.get('/houses/:houseId/rooms', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const houseId = parsePositiveId(request.params.houseId, 'houseId');
            response.json({ rooms: db.listRooms(houseId) });
        });
    });

    router.post('/houses/:houseId/rooms', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const houseId = parsePositiveId(request.params.houseId, 'houseId');
            const body = requireObject(request.body);
            const name = requireStringField(body, 'name');
            response.status(201).json(db.createRoom({ name, houseId }));
        });
    });

    router.get('/rooms', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const houseId = parseOptionalPositiveId(request.query.houseId, 'houseId');
            response.json({ rooms: db.listRooms(houseId) });
        });
    });

    router.post('/rooms', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const body = requireObject(request.body);
            const name = requireStringField(body, 'name');
            const houseId = requirePositiveIntField(body, 'houseId');
            response.status(201).json(db.createRoom({ name, houseId }));
        });
    });

    router.patch('/rooms/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            const body = requireObject(request.body);
            const name = optionalStringField(body, 'name');
            const houseId = optionalPositiveIntField(body, 'houseId');
            response.json(db.updateRoom(id, { name, houseId }));
        });
    });

    router.delete('/rooms/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            db.deleteRoom(id);
            response.status(204).end();
        });
    });

    // ---- Containers ----

    router.get('/rooms/:roomId/containers', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const roomId = parsePositiveId(request.params.roomId, 'roomId');
            response.json({ containers: db.listContainers(roomId) });
        });
    });

    router.post('/rooms/:roomId/containers', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const roomId = parsePositiveId(request.params.roomId, 'roomId');
            const body = requireObject(request.body);
            const name = requireStringField(body, 'name');
            const type = requireContainerTypeField(body, 'type');
            const notes = optionalStringField(body, 'notes');
            response.status(201).json(db.createContainer({ name, type, roomId, notes }));
        });
    });

    router.get('/containers', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const roomId = parseOptionalPositiveId(request.query.roomId, 'roomId');
            response.json({ containers: db.listContainers(roomId) });
        });
    });

    router.post('/containers', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const body = requireObject(request.body);
            const name = requireStringField(body, 'name');
            const type = requireContainerTypeField(body, 'type');
            const roomId = requirePositiveIntField(body, 'roomId');
            const notes = optionalStringField(body, 'notes');
            response.status(201).json(db.createContainer({ name, type, roomId, notes }));
        });
    });

    router.patch('/containers/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            const body = requireObject(request.body);
            const name = optionalStringField(body, 'name');
            const type = optionalContainerTypeField(body, 'type');
            const roomId = optionalPositiveIntField(body, 'roomId');
            const notes = optionalStringField(body, 'notes');
            response.json(db.updateContainer(id, { name, type, roomId, notes }));
        });
    });

    router.delete('/containers/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            db.deleteContainer(id);
            response.status(204).end();
        });
    });

    router.post('/quick-scan-container', (_request: Request, response: Response) => {
        handleRoute(response, () => {
            response.json(db.getOrCreateQuickScanContainer());
        });
    });

    // ---- Items ----

    router.get('/containers/:containerId/items', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const containerId = parsePositiveId(request.params.containerId, 'containerId');
            response.json({ items: db.listItems(containerId) });
        });
    });

    router.post('/containers/:containerId/items', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const containerId = parsePositiveId(request.params.containerId, 'containerId');
            const body = requireObject(request.body);
            const created = db.createItem({
                name: requireStringField(body, 'name'),
                category: requireStringField(body, 'category'),
                shortDescription: optionalStringField(body, 'shortDescription') ?? '',
                notes: optionalStringField(body, 'notes'),
                photoPath: optionalNullableStringField(body, 'photoPath'),
                containerId,
                insertedAt: optionalStringField(body, 'insertedAt'),
                quantity: optionalPositiveIntField(body, 'quantity') ?? 1,
            });
            response.status(201).json(created);
        });
    });

    router.get('/items', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const containerId = parseOptionalPositiveId(
                request.query.containerId,
                'containerId',
            );
            response.json({ items: db.listItems(containerId) });
        });
    });

    router.get('/items/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            const item = db.getItem(id);
            if (!item) {
                throw new InventoryNotFoundError(`Item ${id} not found.`);
            }
            response.json(item);
        });
    });

    router.post('/items', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const body = requireObject(request.body);
            const created = db.createItem({
                name: requireStringField(body, 'name'),
                category: requireStringField(body, 'category'),
                shortDescription: optionalStringField(body, 'shortDescription') ?? '',
                notes: optionalStringField(body, 'notes'),
                photoPath: optionalNullableStringField(body, 'photoPath'),
                containerId: requirePositiveIntField(body, 'containerId'),
                insertedAt: optionalStringField(body, 'insertedAt'),
                quantity: optionalPositiveIntField(body, 'quantity') ?? 1,
            });
            response.status(201).json(created);
        });
    });

    router.patch('/items/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            const body = requireObject(request.body);
            const updated = db.updateItem(id, {
                name: optionalStringField(body, 'name'),
                category: optionalStringField(body, 'category'),
                shortDescription: optionalStringField(body, 'shortDescription'),
                notes: optionalStringField(body, 'notes'),
                photoPath: optionalNullableStringField(body, 'photoPath'),
                containerId: optionalPositiveIntField(body, 'containerId'),
                quantity: optionalPositiveIntField(body, 'quantity'),
            });
            response.json(updated);
        });
    });

    router.post('/items/:id/increment', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            const body = requireObject(request.body);
            const amount = requirePositiveIntField(body, 'amount');
            response.json(db.incrementItemQuantity(id, amount));
        });
    });

    router.delete('/items/:id', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const id = parsePositiveId(request.params.id, 'id');
            db.deleteItem(id);
            response.status(204).end();
        });
    });

    // ---- Search ----

    router.get('/search', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const q = typeof request.query.q === 'string' ? request.query.q : undefined;
            const category =
                typeof request.query.category === 'string'
                    ? request.query.category
                    : undefined;
            const houseId = parseOptionalPositiveId(request.query.houseId, 'houseId');
            response.json({
                items: db.searchItems({ q, houseId, category }),
            });
        });
    });

    // ---- State & Export ----

    router.get('/state/:key', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const key = requireParamString(request.params.key, 'key');
            response.json({ key, value: db.getState(key) });
        });
    });

    router.put('/state/:key', (request: Request, response: Response) => {
        handleRoute(response, () => {
            const key = requireParamString(request.params.key, 'key');
            const body = requireObject(request.body);
            const value = body.value;
            if (typeof value !== 'string') {
                throw new InventoryValidationError('value must be a string.');
            }
            db.setState(key, value);
            response.json({ key, value });
        });
    });

    router.get('/export', (_request: Request, response: Response) => {
        response.json(db.exportAll());
    });

    return router;
}

function handleRoute(response: Response, action: () => void): void {
    try {
        action();
    } catch (error) {
        if (error instanceof InventoryValidationError) {
            response.status(400).json({ error: error.message });
            return;
        }
        if (error instanceof InventoryNotFoundError) {
            response.status(404).json({ error: error.message });
            return;
        }
        response.status(500).json({ error: 'Internal server error.' });
    }
}

function requireObject(value: unknown): Record<string, unknown> {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        throw new InventoryValidationError('Request body must be a JSON object.');
    }
    return value as Record<string, unknown>;
}

function requireParamString(value: string | string[] | undefined, field: string): string {
    const raw = Array.isArray(value) ? value[0] : value;
    if (typeof raw !== 'string' || raw.trim().length === 0) {
        throw new InventoryValidationError(`${field} must be a non-empty string.`);
    }
    return raw.trim();
}

function parsePositiveId(value: string | string[] | undefined, field: string): number {
    const raw = Array.isArray(value) ? value[0] : value;
    if (typeof raw !== 'string' || !/^\d+$/.test(raw)) {
        throw new InventoryValidationError(`${field} must be a positive integer.`);
    }
    const parsed = Number.parseInt(raw, 10);
    if (!Number.isSafeInteger(parsed) || parsed <= 0) {
        throw new InventoryValidationError(`${field} must be a positive integer.`);
    }
    return parsed;
}

function parseOptionalPositiveId(
    value: unknown,
    field: string,
): number | undefined {
    if (value === undefined || value === '') {
        return undefined;
    }
    if (typeof value !== 'string') {
        throw new InventoryValidationError(`${field} must be a positive integer.`);
    }
    return parsePositiveId(value, field);
}

function requireStringField(body: Record<string, unknown>, field: string): string {
    const value = body[field];
    if (typeof value !== 'string' || value.trim().length === 0) {
        throw new InventoryValidationError(`${field} must be a non-empty string.`);
    }
    return value;
}

function optionalStringField(
    body: Record<string, unknown>,
    field: string,
): string | undefined {
    const value = body[field];
    if (value === undefined) {
        return undefined;
    }
    if (typeof value !== 'string') {
        throw new InventoryValidationError(`${field} must be a string.`);
    }
    return value;
}

function optionalNullableStringField(
    body: Record<string, unknown>,
    field: string,
): string | null | undefined {
    const value = body[field];
    if (value === undefined || value === null) {
        return value;
    }
    if (typeof value !== 'string') {
        throw new InventoryValidationError(`${field} must be a string or null.`);
    }
    return value;
}

function requirePositiveIntField(body: Record<string, unknown>, field: string): number {
    const value = body[field];
    if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
        throw new InventoryValidationError(`${field} must be a positive integer.`);
    }
    return value;
}

function optionalPositiveIntField(
    body: Record<string, unknown>,
    field: string,
): number | undefined {
    const value = body[field];
    if (value === undefined) {
        return undefined;
    }
    if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
        throw new InventoryValidationError(`${field} must be a positive integer.`);
    }
    return value;
}

function requireContainerTypeField(
    body: Record<string, unknown>,
    field: string,
): ContainerType {
    const value = body[field];
    if (!isContainerType(value)) {
        throw new InventoryValidationError(`${field} is not a valid container type.`);
    }
    return value;
}

function optionalContainerTypeField(
    body: Record<string, unknown>,
    field: string,
): ContainerType | undefined {
    const value = body[field];
    if (value === undefined) {
        return undefined;
    }
    if (!isContainerType(value)) {
        throw new InventoryValidationError(`${field} is not a valid container type.`);
    }
    return value;
}
