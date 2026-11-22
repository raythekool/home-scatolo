import assert from 'node:assert/strict';
import { createSign, generateKeyPairSync } from 'node:crypto';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import test from 'node:test';

import { createApp } from '../src/app.js';
import type { CloudflareJwksProvider } from '../src/auth.js';
import { InventoryDatabase } from '../src/db.js';
import type { VisionProvider } from '../src/vision/providers.js';

async function startServer(options: {
    environment?: NodeJS.ProcessEnv;
    providers?: VisionProvider[];
    cloudflareJwks?: CloudflareJwksProvider;
    fetchImpl?: typeof fetch;
}) {
    const db = new InventoryDatabase(':memory:');
    const app = createApp({
        db,
        environment: options.environment ?? {},
        providers: options.providers,
        cloudflareJwks: options.cloudflareJwks,
        fetchImpl: options.fetchImpl,
        publicWebDir: null,
    });
    const server: Server = createServer(app);
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address() as AddressInfo;
    return {
        db,
        baseUrl: `http://127.0.0.1:${address.port}`,
        close: async () => {
            await new Promise<void>((resolve, reject) =>
                server.close((err) => (err ? reject(err) : resolve())),
            );
            db.close();
        },
    };
}

function signRs256Jwt(
    header: Record<string, unknown>,
    payload: Record<string, unknown>,
    privateKeyPem: string,
): string {
    const h = Buffer.from(JSON.stringify(header)).toString('base64url');
    const p = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signer = createSign('RSA-SHA256');
    signer.update(`${h}.${p}`);
    signer.end();
    const sig = signer.sign(privateKeyPem).toString('base64url');
    return `${h}.${p}.${sig}`;
}

test('authenticates admin via password HttpOnly session cookie, rate-limits failures, and supports logout', async () => {
    const srv = await startServer({
        environment: {
            ADMIN_PASSWORD: 'casa-vaiano-password',
            APP_API_TOKEN: 'master-api-token',
        },
    });
    try {
        // Unauthenticated admin access is rejected
        const denied = await fetch(`${srv.baseUrl}/api/admin/overview`);
        assert.equal(denied.status, 401);

        // Wrong password returns 401
        const badLogin = await fetch(`${srv.baseUrl}/api/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ password: 'wrong' }),
        });
        assert.equal(badLogin.status, 401);

        // Correct password returns HttpOnly cookie
        const okLogin = await fetch(`${srv.baseUrl}/api/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ password: 'casa-vaiano-password' }),
        });
        assert.equal(okLogin.status, 200);
        const setCookie = okLogin.headers.get('set-cookie') ?? '';
        assert.match(setCookie, /hs_session=/);
        assert.match(setCookie, /HttpOnly/);
        const cookiePair = setCookie.split(';')[0] ?? '';

        const sessionRes = await fetch(`${srv.baseUrl}/api/auth/session`, {
            headers: { Cookie: cookiePair },
        });
        const session = (await sessionRes.json()) as {
            authenticated: boolean;
            role: string;
            method: string;
        };
        assert.equal(session.authenticated, true);
        assert.equal(session.role, 'admin');
        assert.equal(session.method, 'password');

        const overviewRes = await fetch(`${srv.baseUrl}/api/admin/overview`, {
            headers: { Cookie: cookiePair },
        });
        assert.equal(overviewRes.status, 200);

        // Logout clears cookie
        const logoutRes = await fetch(`${srv.baseUrl}/api/auth/logout`, {
            method: 'POST',
            headers: { Cookie: cookiePair },
        });
        assert.equal(logoutRes.status, 200);
        assert.match(logoutRes.headers.get('set-cookie') ?? '', /Max-Age=0/);
    } finally {
        await srv.close();
    }
});

