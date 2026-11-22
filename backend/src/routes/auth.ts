import { randomBytes } from 'node:crypto';
import { Router, type Request, type Response } from 'express';

import {
    createSessionCookieValue,
    createSignedOAuthState,
    isSecureRequest,
    OAUTH_STATE_COOKIE_NAME,
    parseCookies,
    serializeCookie,
    SESSION_COOKIE_NAME,
    verifyPasswordCredential,
    verifySignedOAuthState,
    type AuthService,
} from '../auth.js';

export function createAuthRouter(
    authService: AuthService,
    fetchImpl: typeof fetch = fetch,
): Router {
    const router = Router();
    const { config, rateLimiter } = authService;

    router.get('/config', (_request: Request, response: Response) => {
        response.json({
            authEnabled: config.authEnabled,
            methods: {
                password: Boolean(config.adminPassword),
                google: Boolean(config.google),
                cloudflare: Boolean(config.cloudflare),
            },
            googleRequiresAllowedEmails:
                Boolean(config.google) && config.allowedEmails.size === 0,
        });
    });

    router.get('/session', async (request: Request, response: Response) => {
        const principal = await authService.authenticate(request);
        if (!principal) {
            response.json({
                authenticated: false,
                authEnabled: config.authEnabled,
                role: null,
                method: null,
                subject: null,
            });
            return;
        }
        response.json({
            authenticated: true,
            authEnabled: config.authEnabled,
            role: principal.role,
            method: principal.method,
            subject: principal.subject,
        });
    });

    router.post('/login', (request: Request, response: Response) => {
        if (!config.authEnabled) {
            response.json({ authenticated: true, role: 'admin', method: 'open' });
            return;
        }
        if (!config.adminPassword) {
            response.status(400).json({
                error: 'Password login is not enabled on this server.',
            });
            return;
        }

        const clientIp =
            (config.cloudflare ? request.header('cf-connecting-ip') : undefined) ||
            request.ip ||
            'unknown';

        if (rateLimiter.isBlocked(clientIp)) {
            response.status(429).json({
                error: 'Troppi tentativi falliti. Riprova tra qualche minuto.',
            });
            return;
        }

        const body = request.body as { password?: unknown } | undefined;
        const password =
            typeof body?.password === 'string' ? body.password.trim() : '';

        if (!verifyPasswordCredential(password, config)) {
            rateLimiter.recordFailure(clientIp);
            response.status(401).json({ error: 'Credenziali non valide.' });
            return;
        }

        rateLimiter.reset(clientIp);
        const cookieValue = createSessionCookieValue(
            { sub: 'admin', method: 'password' },
            config,
        );
        response.setHeader(
            'Set-Cookie',
            serializeCookie(SESSION_COOKIE_NAME, cookieValue, {
                maxAgeSeconds: config.sessionTtlSeconds,
                httpOnly: true,
                sameSite: 'Lax',
                secure: isSecureRequest(request),
            }),
        );
        response.json({
            authenticated: true,
            role: 'admin',
            method: 'password',
            subject: 'admin',
        });
    });

    router.post('/logout', (request: Request, response: Response) => {
        response.setHeader(
            'Set-Cookie',
            serializeCookie(SESSION_COOKIE_NAME, '', {
                maxAgeSeconds: 0,
                httpOnly: true,
                sameSite: 'Lax',
                secure: isSecureRequest(request),
            }),
        );
        response.json({ authenticated: false });
    });

    router.get('/google', (request: Request, response: Response) => {
        if (!config.google) {
            response
                .status(404)
                .json({ error: 'Google OAuth is not configured.' });
            return;
        }
        if (config.allowedEmails.size === 0) {
            response.status(503).json({
                error: 'AUTH_ALLOWED_EMAILS must be configured before using Google OAuth.',
            });
            return;
        }

        const nonce = randomBytes(16).toString('base64url');
        const signedState = createSignedOAuthState(nonce, config);
        const redirectUri = resolveGoogleRedirectUri(request, config.google.redirectUri);

        response.setHeader(
            'Set-Cookie',
            serializeCookie(OAUTH_STATE_COOKIE_NAME, signedState, {
                maxAgeSeconds: 600,
                httpOnly: true,
                sameSite: 'Lax',
                secure: isSecureRequest(request),
            }),
        );

        const params = new URLSearchParams({
            client_id: config.google.clientId,
            redirect_uri: redirectUri,
            response_type: 'code',
            scope: 'openid email profile',
            state: signedState,
            prompt: 'select_account',
        });

        response.redirect(
            `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`,
        );
    });

    router.get('/google/callback', async (request: Request, response: Response) => {
        if (!config.google) {
            response.redirect('/admin?authError=google_disabled');
            return;
        }

        const code = typeof request.query.code === 'string' ? request.query.code : '';
        const stateParam =
            typeof request.query.state === 'string' ? request.query.state : '';
        const cookies = parseCookies(request.header('cookie'));
        const stateCookie = cookies[OAUTH_STATE_COOKIE_NAME] ?? '';

        if (
            !code ||
            !stateParam ||
            stateParam !== stateCookie ||
            !verifySignedOAuthState(stateParam, config)
        ) {
            response.redirect('/admin?authError=invalid_state');
            return;
        }

        const redirectUri = resolveGoogleRedirectUri(
            request,
            config.google.redirectUri,
        );

        try {
            const tokenRes = await fetchImpl(
                'https://oauth2.googleapis.com/token',
                {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: new URLSearchParams({
                        code,
                        client_id: config.google.clientId,
                        client_secret: config.google.clientSecret,
                        redirect_uri: redirectUri,
                        grant_type: 'authorization_code',
                    }),
                    signal: AbortSignal.timeout(10_000),
                },
            );
            if (!tokenRes.ok) {
                response.redirect('/admin?authError=token_exchange');
                return;
            }
            const tokenPayload = (await tokenRes.json()) as {
                access_token?: unknown;
            };
            if (typeof tokenPayload.access_token !== 'string') {
                response.redirect('/admin?authError=token_exchange');
                return;
            }

            const userRes = await fetchImpl(
                'https://openidconnect.googleapis.com/v1/userinfo',
                {
                    headers: {
                        Authorization: `Bearer ${tokenPayload.access_token}`,
                    },
                    signal: AbortSignal.timeout(10_000),
                },
            );
            if (!userRes.ok) {
                response.redirect('/admin?authError=userinfo_failed');
                return;
            }
            const userInfo = (await userRes.json()) as {
                email?: unknown;
                email_verified?: unknown;
            };
            const email =
                typeof userInfo.email === 'string'
                    ? userInfo.email.trim().toLowerCase()
                    : '';
            if (
                !email ||
                userInfo.email_verified !== true ||
                !config.allowedEmails.has(email)
            ) {
                response.redirect('/admin?authError=unauthorized_email');
                return;
            }

            const sessionValue = createSessionCookieValue(
                { sub: email, method: 'google' },
                config,
            );
            const secure = isSecureRequest(request);
            response.setHeader('Set-Cookie', [
                serializeCookie(SESSION_COOKIE_NAME, sessionValue, {
                    maxAgeSeconds: config.sessionTtlSeconds,
                    httpOnly: true,
                    sameSite: 'Lax',
                    secure,
                }),
                serializeCookie(OAUTH_STATE_COOKIE_NAME, '', {
                    maxAgeSeconds: 0,
                    httpOnly: true,
                    sameSite: 'Lax',
                    secure,
                }),
            ]);
            response.redirect('/admin');
        } catch {
            response.redirect('/admin?authError=oauth_error');
        }
    });

    return router;
}

function resolveGoogleRedirectUri(
    request: Request,
    configuredRedirectUri: string | null,
): string {
    if (configuredRedirectUri) {
        return configuredRedirectUri;
    }
    const proto = isSecureRequest(request) ? 'https' : 'http';
    const host =
        request.header('x-forwarded-host') ||
        request.header('host') ||
        'localhost:3000';
    return `${proto}://${host}/api/auth/google/callback`;
}
