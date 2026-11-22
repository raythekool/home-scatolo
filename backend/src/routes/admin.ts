import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { Router, type Request, type Response } from 'express';

import type { AuthConfig } from '../auth.js';
import {
    InventoryDatabase,
    InventoryNotFoundError,
    InventoryValidationError,
    type ApiTokenScope,
} from '../db.js';
import { recognitionPrompt } from '../recognition.js';
import {
    listOllamaModels,
    mergeVisionEnvironment,
    resolveVisionProviders,
    type VisionProvider,
} from '../vision/providers.js';

const ALLOWED_PROVIDERS = new Set([
    '',
    'none',
    'github-models',
    'anthropic',
    'openai-compatible',
    'ollama',
    'azure-foundry',
]);

export interface AdminRouterOptions {
    db: InventoryDatabase;
    environment: NodeJS.ProcessEnv;
    authConfig: AuthConfig;
    overrideProviders?: readonly VisionProvider[];
    fetchImpl?: typeof fetch;
}

export function createAdminRouter(options: AdminRouterOptions): Router {
    const { db, environment, authConfig } = options;
    const fetchImpl = options.fetchImpl ?? fetch;
    const router = Router();

    router.get('/overview', (_request: Request, response: Response) => {
        const settings = db.getSettings();
        const { env, promptTemplate } = mergeVisionEnvironment(
            environment,
            settings,
        );
        const providers =
            options.overrideProviders ??
            resolveVisionProviders(env, fetchImpl, promptTemplate);

        response.json({
            stats: db.getStats(),
            recognition: {
                available: providers.length > 0,
                providers: providers.map((provider) => provider.name),
                ollamaModel: env.OLLAMA_MODEL?.trim() || 'qwen2.5vl:3b',
            },
            auth: {
                enabled: authConfig.authEnabled,
                methods: {
                    password: Boolean(authConfig.adminPassword),
                    google: Boolean(authConfig.google),
                    cloudflare: Boolean(authConfig.cloudflare),
                },
            },
            scanLogs: db.listScanLogs(50),
        });
    });

    router.get('/tree', (_request: Request, response: Response) => {
        response.json({ houses: db.getTree() });
    });

    router.get('/items', (_request: Request, response: Response) => {
        response.json({ items: db.listEnrichedItems() });
    });

    router.get('/ollama/models', async (_request: Request, response: Response) => {
        const settings = db.getSettings();
        const { env } = mergeVisionEnvironment(environment, settings);
        const result = await listOllamaModels(env, fetchImpl);
        response.json(result);
    });

    router.get('/settings', (_request: Request, response: Response) => {
        const stored = db.getSettings();
        const { env } = mergeVisionEnvironment(environment, stored);
        response.json({
            settings: {
                primaryProvider: stored['ai.primaryProvider'] ?? '',
                fallbackProvider: stored['ai.fallbackProvider'] ?? '',
                ollamaModel: stored['ai.ollamaModel'] ?? '',
                cloudTimeoutMs: stored['ai.cloudTimeoutMs'] ?? '',
                ollamaTimeoutMs: stored['ai.ollamaTimeoutMs'] ?? '',
                promptTemplate: stored['ai.promptTemplate'] ?? '',
            },
            effective: {
                primaryProvider: env.AI_PRIMARY_PROVIDER ?? '',
                fallbackProvider: env.AI_FALLBACK_PROVIDER ?? '',
                ollamaModel: env.OLLAMA_MODEL ?? 'qwen2.5vl:3b',
                cloudTimeoutMs: env.AI_TIMEOUT_MS ?? '30000',
                ollamaTimeoutMs: env.OLLAMA_TIMEOUT_MS ?? '90000',
            },
            defaultPrompt: recognitionPrompt([]).trim(),
        });
    });

    router.put('/settings', (request: Request, response: Response) => {
        try {
            if (
                typeof request.body !== 'object' ||
                request.body === null ||
                Array.isArray(request.body)
            ) {
                throw new InventoryValidationError(
                    'Request body must be a JSON object.',
                );
            }
            const body = request.body as Record<string, unknown>;

            const pending: Array<{ key: string; value: string | null }> = [
                validateOptionalProviderSetting(
                    'ai.primaryProvider',
                    body.primaryProvider,
                ),
                validateOptionalProviderSetting(
                    'ai.fallbackProvider',
                    body.fallbackProvider,
                ),
                validateOptionalTextSetting('ai.ollamaModel', body.ollamaModel, 120),
                validateOptionalTimeoutSetting(
                    'ai.cloudTimeoutMs',
                    body.cloudTimeoutMs,
                ),
                validateOptionalTimeoutSetting(
                    'ai.ollamaTimeoutMs',
                    body.ollamaTimeoutMs,
                ),
                validateOptionalTextSetting(
                    'ai.promptTemplate',
                    body.promptTemplate,
                    4000,
                ),
            ].filter(
                (entry): entry is { key: string; value: string | null } =>
                    entry !== null,
            );

            for (const entry of pending) {
                if (entry.value === null) {
                    db.deleteSetting(entry.key);
                } else {
                    db.setSetting(entry.key, entry.value);
                }
            }

            const stored = db.getSettings();
            response.json({
                settings: {
                    primaryProvider: stored['ai.primaryProvider'] ?? '',
                    fallbackProvider: stored['ai.fallbackProvider'] ?? '',
                    ollamaModel: stored['ai.ollamaModel'] ?? '',
                    cloudTimeoutMs: stored['ai.cloudTimeoutMs'] ?? '',
                    ollamaTimeoutMs: stored['ai.ollamaTimeoutMs'] ?? '',
                    promptTemplate: stored['ai.promptTemplate'] ?? '',
                },
            });
        } catch (error) {
            handleError(response, error);
        }
    });

    router.get('/backup/sqlite', (_request: Request, response: Response) => {
        const tempDir = mkdtempSync(join(tmpdir(), 'home-scatolo-backup-'));
        const dateStamp = new Date().toISOString().slice(0, 10);
        const fileName = `home-scatolo-${dateStamp}.db`;
        const backupPath = join(tempDir, fileName);

        const cleanup = () => {
            rmSync(tempDir, { recursive: true, force: true });
        };

        try {
            db.createBackupFile(backupPath);
            response.download(backupPath, fileName, (err) => {
                cleanup();
                if (err && !response.headersSent) {
                    response
                        .status(500)
                        .json({ error: 'Unable to send SQLite backup.' });
                }
            });
        } catch {
            cleanup();
            response
                .status(500)
                .json({ error: 'Unable to create SQLite backup.' });
        }
    });

    router.get('/export/csv', (_request: Request, response: Response) => {
        const items = db.listEnrichedItems();
        const header = [
            'ID',
            'Casa',
            'Stanza',
            'Contenitore',
            'Tipo',
            'Oggetto',
            'Categoria',
            'Quantita',
            'Descrizione',
            'Note',
            'Inserito',
        ];
        const lines = [
            header.join(','),
            ...items.map((item) =>
                [
                    item.id,
                    item.houseName,
                    item.roomName,
                    item.containerName,
                    item.containerType,
                    item.name,
                    item.category,
                    item.quantity,
                    item.shortDescription,
                    item.notes,
                    item.insertedAt,
                ]
                    .map(csvCell)
                    .join(','),
            ),
        ];
        const dateStamp = new Date().toISOString().slice(0, 10);
        response.setHeader('Content-Type', 'text/csv; charset=utf-8');
        response.setHeader(
            'Content-Disposition',
            `attachment; filename="home-scatolo-${dateStamp}.csv"`,
        );
        response.send(`\uFEFF${lines.join('\r\n')}\r\n`);
    });

    router.post('/import', (request: Request, response: Response) => {
        try {
            const dryRun =
                request.query.dryRun === 'true' ||
                request.query.dryRun === '1';
            const summary = db.importInventory(request.body, { dryRun });
            response.json(summary);
        } catch (error) {
            handleError(response, error);
        }
    });

    router.post(
        '/maintenance/integrity',
        (_request: Request, response: Response) => {
            response.json(db.checkIntegrity());
        },
    );

    router.post(
        '/maintenance/rebuild-fts',
        (_request: Request, response: Response) => {
            db.rebuildFts();
            response.json({ status: 'ok' });
        },
    );

    router.get('/tokens', (_request: Request, response: Response) => {
        response.json({ tokens: db.listApiTokens() });
    });

    router.post('/tokens', (request: Request, response: Response) => {
        try {
            if (
                typeof request.body !== 'object' ||
                request.body === null ||
                Array.isArray(request.body)
            ) {
                throw new InventoryValidationError(
                    'Request body must be a JSON object.',
                );
            }
            const body = request.body as { name?: unknown; scope?: unknown };
            const name = typeof body.name === 'string' ? body.name : '';
            const rawScope = body.scope === undefined ? 'read' : body.scope;
            if (rawScope !== 'read' && rawScope !== 'write') {
                throw new InventoryValidationError(
                    'scope must be "read" or "write".',
                );
            }
            const scope: ApiTokenScope = rawScope;
            const created = db.createApiToken({ name, scope });
            response.status(201).json(created);
        } catch (error) {
            handleError(response, error);
        }
    });

    router.delete('/tokens/:id', (request: Request, response: Response) => {
        try {
            const raw = Array.isArray(request.params.id)
                ? request.params.id[0]
                : request.params.id;
            if (!raw || !/^\d+$/.test(raw)) {
                throw new InventoryValidationError('id must be a positive integer.');
            }
            db.revokeApiToken(Number.parseInt(raw, 10));
            response.status(204).end();
        } catch (error) {
            handleError(response, error);
        }
    });

    return router;
}