test('verifies Cloudflare Access RS256 JWT cryptographically and enforces allowed emails', async () => {
    const { publicKey, privateKey } = generateKeyPairSync('rsa', {
        modulusLength: 2048,
    });
    const privatePem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();

    const jwks: CloudflareJwksProvider = {
        async getKey(kid) {
            return kid === 'cf-kid-1' ? publicKey : null;
        },
    };

    const srv = await startServer({
        environment: {
            CF_ACCESS_TEAM_DOMAIN: 'vaiano.cloudflareaccess.com',
            CF_ACCESS_AUD: 'aud-home-scatolo-123',
            AUTH_ALLOWED_EMAILS: 'marco@example.com',
        },
        cloudflareJwks: jwks,
    });
    try {
        const now = Math.floor(Date.now() / 1000);
        const validJwt = signRs256Jwt(
            { alg: 'RS256', kid: 'cf-kid-1', typ: 'JWT' },
            {
                aud: ['aud-home-scatolo-123'],
                iss: 'https://vaiano.cloudflareaccess.com',
                email: 'marco@example.com',
                iat: now - 10,
                exp: now + 3600,
            },
            privatePem,
        );

        const okSession = await fetch(`${srv.baseUrl}/api/auth/session`, {
            headers: { 'Cf-Access-Jwt-Assertion': validJwt },
        });
        const body = (await okSession.json()) as {
            authenticated: boolean;
            method: string;
            subject: string;
        };
        assert.equal(body.authenticated, true);
        assert.equal(body.method, 'cloudflare');
        assert.equal(body.subject, 'marco@example.com');

        const overview = await fetch(`${srv.baseUrl}/api/admin/overview`, {
            headers: { 'Cf-Access-Jwt-Assertion': validJwt },
        });
        assert.equal(overview.status, 200);

        // Unauthorized email signed by same key must be rejected
        const otherEmailJwt = signRs256Jwt(
            { alg: 'RS256', kid: 'cf-kid-1', typ: 'JWT' },
            {
                aud: ['aud-home-scatolo-123'],
                iss: 'https://vaiano.cloudflareaccess.com',
                email: 'intruder@example.com',
                iat: now - 10,
                exp: now + 3600,
            },
            privatePem,
        );
        const rejected = await fetch(`${srv.baseUrl}/api/admin/overview`, {
            headers: { 'Cf-Access-Jwt-Assertion': otherEmailJwt },
        });
        assert.equal(rejected.status, 403);
    } finally {
        await srv.close();
    }
});

test('supports Google OAuth 2.0 login flow with email allowlist', async () => {
    const mockFetch: typeof fetch = async (input) => {
        const url = String(input);
        if (url === 'https://oauth2.googleapis.com/token') {
            return new Response(JSON.stringify({ access_token: 'google-access-1' }), {
                status: 200,
                headers: { 'Content-Type': 'application/json' },
            });
        }
        if (url === 'https://openidconnect.googleapis.com/v1/userinfo') {
            return new Response(
                JSON.stringify({
                    email: 'marco@gmail.com',
                    email_verified: true,
                }),
                { status: 200, headers: { 'Content-Type': 'application/json' } },
            );
        }
        return new Response('unexpected', { status: 500 });
    };

    const srv = await startServer({
        environment: {
            GOOGLE_CLIENT_ID: 'client-id-123',
            GOOGLE_CLIENT_SECRET: 'client-secret-456',
            AUTH_ALLOWED_EMAILS: 'marco@gmail.com',
        },
        fetchImpl: mockFetch,
    });
    try {
        const startRes = await fetch(`${srv.baseUrl}/api/auth/google`, {
            redirect: 'manual',
        });
        assert.equal(startRes.status, 302);
        const location = startRes.headers.get('location') ?? '';
        assert.match(location, /^https:\/\/accounts\.google\.com\/o\/oauth2\/v2\/auth\?/);
        const stateParam = new URL(location).searchParams.get('state');
        assert.ok(stateParam);
        const stateCookie = (startRes.headers.get('set-cookie') ?? '').split(';')[0] ?? '';

        const cbRes = await fetch(
            `${srv.baseUrl}/api/auth/google/callback?code=auth-code-1&state=${encodeURIComponent(stateParam)}`,
            {
                redirect: 'manual',
                headers: { Cookie: stateCookie },
            },
        );
        assert.equal(cbRes.status, 302);
        assert.equal(cbRes.headers.get('location'), '/admin');
        const sessionCookie = (cbRes.headers.get('set-cookie') ?? '').split(';')[0] ?? '';
        assert.match(sessionCookie, /^hs_session=/);

        const sessionRes = await fetch(`${srv.baseUrl}/api/auth/session`, {
            headers: { Cookie: sessionCookie },
        });
        const session = (await sessionRes.json()) as {
            authenticated: boolean;
            method: string;
            subject: string;
        };
        assert.equal(session.authenticated, true);
        assert.equal(session.method, 'google');
        assert.equal(session.subject, 'marco@gmail.com');
    } finally {
        await srv.close();
    }
});

