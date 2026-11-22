import { readFoundryConfig, recognizeWithFoundry } from '../foundry_client.js';
import {
    parseRecognitionResult,
    recognitionPrompt,
    type RecognitionRequest,
    type RecognitionResult,
} from '../recognition.js';

export type VisionProviderName =
    | 'github-models'
    | 'anthropic'
    | 'openai-compatible'
    | 'ollama'
    | 'azure-foundry';

export interface VisionProvider {
    readonly name: VisionProviderName;
    recognize(request: RecognitionRequest): Promise<unknown>;
}

export interface RecognitionOutcome {
    result: RecognitionResult;
    provider: VisionProviderName;
    usedFallback: boolean;
}

export interface VisionRuntimeSettings {
    primaryProvider?: string;
    fallbackProvider?: string;
    ollamaModel?: string;
    cloudTimeoutMs?: string;
    ollamaTimeoutMs?: string;
    promptTemplate?: string;
}

export interface OllamaModelInfo {
    name: string;
    size: number;
    modifiedAt: string;
}

const DEFAULT_SYSTEM_PROMPT =
    'You extract visible household inventory from images.';
const DEFAULT_CLOUD_TIMEOUT_MS = 30_000;
const DEFAULT_OLLAMA_TIMEOUT_MS = 90_000;

export function buildEffectivePrompt(
    existingItems: RecognitionRequest['existingItems'],
    customTemplate?: string,
): string {
    const trimmed = customTemplate?.trim();
    if (!trimmed) {
        return recognitionPrompt(existingItems);
    }
    const serialized = JSON.stringify(existingItems);
    if (trimmed.includes('{{existingItems}}')) {
        return trimmed.replaceAll('{{existingItems}}', serialized);
    }
    return `${trimmed}\nInventario esistente del contenitore:\n${serialized}`;
}

export function mergeVisionEnvironment(
    environment: NodeJS.ProcessEnv,
    settings: Record<string, string>,
): { env: NodeJS.ProcessEnv; promptTemplate?: string } {
    const merged: NodeJS.ProcessEnv = { ...environment };
    if (settings['ai.primaryProvider']?.trim()) {
        merged.AI_PRIMARY_PROVIDER = settings['ai.primaryProvider'].trim();
    }
    if (settings['ai.fallbackProvider']?.trim()) {
        merged.AI_FALLBACK_PROVIDER = settings['ai.fallbackProvider'].trim();
    }
    if (settings['ai.ollamaModel']?.trim()) {
        merged.OLLAMA_MODEL = settings['ai.ollamaModel'].trim();
    }
    if (settings['ai.cloudTimeoutMs']?.trim()) {
        merged.AI_TIMEOUT_MS = settings['ai.cloudTimeoutMs'].trim();
    }
    if (settings['ai.ollamaTimeoutMs']?.trim()) {
        merged.OLLAMA_TIMEOUT_MS = settings['ai.ollamaTimeoutMs'].trim();
    }
    const promptTemplate = settings['ai.promptTemplate']?.trim() || undefined;
    return { env: merged, promptTemplate };
}

export async function listOllamaModels(
    environment: NodeJS.ProcessEnv,
    fetchImpl: typeof fetch = fetch,
): Promise<{ online: boolean; baseUrl: string; models: OllamaModelInfo[]; error?: string }> {
    const baseUrl = (
        environment.OLLAMA_BASE_URL?.trim() ||
        'http://host.docker.internal:11434'
    ).replace(/\/$/, '');

    try {
        const response = await fetchImpl(`${baseUrl}/api/tags`, {
            signal: AbortSignal.timeout(5_000),
        });
        if (!response.ok) {
            return {
                online: false,
                baseUrl,
                models: [],
                error: `HTTP ${response.status}`,
            };
        }
        const payload = (await response.json()) as {
            models?: Array<{
                name?: unknown;
                size?: unknown;
                modified_at?: unknown;
            }>;
        };
        const models: OllamaModelInfo[] = (payload.models ?? [])
            .filter(
                (entry): entry is { name: string; size?: number; modified_at?: string } =>
                    typeof entry?.name === 'string',
            )
            .map((entry) => ({
                name: entry.name,
                size: typeof entry.size === 'number' ? entry.size : 0,
                modifiedAt:
                    typeof entry.modified_at === 'string'
                        ? entry.modified_at
                        : '',
            }));
        return { online: true, baseUrl, models };
    } catch (error) {
        return {
            online: false,
            baseUrl,
            models: [],
            error: error instanceof Error ? error.message : 'Unreachable',
        };
    }
}

