import assert from 'node:assert/strict';
import test from 'node:test';

import {
    createAnthropicRequest,
    createGitHubModelsRequest,
    createOllamaRequest,
    extractJsonObject,
    recognizeWithFallback,
    resolveVisionProviders,
    type VisionProvider,
} from '../src/vision/providers.js';

const sampleRequest = {
    imageBase64: 'aGVsbG8=',
    mimeType: 'image/jpeg' as const,
    existingItems: [{ id: 1, name: 'Trapano', category: 'Attrezzi', quantity: 1 }],
};

test('builds GitHub Models, Anthropic, and Ollama vision requests', () => {
    const gh = createGitHubModelsRequest(sampleRequest, {
        endpoint: 'https://models.github.ai/inference/chat/completions',
        model: 'openai/gpt-4o',
        token: 'gh-token',
    });
    assert.equal(gh.url, 'https://models.github.ai/inference/chat/completions');
    assert.match(String(gh.init.body), /data:image\/jpeg;base64,aGVsbG8=/);

    const claude = createAnthropicRequest(sampleRequest, {
        baseUrl: 'https://api.anthropic.com/',
        model: 'claude-sonnet-4-5',
        apiKey: 'sk-ant-test',
    });
    assert.equal(claude.url, 'https://api.anthropic.com/v1/messages');
    const claudeBody = JSON.parse(String(claude.init.body)) as {
        messages: Array<{ content: Array<{ type: string; source?: { data: string } }> }>;
    };
    assert.equal(claudeBody.messages[0]?.content[0]?.type, 'image');
    assert.equal(claudeBody.messages[0]?.content[0]?.source?.data, 'aGVsbG8=');

    const ollama = createOllamaRequest(sampleRequest, {
        baseUrl: 'http://ollama:11434/',
        model: 'qwen2.5vl:3b',
    });
    assert.equal(ollama.url, 'http://ollama:11434/api/chat');
    const ollamaBody = JSON.parse(String(ollama.init.body)) as {
        model: string;
        stream: boolean;
        format: string;
        messages: Array<{ images?: string[] }>;
    };
    assert.equal(ollamaBody.model, 'qwen2.5vl:3b');
    assert.equal(ollamaBody.stream, false);
    assert.equal(ollamaBody.format, 'json');
    assert.deepEqual(ollamaBody.messages[1]?.images, ['aGVsbG8=']);
});

test('extractJsonObject parses plain JSON and fenced JSON blocks', () => {
    assert.deepEqual(extractJsonObject('{"items":[]}'), { items: [] });
    assert.deepEqual(
        extractJsonObject('```json\n{"items":[{"name":"Libro"}]}\n```'),
        { items: [{ name: 'Libro' }] },
    );
    assert.deepEqual(
        extractJsonObject('Ecco il risultato:\n{"items":[]}\nFine.'),
        { items: [] },
    );
});

test('auto-resolves cloud primary with Ollama local fallback', () => {
    const providers = resolveVisionProviders({
        GITHUB_MODELS_TOKEN: 'test-token',
        OLLAMA_BASE_URL: 'http://ollama:11434',
        OLLAMA_MODEL: 'qwen2.5vl:3b',
    });

    assert.deepEqual(
        providers.map((provider) => provider.name),
        ['github-models', 'ollama'],
    );

    const disabled = resolveVisionProviders({
        AI_PRIMARY_PROVIDER: 'none',
        AI_FALLBACK_PROVIDER: 'none',
        GITHUB_MODELS_TOKEN: 'test-token',
        OLLAMA_BASE_URL: 'http://ollama:11434',
    });
    assert.deepEqual(disabled, []);
});

test('falls back to secondary provider when primary fails or returns invalid schema', async () => {
    const primary: VisionProvider = {
        name: 'github-models',
        async recognize() {
            throw new Error('429 rate limited');
        },
    };
    const fallback: VisionProvider = {
        name: 'ollama',
        async recognize() {
            return {
                items: [
                    {
                        name: 'Martello',
                        category: 'Attrezzi',
                        shortDescription: 'Manico in legno',
                        quantity: 1,
                        confidence: 0.85,
                    },
                ],
            };
        },
    };

    const failedProviders: string[] = [];
    const outcome = await recognizeWithFallback(
        sampleRequest,
        [primary, fallback],
        (providerName) => failedProviders.push(providerName),
    );

    assert.deepEqual(failedProviders, ['github-models']);
    assert.equal(outcome.provider, 'ollama');
    assert.equal(outcome.usedFallback, true);
    assert.equal(outcome.result.items[0]?.name, 'Martello');
});

test('executes GitHub Models and falls back to Ollama over HTTP fetch', async () => {
    const calls: string[] = [];
    const mockFetch: typeof fetch = async (input) => {
        const url = String(input);
        calls.push(url);
        if (url.includes('models.github.ai')) {
            return new Response('rate limit', { status: 429 });
        }
        return new Response(
            JSON.stringify({
                message: {
                    content:
                        '```json\n{"items":[{"name":"Lampadina LED","category":"Casa","shortDescription":"E27 luce calda","quantity":2,"confidence":0.92}]}\n```',
                },
            }),
            { status: 200, headers: { 'Content-Type': 'application/json' } },
        );
    };

    const providers = resolveVisionProviders(
        {
            GITHUB_MODELS_TOKEN: 'gh-test-token',
            OLLAMA_BASE_URL: 'http://ollama:11434',
            OLLAMA_MODEL: 'qwen2.5vl:3b',
        },
        mockFetch,
    );

    const outcome = await recognizeWithFallback(sampleRequest, providers);
    assert.equal(calls.length, 2);
    assert.match(calls[0] ?? '', /models\.github\.ai/);
    assert.match(calls[1] ?? '', /ollama:11434\/api\/chat/);
    assert.equal(outcome.provider, 'ollama');
    assert.equal(outcome.usedFallback, true);
    assert.equal(outcome.result.items[0]?.name, 'Lampadina LED');
    assert.equal(outcome.result.items[0]?.quantity, 2);
});