test('enforces scoped read/write API tokens and isolates admin routes', async () => {
    const srv = await startServer({
        environment: { APP_API_TOKEN: 'master-secret' },
    });
    try {
        const createReadRes = await fetch(`${srv.baseUrl}/api/admin/tokens`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: 'Bearer master-secret',
            },
            body: JSON.stringify({ name: 'hermes-agent', scope: 'read' }),
        });
        assert.equal(createReadRes.status, 201);
        const readToken = (await createReadRes.json()) as {
            id: number;
            token: string;
            scope: string;
        };
        assert.equal(readToken.scope, 'read');

        // Read token can GET /api/houses and /api/search
        const getHouses = await fetch(`${srv.baseUrl}/api/houses`, {
            headers: { 'X-Api-Key': readToken.token },
        });
        assert.equal(getHouses.status, 200);

        // Read token CANNOT POST /api/houses or access /api/admin/*
        const postHouse = await fetch(`${srv.baseUrl}/api/houses`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': readToken.token,
            },
            body: JSON.stringify({ name: 'Vietata' }),
        });
        assert.equal(postHouse.status, 403);

        const adminAttempt = await fetch(`${srv.baseUrl}/api/admin/overview`, {
            headers: { 'X-Api-Key': readToken.token },
        });
        assert.equal(adminAttempt.status, 403);

        // Revoking token blocks further access immediately
        const revokeRes = await fetch(
            `${srv.baseUrl}/api/admin/tokens/${readToken.id}`,
            {
                method: 'DELETE',
                headers: { Authorization: 'Bearer master-secret' },
            },
        );
        assert.equal(revokeRes.status, 204);

        const afterRevoke = await fetch(`${srv.baseUrl}/api/houses`, {
            headers: { 'X-Api-Key': readToken.token },
        });
        assert.equal(afterRevoke.status, 403);
    } finally {
        await srv.close();
    }
});

