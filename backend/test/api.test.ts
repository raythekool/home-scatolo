import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { createApp } from '../src/app.js';
import { InventoryDatabase } from '../src/db.js';
import type { VisionProvider } from '../src/vision/providers.js';

async function startTestServer(options?: {
    apiToken?: string;
    providers?: VisionProvider[];
    publicWebDir?: string | null;
}): Promise<{ baseUrl: string; close: () => Promise<void> }> {
    const db = new InventoryDatabase(':memory:');
    const app = createApp({
        db,
        environment: {
            APP_API_TOKEN: options?.apiToken,
        },
        providers: options?.providers ?? [],
        publicWebDir: options?.publicWebDir ?? null,
    });

    const server: Server = createServer(app);
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address() as AddressInfo;

    return {
        baseUrl: `http://127.0.0.1:${address.port}`,
        close: async () => {
            await new Promise<void>((resolve, reject) => {
                server.close((err) => (err ? reject(err) : resolve()));
            });
            db.close();
        },
    };
}

test('enforces APP_API_TOKEN on /api and /recognize while keeping /livez and /health accessible', async () => {
    const fakeProvider: VisionProvider = {
        name: 'ollama',
        async recognize() {
            return {
                items: [
                    {
                        name: 'Chiave inglese',
                        category: 'Attrezzi',
                        shortDescription: 'Acciaio',
                        quantity: 1,
                        confidence: 0.9,
                    },
                ],
            };
        },
    };

    const server = await startTestServer({
        apiToken: 'super-secret-house-token',
        providers: [fakeProvider],
    });
    try {
        const livez = await fetch(`${server.baseUrl}/livez`);
        assert.equal(livez.status, 200);

        const health = await fetch(`${server.baseUrl}/health`);
        assert.equal(health.status, 200);
        const healthBody = (await health.json()) as {
            status: string;
            authEnabled: boolean;
            recognition: { providers: string[] };
        };
        assert.equal(healthBody.status, 'ok');
        assert.equal(healthBody.authEnabled, true);
        assert.deepEqual(healthBody.recognition.providers, ['ollama']);

        const unauth = await fetch(`${server.baseUrl}/api/houses`);
        assert.equal(unauth.status, 401);

        const wrong = await fetch(`${server.baseUrl}/api/houses`, {
            headers: { Authorization: 'Bearer wrong-token' },
        });
        assert.equal(wrong.status, 403);

        const byBearer = await fetch(`${server.baseUrl}/api/houses`, {
            headers: { Authorization: 'Bearer super-secret-house-token' },
        });
        assert.equal(byBearer.status, 200);

        const byApiKey = await fetch(`${server.baseUrl}/api/houses`, {
            headers: { 'X-Api-Key': 'super-secret-house-token' },
        });
        assert.equal(byApiKey.status, 200);

        const recognizeRes = await fetch(`${server.baseUrl}/recognize`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: 'Bearer super-secret-house-token',
            },
            body: JSON.stringify({
                imageBase64: Buffer.from('img').toString('base64'),
                mimeType: 'image/jpeg',
                existingItems: [],
            }),
        });
        assert.equal(recognizeRes.status, 200);
        assert.equal(recognizeRes.headers.get('x-vision-provider'), 'ollama');
        assert.equal(recognizeRes.headers.get('x-vision-fallback'), 'false');
    } finally {
        await server.close();
    }
});

test('supports end-to-end inventory REST CRUD, search with path, and export', async () => {
    const server = await startTestServer();
    try {
        const houseRes = await fetch(`${server.baseUrl}/api/houses`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: 'Casa Vaiano' }),
        });
        assert.equal(houseRes.status, 201);
        const house = (await houseRes.json()) as { id: number; name: string };

        const roomRes = await fetch(
            `${server.baseUrl}/api/houses/${house.id}/rooms`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name: 'Ripostiglio' }),
            },
        );
        assert.equal(roomRes.status, 201);
        const room = (await roomRes.json()) as { id: number };

        const containerRes = await fetch(
            `${server.baseUrl}/api/rooms/${room.id}/containers`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name: 'Scatola Rete', type: 'scatolone' }),
            },
        );
        assert.equal(containerRes.status, 201);
        const container = (await containerRes.json()) as { id: number };

        const itemRes = await fetch(
            `${server.baseUrl}/api/containers/${container.id}/items`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    name: 'Switch Gigabit 8 porte',
                    category: 'Elettronica',
                    shortDescription: 'TP-Link metallo',
                    quantity: 1,
                }),
            },
        );
        assert.equal(itemRes.status, 201);
        const item = (await itemRes.json()) as { id: number };

        const incRes = await fetch(
            `${server.baseUrl}/api/items/${item.id}/increment`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ amount: 2 }),
            },
        );
        assert.equal(incRes.status, 200);
        const updatedItem = (await incRes.json()) as { quantity: number };
        assert.equal(updatedItem.quantity, 3);

        const searchRes = await fetch(
            `${server.baseUrl}/api/search?q=${encodeURIComponent('gigabit')}`,
        );
        assert.equal(searchRes.status, 200);
        const searchBody = (await searchRes.json()) as {
            items: Array<{
                name: string;
                houseName: string;
                roomName: string;
                containerName: string;
            }>;
        };
        assert.equal(searchBody.items.length, 1);
        assert.equal(searchBody.items[0]?.houseName, 'Casa Vaiano');
        assert.equal(searchBody.items[0]?.roomName, 'Ripostiglio');
        assert.equal(searchBody.items[0]?.containerName, 'Scatola Rete');

        const statePut = await fetch(`${server.baseUrl}/api/state/activeHouseId`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ value: String(house.id) }),
        });
        assert.equal(statePut.status, 200);

        const stateGet = await fetch(`${server.baseUrl}/api/state/activeHouseId`);
        assert.deepEqual(await stateGet.json(), {
            key: 'activeHouseId',
            value: String(house.id),
        });

        const exportRes = await fetch(`${server.baseUrl}/api/export`);
        assert.equal(exportRes.status, 200);
        const exported = (await exportRes.json()) as {
            houses: unknown[];
            items: unknown[];
        };
        assert.equal(exported.houses.length, 1);
        assert.equal(exported.items.length, 1);
    } finally {
        await server.close();
    }
});

test('serves static PWA files with SPA fallback when publicWebDir is configured', async () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'home-scatolo-web-'));
    writeFileSync(join(tempDir, 'index.html'), '<!doctype html><title>Home Scatolo</title>');
    const server = await startTestServer({ publicWebDir: tempDir });
    try {
        const res = await fetch(`${server.baseUrl}/rooms?houseId=1`);
        assert.equal(res.status, 200);
        const html = await res.text();
        assert.match(html, /Home Scatolo/);
    } finally {
        await server.close();
        rmSync(tempDir, { recursive: true, force: true });
    }
});