export function extractJsonObject(rawText: string): unknown {
    const trimmed = rawText.trim();
    const fenceMatch = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(trimmed);
    const candidate = fenceMatch ? fenceMatch[1].trim() : trimmed;
    try {
        return JSON.parse(candidate);
    } catch {
        const firstBrace = candidate.indexOf('{');
        const lastBrace = candidate.lastIndexOf('}');
        if (firstBrace !== -1 && lastBrace > firstBrace) {
            return JSON.parse(candidate.slice(firstBrace, lastBrace + 1));
        }
        throw new Error('Model response did not contain valid JSON.');
    }
}

export function createGitHubModelsRequest(
    request: RecognitionRequest,
    config: { endpoint: string; model: string; token: string; promptTemplate?: string },
): { url: string; init: RequestInit } {
    return {
        url: config.endpoint,
        init: {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${config.token}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: config.model,
                response_format: { type: 'json_object' },
                messages: [
                    {
                        role: 'system',
                        content: DEFAULT_SYSTEM_PROMPT,
                    },
                    {
                        role: 'user',
                        content: [
                            {
                                type: 'text',
                                text: buildEffectivePrompt(
                                    request.existingItems,
                                    config.promptTemplate,
                                ),
                            },
                            {
                                type: 'image_url',
                                image_url: {
                                    url: `data:${request.mimeType};base64,${request.imageBase64}`,
                                },
                            },
                        ],
                    },
                ],
            }),
        },
    };
}

export function createAnthropicRequest(
    request: RecognitionRequest,
    config: { baseUrl: string; model: string; apiKey: string; promptTemplate?: string },
): { url: string; init: RequestInit } {
    const normalizedBase = config.baseUrl.replace(/\/$/, '');
    return {
        url: `${normalizedBase}/v1/messages`,
        init: {
            method: 'POST',
            headers: {
                'x-api-key': config.apiKey,
                'anthropic-version': '2023-06-01',
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: config.model,
                max_tokens: 1500,
                system: DEFAULT_SYSTEM_PROMPT,
                messages: [
                    {
                        role: 'user',
                        content: [
                            {
                                type: 'image',
                                source: {
                                    type: 'base64',
                                    media_type: request.mimeType,
                                    data: request.imageBase64,
                                },
                            },
                            {
                                type: 'text',
                                text: buildEffectivePrompt(
                                    request.existingItems,
                                    config.promptTemplate,
                                ),
                            },
                        ],
                    },
                ],
            }),
        },
    };
}

export function createOllamaRequest(
    request: RecognitionRequest,
    config: { baseUrl: string; model: string; promptTemplate?: string },
): { url: string; init: RequestInit } {
    const normalizedBase = config.baseUrl.replace(/\/$/, '');
    return {
        url: `${normalizedBase}/api/chat`,
        init: {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                model: config.model,
                stream: false,
                format: 'json',
                messages: [
                    {
                        role: 'system',
                        content: DEFAULT_SYSTEM_PROMPT,
                    },
                    {
                        role: 'user',
                        content: buildEffectivePrompt(
                            request.existingItems,
                            config.promptTemplate,
                        ),
                        images: [request.imageBase64],
                    },
                ],
            }),
        },
    };
}