test('serves admin console, Ollama live models, runtime settings, backup SQLite, CSV, import, and scan logs', async () => {
    const fakeProvider: VisionProvider = {
        name: 'ollama',
        async recognize() {
            return {
                items: [
                    {
                        name: 'Cavo USB-C',
                        category: 'Elettronica',
                        shortDescription: 'Bianco 1m',
                        quantity: 2,
                        confidence: 0.91,
                    },
                ],
            };
        },
    };

    const mockFetch: typeof fetch = async (input) => {
        const url = String(input);
        if (url.endsWith('/api/tags')) {
            return new Response(
                JSON.stringify({
                    models: [
                        {
                            name: 'qwen2.5vl:3b',
                            size: 3_200_000_000,
                            modified_at: '2026-11-20T10:00:00Z',
                        },
                    ],
                }),
                { status: 200, headers: { 'Content-Type': 'application/json' } },
            );
        }
        return new Response('not found', { status: 404 });
    };

    const srv = await startServer({
        environment: { OLLAMA_BASE_URL: 'http://ollama.local:11434' },
        providers: [fakeProvider],
        fetchImpl: mockFetch,
    });
    try {
        // Seed one item
        const house = srv.db.createHouse('Casa Vaiano');
        const room = srv.db.createRoom({ name: 'Studio', houseId: house.id });
        const box = srv.db.createContainer({
            name: 'Scatola Cavi',
            type: 'scatolone',
            roomId: room.id,
        });
        srv.db.createItem({
            name: 'Adattatore HDMI',
            category: 'Elettronica',
            shortDescription: 'Mini HDMI',
            containerId: box.id,
            quantity: 2,
        });

        // Admin HTML + assets served with security headers
        const adminHtml = await fetch(`${srv.baseUrl}/admin`);
        assert.equal(adminHtml.status, 200);
        assert.equal(adminHtml.headers.get('x-frame-options'), 'DENY');
        assert.match(await adminHtml.text(), /Home Scatolo Admin/);

        const qrJs = await fetch(`${srv.baseUrl}/admin/qr.js`);
        assert.equal(qrJs.status, 200);

        // Recognize logs scan into scan_logs
        const rec = await fetch(`${srv.baseUrl}/api/recognize`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                imageBase64: Buffer.from('pic').toString('base64'),
                mimeType: 'image/jpeg',
                existingItems: [],
            }),
        });
        assert.equal(rec.status, 200);

        const overviewRes = await fetch(`${srv.baseUrl}/api/admin/overview`);
        const overview = (await overviewRes.json()) as {
            stats: { houses: number; distinctItems: number; totalQuantity: number };
            scanLogs: Array<{ provider: string; itemsCount: number; status: string }>;
        };
        assert.equal(overview.stats.houses, 1);
        assert.equal(overview.stats.distinctItems, 1);
        assert.equal(overview.stats.totalQuantity, 2);
        assert.equal(overview.scanLogs.length, 1);
        assert.equal(overview.scanLogs[0]?.provider, 'ollama');
        assert.equal(overview.scanLogs[0]?.itemsCount, 1);

        // Ollama models discovery
        const ollamaRes = await fetch(`${srv.baseUrl}/api/admin/ollama/models`);
        const ollama = (await ollamaRes.json()) as {
            online: boolean;
            models: Array<{ name: string }>;
        };
        assert.equal(ollama.online, true);
        assert.equal(ollama.models[0]?.name, 'qwen2.5vl:3b');

        // Runtime settings update
        const putSettings = await fetch(`${srv.baseUrl}/api/admin/settings`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                primaryProvider: 'github-models',
                fallbackProvider: 'ollama',
                ollamaModel: 'gemma3:4b',
                cloudTimeoutMs: '25000',
            }),
        });
        assert.equal(putSettings.status, 200);

        // Consistent SQLite backup download
        const backupRes = await fetch(`${srv.baseUrl}/api/admin/backup/sqlite`);
        assert.equal(backupRes.status, 200);
        const backupBuf = Buffer.from(await backupRes.arrayBuffer());
        assert.equal(backupBuf.subarray(0, 15).toString('utf8'), 'SQLite format 3');

        // CSV export
        const csvRes = await fetch(`${srv.baseUrl}/api/admin/export/csv`);
        assert.equal(csvRes.status, 200);
        const csvText = await csvRes.text();
        assert.match(csvText, /Casa Vaiano/);
        assert.match(csvText, /Adattatore HDMI/);

        // JSON export -> import dryRun & apply
        const exported = await (await fetch(`${srv.baseUrl}/api/export`)).json();
        const dryRunRes = await fetch(
            `${srv.baseUrl}/api/admin/import?dryRun=true`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(exported),
            },
        );
        const drySummary = (await dryRunRes.json()) as {
            dryRun: boolean;
            itemsAdded: number;
        };
        assert.equal(drySummary.dryRun, true);
        assert.equal(drySummary.itemsAdded, 1);
        assert.equal(srv.db.listItems().length, 1);

        const applyRes = await fetch(
            `${srv.baseUrl}/api/admin/import?dryRun=false`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(exported),
            },
        );
        assert.equal(applyRes.status, 200);
        assert.equal(srv.db.listItems().length, 2);

        // Maintenance
        const integrity = (await (
            await fetch(`${srv.baseUrl}/api/admin/maintenance/integrity`, {
                method: 'POST',
            })
        ).json()) as { ok: boolean };
        assert.equal(integrity.ok, true);

        const rebuild = await fetch(
            `${srv.baseUrl}/api/admin/maintenance/rebuild-fts`,
            { method: 'POST' },
        );
        assert.equal(rebuild.status, 200);
    } finally {
        await srv.close();
    }
});

