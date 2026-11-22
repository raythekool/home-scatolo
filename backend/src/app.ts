import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import cors from 'cors';
import express, {
    type Express,
    type NextFunction,
    type Request,
    type Response,
} from 'express';

import {
    createAuthService,
    readAuthConfig,
    type CloudflareJwksProvider,
} from './auth.js';
import { InventoryDatabase } from './db.js';
import {
    parseRecognitionRequest,
    RecognitionValidationError,
} from './recognition.js';
import { createAdminRouter } from './routes/admin.js';
import { createAuthRouter } from './routes/auth.js';
import { createInventoryRouter } from './routes/inventory.js';
import {
    mergeVisionEnvironment,
    recognizeWithFallback,
    resolveVisionProviders,
    type VisionProvider,
} from './vision/providers.js';

const currentDir = dirname(fileURLToPath(import.meta.url));
const defaultAdminDir = join(currentDir, 'admin', 'public');

export interface CreateAppOptions {
    db: InventoryDatabase;
    environment?: NodeJS.ProcessEnv;
    providers?: readonly VisionProvider[];
    publicWebDir?: string | null;
    adminWebDir?: string | null;
    cloudflareJwks?: CloudflareJwksProvider;
    fetchImpl?: typeof fetch;
}

export function createApp(options: CreateAppOptions): Express {
    const environment = options.environment ?? process.env;
    const fetchImpl = options.fetchImpl ?? fetch;
    const app = express();

    // Respect X-Forwarded-For / X-Forwarded-Proto behind Cloudflare Tunnel
    app.set('trust proxy', 1);

    const allowedOrigins = (
        environment.ALLOWED_ORIGINS ??
        'http://localhost:8080,http://localhost:3000'
    )
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean);

    app.use(
        cors({
            origin: allowedOrigins,
            credentials: true,
            allowedHeaders: [
                'Content-Type',
                'Authorization',
                'X-Api-Key',
                'Cf-Access-Jwt-Assertion',
            ],
            exposedHeaders: ['X-Vision-Provider', 'X-Vision-Fallback'],
        }),
    );
    app.use(express.json({ limit: '7mb' }));

    const authConfig = readAuthConfig(environment);
    const authService = createAuthService({
        db: options.db,
        config: authConfig,
        cloudflareJwks: options.cloudflareJwks,
        fetchImpl,
    });

    const getProviders = (): readonly VisionProvider[] => {
        if (options.providers) {
            return options.providers;
        }
        const { env, promptTemplate } = mergeVisionEnvironment(
            environment,
            options.db.getSettings(),
        );
        return resolveVisionProviders(env, fetchImpl, promptTemplate);
    };

    app.get('/livez', (_request: Request, response: Response) => {
        try {
            if (!options.db.ping()) {
                response.status(503).json({ status: 'error', database: 'error' });
                return;
            }
            response.json({ status: 'ok', database: 'ok' });
        } catch {
            response.status(503).json({ status: 'error', database: 'error' });
        }
    });

    app.get('/health', (_request: Request, response: Response) => {
        let dbOk = false;
        try {
            dbOk = options.db.ping();
        } catch {
            dbOk = false;
        }

        const providers = getProviders();
        const recognitionAvailable = providers.length > 0;
        const ready = dbOk && recognitionAvailable;

        response.status(ready ? 200 : 503).json({
            status: ready ? 'ok' : 'configuring',
            database: dbOk ? 'ok' : 'error',
            recognition: {
                available: recognitionAvailable,
                providers: providers.map((provider) => provider.name),
            },
            authEnabled: authConfig.authEnabled,
        });
    });

    const recognizeHandler = async (request: Request, response: Response) => {
        const startedAt = Date.now();
        try {
            const recognitionRequest = parseRecognitionRequest(request.body);
            const outcome = await recognizeWithFallback(
                recognitionRequest,
                getProviders(),
                (providerName, error) => {
                    const reason =
                        error instanceof Error ? error.name : 'UnknownError';
                    console.warn(
                        `Vision provider "${providerName}" failed (${reason}); trying fallback if configured.`,
                    );
                },
            );
            options.db.logScan({
                provider: outcome.provider,
                usedFallback: outcome.usedFallback,
                latencyMs: Date.now() - startedAt,
                itemsCount: outcome.result.items.length,
                status: 'ok',
            });
            response.setHeader('X-Vision-Provider', outcome.provider);
            response.setHeader(
                'X-Vision-Fallback',
                outcome.usedFallback ? 'true' : 'false',
            );
            response.json(outcome.result);
        } catch (error) {
            if (error instanceof RecognitionValidationError) {
                response.status(400).json({ error: error.message });
                return;
            }

            const errorCode =
                error instanceof Error ? error.name : 'RecognitionError';
            try {
                options.db.logScan({
                    provider:
                        getProviders()
                            .map((p) => p.name)
                            .join('->') || 'none',
                    usedFallback: false,
                    latencyMs: Date.now() - startedAt,
                    itemsCount: 0,
                    status: 'error',
                    errorCode,
                });
            } catch {
                // Never mask API response if logging fails
            }

            response
                .status(502)
                .json({ error: 'Recognition is currently unavailable.' });
        }
    };

    const requireWrite = authService.requireRole('write');
    const requireAdmin = authService.requireRole('admin');
    const requireInventory = authService.requireInventoryAccess();

    app.use('/api/auth', createAuthRouter(authService, fetchImpl));
    app.use(
        '/api/admin',
        requireAdmin,
        createAdminRouter({
            db: options.db,
            environment,
            authConfig,
            overrideProviders: options.providers,
            fetchImpl,
        }),
    );

    app.post('/recognize', requireWrite, recognizeHandler);
    app.post('/api/recognize', requireWrite, recognizeHandler);
    app.use('/api', requireInventory, createInventoryRouter(options.db));

    // ---- Admin Web Console (/admin) ----
    const resolvedAdminDir = resolveStaticDir(
        options.adminWebDir !== undefined ? options.adminWebDir : defaultAdminDir,
    );
    if (resolvedAdminDir) {
        app.use('/admin', (_request: Request, response: Response, next: NextFunction) => {
            response.setHeader('X-Content-Type-Options', 'nosniff');
            response.setHeader('X-Frame-Options', 'DENY');
            response.setHeader('Referrer-Policy', 'same-origin');
            response.setHeader(
                'Content-Security-Policy',
                "default-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; base-uri 'self'; frame-ancestors 'none'",
            );
            next();
        });
        app.use('/admin', express.static(resolvedAdminDir));
        app.get('/admin', (_request: Request, response: Response) => {
            response.sendFile(join(resolvedAdminDir, 'index.html'));
        });
        app.use('/admin', (request: Request, response: Response, next: NextFunction) => {
            if (request.method !== 'GET') {
                next();
                return;
            }
            response.sendFile(join(resolvedAdminDir, 'index.html'));
        });
    }

    // ---- Optional Flutter PWA Static Hosting (/) ----
    const resolvedPublicDir = resolveStaticDir(
        options.publicWebDir !== undefined
            ? options.publicWebDir
            : environment.PUBLIC_WEB_DIR,
    );

    if (resolvedPublicDir) {
        app.use(express.static(resolvedPublicDir));
        app.use((request: Request, response: Response, next: NextFunction) => {
            if (
                request.method !== 'GET' ||
                request.path.startsWith('/api/') ||
                request.path === '/api' ||
                request.path.startsWith('/admin') ||
                request.path === '/health' ||
                request.path === '/livez' ||
                request.path === '/recognize'
            ) {
                next();
                return;
            }
            response.sendFile(join(resolvedPublicDir, 'index.html'));
        });
    }

    // Global JSON error handler (prevents Express default HTML stack traces on bad JSON / 413)
    app.use(
        (
            error: unknown,
            _request: Request,
            response: Response,
            _next: NextFunction,
        ) => {
            const err = error as { status?: number; type?: string };
            if (err?.type === 'entity.too.large' || err?.status === 413) {
                response.status(413).json({ error: 'Payload too large.' });
                return;
            }
            if (err?.type === 'entity.parse.failed' || err?.status === 400) {
                response.status(400).json({ error: 'Invalid JSON request body.' });
                return;
            }
            response.status(500).json({ error: 'Internal server error.' });
        },
    );

    return app;
}

function resolveStaticDir(
    configuredDir: string | null | undefined,
): string | null {
    if (!configuredDir || configuredDir.trim().length === 0) {
        return null;
    }
    const candidate = resolve(configuredDir.trim());
    if (existsSync(join(candidate, 'index.html'))) {
        return candidate;
    }
    return null;
}