export function createProviderByName(
    name: VisionProviderName,
    environment: NodeJS.ProcessEnv,
    fetchImpl: typeof fetch = fetch,
    promptTemplate?: string,
): VisionProvider {
    const cloudTimeoutMs = parsePositiveInt(
        environment.AI_TIMEOUT_MS,
        DEFAULT_CLOUD_TIMEOUT_MS,
    );
    const ollamaTimeoutMs = parsePositiveInt(
        environment.OLLAMA_TIMEOUT_MS,
        DEFAULT_OLLAMA_TIMEOUT_MS,
    );

    switch (name) {
        case 'github-models': {
            const token = environment.GITHUB_MODELS_TOKEN?.trim();
            if (!token) {
                throw new Error('GITHUB_MODELS_TOKEN must be configured.');
            }
            const endpoint =
                environment.GITHUB_MODELS_ENDPOINT?.trim() ||
                'https://models.github.ai/inference/chat/completions';
            const model =
                environment.GITHUB_MODELS_MODEL?.trim() ||
                environment.MODEL_NAME?.trim() ||
                'openai/gpt-4o';

            return {
                name: 'github-models',
                async recognize(request: RecognitionRequest): Promise<unknown> {
                    const req = createGitHubModelsRequest(request, {
                        endpoint,
                        model,
                        token,
                        promptTemplate,
                    });
                    const response = await fetchWithTimeout(
                        fetchImpl,
                        req.url,
                        req.init,
                        cloudTimeoutMs,
                    );
                    if (!response.ok) {
                        throw new Error(`GitHub Models responded with ${response.status}.`);
                    }
                    const payload: unknown = await response.json();
                    const content = extractOpenAIChatContent(payload);
                    return extractJsonObject(content);
                },
            };
        }

        case 'openai-compatible': {
            const baseUrl = environment.OPENAI_BASE_URL?.trim().replace(/\/$/, '');
            const apiKey = environment.OPENAI_API_KEY?.trim();
            const model = environment.OPENAI_MODEL?.trim();
            if (!baseUrl || !apiKey || !model) {
                throw new Error(
                    'OPENAI_BASE_URL, OPENAI_API_KEY, and OPENAI_MODEL must be configured.',
                );
            }
            const endpoint = baseUrl.endsWith('/chat/completions')
                ? baseUrl
                : `${baseUrl}/chat/completions`;

            return {
                name: 'openai-compatible',
                async recognize(request: RecognitionRequest): Promise<unknown> {
                    const req = createGitHubModelsRequest(request, {
                        endpoint,
                        model,
                        token: apiKey,
                        promptTemplate,
                    });
                    const response = await fetchWithTimeout(
                        fetchImpl,
                        req.url,
                        req.init,
                        cloudTimeoutMs,
                    );
                    if (!response.ok) {
                        throw new Error(
                            `OpenAI-compatible provider responded with ${response.status}.`,
                        );
                    }
                    const payload: unknown = await response.json();
                    const content = extractOpenAIChatContent(payload);
                    return extractJsonObject(content);
                },
            };
        }

        case 'anthropic': {
            const apiKey = environment.ANTHROPIC_API_KEY?.trim();
            if (!apiKey) {
                throw new Error('ANTHROPIC_API_KEY must be configured.');
            }
            const baseUrl =
                environment.ANTHROPIC_BASE_URL?.trim() || 'https://api.anthropic.com';
            const model =
                environment.ANTHROPIC_MODEL?.trim() || 'claude-sonnet-4-5';

            return {
                name: 'anthropic',
                async recognize(request: RecognitionRequest): Promise<unknown> {
                    const req = createAnthropicRequest(request, {
                        baseUrl,
                        model,
                        apiKey,
                        promptTemplate,
                    });
                    const response = await fetchWithTimeout(
                        fetchImpl,
                        req.url,
                        req.init,
                        cloudTimeoutMs,
                    );
                    if (!response.ok) {
                        throw new Error(`Anthropic responded with ${response.status}.`);
                    }
                    const payload: unknown = await response.json();
                    const content = extractAnthropicContent(payload);
                    return extractJsonObject(content);
                },
            };
        }

        case 'ollama': {
            const baseUrl =
                environment.OLLAMA_BASE_URL?.trim() ||
                'http://host.docker.internal:11434';
            const model = environment.OLLAMA_MODEL?.trim() || 'qwen2.5vl:3b';

            return {
                name: 'ollama',
                async recognize(request: RecognitionRequest): Promise<unknown> {
                    const req = createOllamaRequest(request, {
                        baseUrl,
                        model,
                        promptTemplate,
                    });
                    const response = await fetchWithTimeout(
                        fetchImpl,
                        req.url,
                        req.init,
                        ollamaTimeoutMs,
                    );
                    if (!response.ok) {
                        throw new Error(`Ollama responded with ${response.status}.`);
                    }
                    const payload: unknown = await response.json();
                    const content = extractOllamaContent(payload);
                    return extractJsonObject(content);
                },
            };
        }

        case 'azure-foundry': {
            readFoundryConfig(environment);
            return {
                name: 'azure-foundry',
                recognize: (request: RecognitionRequest) => recognizeWithFoundry(request),
            };
        }
    }
}

export function resolveVisionProviders(
    environment: NodeJS.ProcessEnv,
    fetchImpl: typeof fetch = fetch,
    promptTemplate?: string,
): VisionProvider[] {
    const names: VisionProviderName[] = [];

    const explicitPrimaryRaw = environment.AI_PRIMARY_PROVIDER?.trim().toLowerCase();
    const explicitPrimary = parseProviderName(explicitPrimaryRaw);
    if (explicitPrimary) {
        names.push(explicitPrimary);
    } else if (explicitPrimaryRaw !== 'none') {
        const autoPrimary = detectPrimaryProvider(environment);
        if (autoPrimary) {
            names.push(autoPrimary);
        }
    }

    const explicitFallback = parseProviderName(environment.AI_FALLBACK_PROVIDER);
    if (explicitFallback && !names.includes(explicitFallback)) {
        names.push(explicitFallback);
    } else if (
        !explicitFallback &&
        environment.AI_FALLBACK_PROVIDER?.trim().toLowerCase() !== 'none' &&
        !names.includes('ollama') &&
        (Boolean(environment.OLLAMA_BASE_URL?.trim()) ||
            Boolean(environment.OLLAMA_MODEL?.trim()))
    ) {
        names.push('ollama');
    }

    const providers: VisionProvider[] = [];
    for (const name of names) {
        try {
            providers.push(
                createProviderByName(name, environment, fetchImpl, promptTemplate),
            );
        } catch {
            // Skip misconfigured provider so fallback or health reporting handles it gracefully.
        }
    }

    return providers;
}