test('returns 502 and logs scan error when upstream AI returns invalid schema, and enforces global JSON errors', async () => {
    const brokenProvider: VisionProvider = {
        name: 'ollama',
        async recognize() {
            return { wrongShape: true };
        },
    };

    const srv = await startServer({
        providers: [brokenProvider],
    });
    try {
        const badSchema = await fetch(`${srv.baseUrl}/api/recognize`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                imageBase64: Buffer.from('pic').toString('base64'),
                mimeType: 'image/jpeg',
                existingItems: [],
            }),
        });
        assert.equal(badSchema.status, 502);
        const logs = srv.db.listScanLogs(10);
        assert.equal(logs.length, 1);
        assert.equal(logs[0]?.status, 'error');

        // Global JSON error handler prevents HTML stack traces on broken JSON
        const badJson = await fetch(`${srv.baseUrl}/api/houses`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: '{broken-json',
        });
        assert.equal(badJson.status, 400);
        assert.match(badJson.headers.get('content-type') ?? '', /application\/json/);

        // Atomic PUT /api/admin/settings: invalid timeout must not persist primaryProvider
        const badSettings = await fetch(`${srv.baseUrl}/api/admin/settings`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                primaryProvider: 'ollama',
                cloudTimeoutMs: '50',
            }),
        });
        assert.equal(badSettings.status, 400);
        assert.equal(srv.db.getSettings()['ai.primaryProvider'], undefined);

        // Strict import rejects missing IDs (no NaN matching)
        const badImport = await fetch(`${srv.baseUrl}/api/admin/import?dryRun=true`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                houses: [{ name: 'No ID' }],
                rooms: [{ name: 'Room', houseId: 1 }],
            }),
        });
        assert.equal(badImport.status, 400);
    } finally {
        await srv.close();
    }
});

test('enforces write token permissions, rejects invalid token scopes, and rate-limits login with 429', async () => {
    const srv = await startServer({
        environment: {
            ADMIN_PASSWORD: 'correct-password',
            APP_API_TOKEN: 'master-token',
        },
    });
    try {
        // Reject invalid scope
        const badScope = await fetch(`${srv.baseUrl}/api/admin/tokens`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: 'Bearer master-token',
            },
            body: JSON.stringify({ name: 'bad', scope: 'admin' }),
        });
        assert.equal(badScope.status, 400);

        // Create write token: can POST /api/houses, blocked 403 on /api/admin/overview
        const writeRes = await fetch(`${srv.baseUrl}/api/admin/tokens`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: 'Bearer master-token',
            },
            body: JSON.stringify({ name: 'pwa-writer', scope: 'write' }),
        });
        assert.equal(writeRes.status, 201);
        const writeToken = (await writeRes.json()) as { token: string };

        const createdHouse = await fetch(`${srv.baseUrl}/api/houses`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': writeToken.token,
            },
            body: JSON.stringify({ name: 'Casa Scrittura' }),
        });
        assert.equal(createdHouse.status, 201);

        const adminDenied = await fetch(`${srv.baseUrl}/api/admin/overview`, {
            headers: { 'X-Api-Key': writeToken.token },
        });
        assert.equal(adminDenied.status, 403);

        // 10 failed logins -> 11th returns 429
        for (let i = 0; i < 10; i++) {
            const fail = await fetch(`${srv.baseUrl}/api/auth/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ password: 'wrong' }),
            });
            assert.equal(fail.status, 401);
        }
        const blocked = await fetch(`${srv.baseUrl}/api/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ password: 'correct-password' }),
        });
        assert.equal(blocked.status, 429);
    } finally {
        await srv.close();
    }
});
