import {
    createHash,
    createHmac,
    createPublicKey,
    createVerify,
    randomBytes,
    timingSafeEqual,
    type KeyObject,
    type webcrypto,
} from 'node:crypto';
import type { NextFunction, Request, RequestHandler, Response } from 'express';

import type { InventoryDatabase } from './db.js';

export type AuthRole = 'read' | 'write' | 'admin';

export interface AuthPrincipal {
    authenticated: boolean;
    role: AuthRole;
    method:
        | 'open'
        | 'cloudflare'
        | 'google'
        | 'password'
        | 'master-token'
        | 'api-token';
    subject: string;
}

export interface CloudflareAccessConfig {
    teamDomain: string;
    aud: string;
    certsUrl: string;
}

export interface GoogleOAuthConfig {
    clientId: string;
    clientSecret: string;
    redirectUri: string | null;
}

export interface AuthConfig {
    authEnabled: boolean;
    masterToken: string | null;
    adminPassword: string | null;
    sessionSecret: Buffer;
    sessionTtlSeconds: number;
    cloudflare: CloudflareAccessConfig | null;
    google: GoogleOAuthConfig | null;
    allowedEmails: Set<string>;
}

export const SESSION_COOKIE_NAME = 'hs_session';
export const OAUTH_STATE_COOKIE_NAME = 'hs_oauth_state';

const ROLE_LEVEL: Record<AuthRole, number> = {
    read: 1,
    write: 2,
    admin: 3,
};

export function readApiToken(environment: NodeJS.ProcessEnv): string | null {
    const token = environment.APP_API_TOKEN?.trim();
    return token && token.length > 0 ? token : null;
}