export async function recognizeWithFallback(
    request: RecognitionRequest,
    providers: readonly VisionProvider[],
    onProviderError?: (provider: VisionProviderName, error: unknown) => void,
): Promise<RecognitionOutcome> {
    if (providers.length === 0) {
        throw new Error('No vision provider is configured.');
    }

    let lastError: unknown;
    for (let index = 0; index < providers.length; index++) {
        const provider = providers[index];
        try {
            const raw = await provider.recognize(request);
            const result = parseRecognitionResult(raw);
            return {
                result,
                provider: provider.name,
                usedFallback: index > 0,
            };
        } catch (error) {
            lastError = error;
            onProviderError?.(provider.name, error);
        }
    }

    throw new VisionUpstreamError(
        lastError instanceof Error
            ? lastError.message
            : 'All vision providers failed.',
    );
}

export class VisionUpstreamError extends Error {
    constructor(message: string) {
        super(message);
        this.name = 'VisionUpstreamError';
    }
}

function detectPrimaryProvider(
    environment: NodeJS.ProcessEnv,
): VisionProviderName | null {
    if (environment.GITHUB_MODELS_TOKEN?.trim()) {
        return 'github-models';
    }
    if (environment.ANTHROPIC_API_KEY?.trim()) {
        return 'anthropic';
    }
    if (
        environment.AZURE_OPENAI_ENDPOINT?.trim() &&
        environment.AZURE_OPENAI_DEPLOYMENT?.trim()
    ) {
        return 'azure-foundry';
    }
    if (
        environment.OPENAI_BASE_URL?.trim() &&
        environment.OPENAI_API_KEY?.trim() &&
        environment.OPENAI_MODEL?.trim()
    ) {
        return 'openai-compatible';
    }
    if (environment.OLLAMA_BASE_URL?.trim() || environment.OLLAMA_MODEL?.trim()) {
        return 'ollama';
    }
    return null;
}

function parseProviderName(value: string | undefined): VisionProviderName | null {
    const normalized = value?.trim().toLowerCase();
    switch (normalized) {
        case 'github-models':
        case 'anthropic':
        case 'openai-compatible':
        case 'ollama':
        case 'azure-foundry':
            return normalized;
        default:
            return null;
    }
}

function parsePositiveInt(value: string | undefined, fallback: number): number {
    if (!value) return fallback;
    const parsed = Number.parseInt(value, 10);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

async function fetchWithTimeout(
    fetchImpl: typeof fetch,
    url: string,
    init: RequestInit,
    timeoutMs: number,
): Promise<Response> {
    return fetchImpl(url, {
        ...init,
        signal: AbortSignal.timeout(timeoutMs),
    });
}

function extractOpenAIChatContent(payload: unknown): string {
    if (
        typeof payload === 'object' &&
        payload !== null &&
        'choices' in payload &&
        Array.isArray(payload.choices) &&
        payload.choices.length > 0
    ) {
        const first = payload.choices[0] as unknown;
        if (
            typeof first === 'object' &&
            first !== null &&
            'message' in first &&
            typeof first.message === 'object' &&
            first.message !== null &&
            'content' in first.message &&
            typeof first.message.content === 'string'
        ) {
            return first.message.content;
        }
    }
    throw new Error('OpenAI-compatible response had no message content.');
}

function extractAnthropicContent(payload: unknown): string {
    if (
        typeof payload === 'object' &&
        payload !== null &&
        'content' in payload &&
        Array.isArray(payload.content)
    ) {
        const textBlocks = payload.content
            .filter(
                (block): block is { type: string; text: string } =>
                    typeof block === 'object' &&
                    block !== null &&
                    'type' in block &&
                    block.type === 'text' &&
                    'text' in block &&
                    typeof block.text === 'string',
            )
            .map((block) => block.text);
        if (textBlocks.length > 0) {
            return textBlocks.join('\n');
        }
    }
    throw new Error('Anthropic response had no text content.');
}

function extractOllamaContent(payload: unknown): string {
    if (
        typeof payload === 'object' &&
        payload !== null &&
        'message' in payload &&
        typeof payload.message === 'object' &&
        payload.message !== null &&
        'content' in payload.message &&
        typeof payload.message.content === 'string'
    ) {
        return payload.message.content;
    }
    throw new Error('Ollama response had no message content.');
}