function validateOptionalProviderSetting(
    key: string,
    raw: unknown,
): { key: string; value: string | null } | null {
    if (raw === undefined) return null;
    if (typeof raw !== 'string') {
        throw new InventoryValidationError(`${key} must be a string.`);
    }
    const value = raw.trim().toLowerCase();
    if (!ALLOWED_PROVIDERS.has(value)) {
        throw new InventoryValidationError(`Invalid provider value for ${key}.`);
    }
    return { key, value: value === '' ? null : value };
}

function validateOptionalTextSetting(
    key: string,
    raw: unknown,
    maxLength: number,
): { key: string; value: string | null } | null {
    if (raw === undefined) return null;
    if (typeof raw !== 'string') {
        throw new InventoryValidationError(`${key} must be a string.`);
    }
    const value = raw.trim();
    if (value.length > maxLength) {
        throw new InventoryValidationError(
            `${key} exceeds maximum length of ${maxLength}.`,
        );
    }
    return { key, value: value === '' ? null : value };
}

function validateOptionalTimeoutSetting(
    key: string,
    raw: unknown,
): { key: string; value: string | null } | null {
    if (raw === undefined) return null;
    if (raw === '' || raw === null) {
        return { key, value: null };
    }
    const str = String(raw).trim();
    if (!/^\d+$/.test(str)) {
        throw new InventoryValidationError(
            `${key} must be an integer between 1000 and 300000 ms.`,
        );
    }
    const parsed = Number.parseInt(str, 10);
    if (!Number.isSafeInteger(parsed) || parsed < 1000 || parsed > 300_000) {
        throw new InventoryValidationError(
            `${key} must be an integer between 1000 and 300000 ms.`,
        );
    }
    return { key, value: String(parsed) };
}

function csvCell(value: unknown): string {
    const raw = String(value ?? '');
    const safe = /^[=+\-@\t\r]/.test(raw) ? `'${raw}` : raw;
    if (/[",\r\n]/.test(safe)) {
        return `"${safe.replace(/"/g, '""')}"`;
    }
    return safe;
}

function handleError(response: Response, error: unknown): void {
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