export function readAuthConfig(environment: NodeJS.ProcessEnv): AuthConfig {
    const masterToken = readApiToken(environment);
    const explicitPassword = environment.ADMIN_PASSWORD?.trim() || null;
    const adminPassword = explicitPassword ?? masterToken;

    const cfTeamRaw = environment.CF_ACCESS_TEAM_DOMAIN?.trim();
    const cfAud = environment.CF_ACCESS_AUD?.trim();
    let cloudflare: CloudflareAccessConfig | null = null;
    if (cfTeamRaw && cfAud) {
        const teamDomain = cfTeamRaw
            .replace(/^https?:\/\//i, '')
            .replace(/\/+$/, '');
        cloudflare = {
            teamDomain,
            aud: cfAud,
            certsUrl: `https://${teamDomain}/cdn-cgi/access/certs`,
        };
    }

    const googleClientId = environment.GOOGLE_CLIENT_ID?.trim();
    const googleClientSecret = environment.GOOGLE_CLIENT_SECRET?.trim();
    const google: GoogleOAuthConfig | null =
        googleClientId && googleClientSecret
            ? {
                  clientId: googleClientId,
                  clientSecret: googleClientSecret,
                  redirectUri: environment.GOOGLE_REDIRECT_URI?.trim() || null,
              }
            : null;

    const allowedEmails = new Set(
        (environment.AUTH_ALLOWED_EMAILS ?? '')
            .split(',')
            .map((email) => email.trim().toLowerCase())
            .filter(Boolean),
    );

    const authEnabled = Boolean(
        masterToken || adminPassword || cloudflare || google,
    );

    const secretSeed =
        environment.SESSION_SECRET?.trim() ||
        adminPassword ||
        masterToken ||
        googleClientSecret ||
        randomBytes(32).toString('hex');
    const sessionSecret = createHash('sha256')
        .update(`home-scatolo-session:${secretSeed}`, 'utf8')
        .digest();

    const parsedTtl = Number.parseInt(
        environment.SESSION_TTL_SECONDS ?? '',
        10,
    );
    const sessionTtlSeconds =
        Number.isInteger(parsedTtl) && parsedTtl >= 300
            ? parsedTtl
            : 60 * 60 * 24 * 30;

    return {
        authEnabled,
        masterToken,
        adminPassword,
        sessionSecret,
        sessionTtlSeconds,
        cloudflare,
        google,
        allowedEmails,
    };
}

export function createSessionCookieValue(
    payload: { sub: string; method: 'password' | 'google' | 'cloudflare' },
    config: AuthConfig,
    nowSeconds: number = Math.floor(Date.now() / 1000),
): string {
    const body = {
        sub: payload.sub,
        method: payload.method,
        role: 'admin' as const,
        iat: nowSeconds,
        exp: nowSeconds + config.sessionTtlSeconds,
    };
    const encoded = Buffer.from(JSON.stringify(body), 'utf8').toString(
        'base64url',
    );
    const sig = createHmac('sha256', config.sessionSecret)
        .update(encoded)
        .digest('base64url');
    return `${encoded}.${sig}`;
}

export function verifySessionCookieValue(
    rawCookie: string,
    config: AuthConfig,
    nowSeconds: number = Math.floor(Date.now() / 1000),
): { sub: string; method: 'password' | 'google' | 'cloudflare' } | null {
    const parts = rawCookie.split('.');
    if (parts.length !== 2) {
        return null;
    }
    const [encoded, providedSig] = parts;
    if (!encoded || !providedSig) {
        return null;
    }

    const expectedSig = createHmac('sha256', config.sessionSecret)
        .update(encoded)
        .digest();
    let providedBuf: Buffer;
    try {
        providedBuf = Buffer.from(providedSig, 'base64url');
    } catch {
        return null;
    }
    if (
        providedBuf.length !== expectedSig.length ||
        !timingSafeEqual(providedBuf, expectedSig)
    ) {
        return null;
    }

    try {
        const parsed = JSON.parse(
            Buffer.from(encoded, 'base64url').toString('utf8'),
        ) as {
            sub?: unknown;
            method?: unknown;
            exp?: unknown;
        };
        if (
            typeof parsed.sub !== 'string' ||
            typeof parsed.exp !== 'number' ||
            parsed.exp <= nowSeconds
        ) {
            return null;
        }
        if (
            parsed.method !== 'password' &&
            parsed.method !== 'google' &&
            parsed.method !== 'cloudflare'
        ) {
            return null;
        }
        return { sub: parsed.sub, method: parsed.method };
    } catch {
        return null;
    }
}

export function createSignedOAuthState(
    nonce: string,
    config: AuthConfig,
): string {
    const sig = createHmac('sha256', config.sessionSecret)
        .update(`oauth-state:${nonce}`)
        .digest('base64url');
    return `${nonce}.${sig}`;
}

export function verifySignedOAuthState(
    value: string,
    config: AuthConfig,
): string | null {
    const parts = value.split('.');
    if (parts.length !== 2) return null;
    const [nonce, sig] = parts;
    if (!nonce || !sig) return null;
    const expected = createHmac('sha256', config.sessionSecret)
        .update(`oauth-state:${nonce}`)
        .digest();
    let provided: Buffer;
    try {
        provided = Buffer.from(sig, 'base64url');
    } catch {
        return null;
    }
    if (
        provided.length !== expected.length ||
        !timingSafeEqual(provided, expected)
    ) {
        return null;
    }
    return nonce;
}

export function verifyPasswordCredential(
    candidate: string,
    config: AuthConfig,
): boolean {
    if (!config.adminPassword || candidate.length === 0) {
        return false;
    }
    return timingSafeEqual(sha256(candidate), sha256(config.adminPassword));
}

export interface CloudflareJwksProvider {
    getKey(kid: string | undefined, forceRefresh: boolean): Promise<KeyObject | null>;
}

export function createCloudflareJwksProvider(
    certsUrl: string,
    fetchImpl: typeof fetch = fetch,
): CloudflareJwksProvider {
    let cachedKeys = new Map<string, KeyObject>();
    let cachedAll: KeyObject[] = [];
    let cachedAt = 0;
    const cacheTtlMs = 60 * 60 * 1000;

    async function refresh(): Promise<void> {
        const response = await fetchImpl(certsUrl, {
            signal: AbortSignal.timeout(8_000),
        });
        if (!response.ok) {
            throw new Error(`Cloudflare certs fetch failed (${response.status})`);
        }
        const payload = (await response.json()) as {
            keys?: Array<webcrypto.JsonWebKey & { kid?: string }>;
        };
        const nextMap = new Map<string, KeyObject>();
        const nextAll: KeyObject[] = [];
        for (const jwk of payload.keys ?? []) {
            try {
                const keyObject = createPublicKey({ key: jwk, format: 'jwk' });
                nextAll.push(keyObject);
                if (typeof jwk.kid === 'string') {
                    nextMap.set(jwk.kid, keyObject);
                }
            } catch {
                // Ignore unsupported key entries
            }
        }
        cachedKeys = nextMap;
        cachedAll = nextAll;
        cachedAt = Date.now();
    }

    return {
        async getKey(
            kid: string | undefined,
            forceRefresh: boolean,
        ): Promise<KeyObject | null> {
            const expired = Date.now() - cachedAt > cacheTtlMs;
            if (forceRefresh || expired || cachedAll.length === 0) {
                await refresh();
            }
            if (kid && cachedKeys.has(kid)) {
                return cachedKeys.get(kid) ?? null;
            }
            if (!forceRefresh && kid) {
                await refresh();
                return cachedKeys.get(kid) ?? null;
            }
            return cachedAll[0] ?? null;
        },
    };
}

export async function verifyCloudflareAccessJwt(
    jwt: string,
    config: CloudflareAccessConfig,
    jwksProvider: CloudflareJwksProvider,
    allowedEmails: Set<string>,
    nowSeconds: number = Math.floor(Date.now() / 1000),
): Promise<{ email: string } | null> {
    const segments = jwt.split('.');
    if (segments.length !== 3) {
        return null;
    }
    const [headerB64, payloadB64, signatureB64] = segments;
    if (!headerB64 || !payloadB64 || !signatureB64) {
        return null;
    }

    let header: { alg?: unknown; kid?: unknown };
    let payload: {
        aud?: unknown;
        iss?: unknown;
        exp?: unknown;
        nbf?: unknown;
        email?: unknown;
        sub?: unknown;
    };
    try {
        header = JSON.parse(Buffer.from(headerB64, 'base64url').toString('utf8'));
        payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
    } catch {
        return null;
    }

    if (header.alg !== 'RS256') {
        return null;
    }

    const audValues = Array.isArray(payload.aud)
        ? payload.aud.filter((v): v is string => typeof v === 'string')
        : typeof payload.aud === 'string'
          ? [payload.aud]
          : [];
    if (!audValues.includes(config.aud)) {
        return null;
    }

    const expectedIssuer = `https://${config.teamDomain}`;
    if (typeof payload.iss !== 'string' || payload.iss.replace(/\/+$/, '') !== expectedIssuer) {
        return null;
    }

    if (typeof payload.exp !== 'number' || payload.exp <= nowSeconds) {
        return null;
    }
    if (typeof payload.nbf === 'number' && payload.nbf > nowSeconds + 60) {
        return null;
    }

    const email =
        typeof payload.email === 'string'
            ? payload.email.trim().toLowerCase()
            : typeof payload.sub === 'string'
              ? payload.sub.trim().toLowerCase()
              : '';
    if (!email) {
        return null;
    }
    if (allowedEmails.size > 0 && !allowedEmails.has(email)) {
        return null;
    }

    const kid = typeof header.kid === 'string' ? header.kid : undefined;
    let key: KeyObject | null;
    try {
        key = await jwksProvider.getKey(kid, false);
    } catch {
        return null;
    }
    if (!key) {
        return null;
    }

    const verifier = createVerify('RSA-SHA256');
    verifier.update(`${headerB64}.${payloadB64}`);
    verifier.end();

    let signatureBuf: Buffer;
    try {
        signatureBuf = Buffer.from(signatureB64, 'base64url');
    } catch {
        return null;
    }

    if (!verifier.verify(key, signatureBuf)) {
        return null;
    }

    return { email };
}

export class LoginRateLimiter {
    private readonly attempts = new Map<string, number[]>();
    private readonly maxAttempts: number;
    private readonly windowMs: number;

    constructor(maxAttempts: number = 10, windowMs: number = 15 * 60 * 1000) {
        this.maxAttempts = maxAttempts;
        this.windowMs = windowMs;
    }

    isBlocked(key: string, now: number = Date.now()): boolean {
        const list = this.prune(key, now);
        return list.length >= this.maxAttempts;
    }

    recordFailure(key: string, now: number = Date.now()): void {
        if (this.attempts.size >= 1000) {
            for (const existingKey of this.attempts.keys()) {
                this.prune(existingKey, now);
                if (this.attempts.size < 900) break;
            }
            if (this.attempts.size >= 1000) {
                const oldestKey = this.attempts.keys().next().value;
                if (oldestKey !== undefined) {
                    this.attempts.delete(oldestKey);
                }
            }
        }
        const list = this.prune(key, now);
        list.push(now);
        this.attempts.set(key, list);
    }

    reset(key: string): void {
        this.attempts.delete(key);
    }

    private prune(key: string, now: number): number[] {
        const cutoff = now - this.windowMs;
        const existing = this.attempts.get(key) ?? [];
        const filtered = existing.filter((ts) => ts > cutoff);
        if (filtered.length === 0) {
            this.attempts.delete(key);
        } else {
            this.attempts.set(key, filtered);
        }
        return filtered;
    }
}

export interface AuthService {
    readonly config: AuthConfig;
    readonly rateLimiter: LoginRateLimiter;
    authenticate(request: Request): Promise<AuthPrincipal | null>;
    requireRole(minimumRole: AuthRole): RequestHandler;
    requireInventoryAccess(): RequestHandler;
}

export function createAuthService(options: {
    db: InventoryDatabase;
    config: AuthConfig;
    cloudflareJwks?: CloudflareJwksProvider;
    fetchImpl?: typeof fetch;
}): AuthService {
    const { db, config } = options;
    const rateLimiter = new LoginRateLimiter();
    const cfJwks =
        options.cloudflareJwks ??
        (config.cloudflare
            ? createCloudflareJwksProvider(
                  config.cloudflare.certsUrl,
                  options.fetchImpl,
              )
            : undefined);

    const masterDigest = config.masterToken ? sha256(config.masterToken) : null;

    async function authenticate(request: Request): Promise<AuthPrincipal | null> {
        if (!config.authEnabled) {
            return {
                authenticated: true,
                role: 'admin',
                method: 'open',
                subject: 'local',
            };
        }

        // 1. Cloudflare Access JWT (cryptographically verified via JWKS)
        if (config.cloudflare && cfJwks) {
            const cfJwt =
                request.header('cf-access-jwt-assertion')?.trim() ||
                parseCookies(request.header('cookie'))['CF_Authorization'];
            if (cfJwt) {
                const verified = await verifyCloudflareAccessJwt(
                    cfJwt,
                    config.cloudflare,
                    cfJwks,
                    config.allowedEmails,
                );
                if (verified) {
                    return {
                        authenticated: true,
                        role: 'admin',
                        method: 'cloudflare',
                        subject: verified.email,
                    };
                }
            }
        }

        // 2. Signed HttpOnly session cookie (password or Google OAuth)
        const cookies = parseCookies(request.header('cookie'));
        const sessionCookie = cookies[SESSION_COOKIE_NAME];
        if (sessionCookie) {
            const session = verifySessionCookieValue(sessionCookie, config);
            if (session) {
                const emailRevoked =
                    session.method === 'google' &&
                    config.allowedEmails.size > 0 &&
                    !config.allowedEmails.has(session.sub.toLowerCase());
                if (!emailRevoked) {
                    return {
                        authenticated: true,
                        role: 'admin',
                        method: session.method,
                        subject: session.sub,
                    };
                }
            }
        }

        // 3. Bearer / X-Api-Key (master token or scoped SQLite API token)
        const presentedToken = extractToken(request);
        if (presentedToken) {
            if (masterDigest) {
                const providedDigest = sha256(presentedToken);
                if (timingSafeEqual(providedDigest, masterDigest)) {
                    return {
                        authenticated: true,
                        role: 'admin',
                        method: 'master-token',
                        subject: 'api-master',
                    };
                }
            }

            const dbToken = db.verifyApiToken(presentedToken);
            if (dbToken) {
                return {
                    authenticated: true,
                    role: dbToken.scope,
                    method: 'api-token',
                    subject: dbToken.name,
                };
            }
        }

        return null;
    }

    function requireRole(minimumRole: AuthRole): RequestHandler {
        return async (
            request: Request,
            response: Response,
            next: NextFunction,
        ) => {
            if (request.method === 'OPTIONS') {
                next();
                return;
            }

            const principal = await authenticate(request);
            if (!principal) {
                const hasCredential = Boolean(
                    extractToken(request) ||
                        request.header('cf-access-jwt-assertion') ||
                        parseCookies(request.header('cookie'))[SESSION_COOKIE_NAME],
                );
                response
                    .status(hasCredential ? 403 : 401)
                    .json({
                        error: hasCredential
                            ? 'Invalid credentials.'
                            : 'Authentication required.',
                    });
                return;
            }

            if (ROLE_LEVEL[principal.role] < ROLE_LEVEL[minimumRole]) {
                response
                    .status(403)
                    .json({ error: 'Insufficient permissions.' });
                return;
            }

            response.locals.auth = principal;
            next();
        };
    }

    function requireInventoryAccess(): RequestHandler {
        const readMiddleware = requireRole('read');
        const writeMiddleware = requireRole('write');
        return (request: Request, response: Response, next: NextFunction) => {
            if (request.method === 'GET' || request.method === 'HEAD') {
                return readMiddleware(request, response, next);
            }
            return writeMiddleware(request, response, next);
        };
    }

    return {
        config,
        rateLimiter,
        authenticate,
        requireRole,
        requireInventoryAccess,
    };
}

export function createAuthMiddleware(expectedToken: string | null): RequestHandler {
    if (!expectedToken) {
        return (_request: Request, _response: Response, next: NextFunction) => {
            next();
        };
    }

    const expectedDigest = sha256(expectedToken);

    return (request: Request, response: Response, next: NextFunction) => {
        if (request.method === 'OPTIONS') {
            next();
            return;
        }

        const provided = extractToken(request);
        if (!provided) {
            response.status(401).json({ error: 'Authentication required.' });
            return;
        }

        const providedDigest = sha256(provided);
        if (!timingSafeEqual(providedDigest, expectedDigest)) {
            response.status(403).json({ error: 'Invalid credentials.' });
            return;
        }

        next();
    };
}

export function parseCookies(
    cookieHeader: string | undefined,
): Record<string, string> {
    if (!cookieHeader) {
        return {};
    }
    const result: Record<string, string> = {};
    for (const pair of cookieHeader.split(';')) {
        const idx = pair.indexOf('=');
        if (idx <= 0) continue;
        const name = pair.slice(0, idx).trim();
        const value = pair.slice(idx + 1).trim();
        if (name) {
            result[name] = value;
        }
    }
    return result;
}

export function isSecureRequest(request: Request): boolean {
    if (request.secure) return true;
    const forwardedProto = request.header('x-forwarded-proto');
    if (forwardedProto) {
        return forwardedProto
            .split(',')[0]
            ?.trim()
            .toLowerCase() === 'https';
    }
    return false;
}

export function serializeCookie(
    name: string,
    value: string,
    options: {
        maxAgeSeconds?: number;
        httpOnly?: boolean;
        sameSite?: 'Lax' | 'Strict' | 'None';
        secure?: boolean;
        path?: string;
    } = {},
): string {
    const parts = [`${name}=${value}`];
    parts.push(`Path=${options.path ?? '/'}`);
    if (options.maxAgeSeconds !== undefined) {
        parts.push(`Max-Age=${Math.max(0, Math.floor(options.maxAgeSeconds))}`);
    }
    if (options.httpOnly !== false) {
        parts.push('HttpOnly');
    }
    parts.push(`SameSite=${options.sameSite ?? 'Lax'}`);
    if (options.secure) {
        parts.push('Secure');
    }
    return parts.join('; ');
}

function extractToken(request: Request): string | null {
    const authorization = request.header('authorization');
    if (authorization) {
        const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());
        if (match && match[1]) {
            return match[1].trim();
        }
    }

    const apiKey = request.header('x-api-key');
    if (apiKey && apiKey.trim().length > 0) {
        return apiKey.trim();
    }

    return null;
}

function sha256(value: string): Buffer {
    return createHash('sha256').update(value, 'utf8').digest();
}
