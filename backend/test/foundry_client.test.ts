import assert from 'node:assert/strict';
import test from 'node:test';

import {
    createFoundryRequest,
    readFoundryConfig,
} from '../src/foundry_client.js';

const request = {
    imageBase64: 'aGVsbG8=',
    mimeType: 'image/jpeg' as const,
    existingItems: [],
};

test('creates an Azure OpenAI request with a bearer token and image data URL', () => {
    const foundryRequest = createFoundryRequest(
        request,
        {
            endpoint: 'https://home-scatolo.openai.azure.com',
            deployment: 'home-scatolo-vision',
            apiVersion: '2024-10-21',
        },
        'access-token',
    );

    assert.equal(
        foundryRequest.url,
        'https://home-scatolo.openai.azure.com/openai/deployments/home-scatolo-vision/chat/completions?api-version=2024-10-21',
    );
    assert.deepEqual(foundryRequest.init.headers, {
        Authorization: 'Bearer access-token',
        'Content-Type': 'application/json',
    });

    const body = JSON.parse(foundryRequest.init.body as string) as {
        response_format: { type: string };
        messages: Array<{ content: unknown }>;
    };
    assert.equal(body.response_format.type, 'json_object');
    assert.match(JSON.stringify(body.messages), /data:image\/jpeg;base64,aGVsbG8=/);
});

test('requires Azure OpenAI endpoint and deployment configuration', () => {
    assert.throws(
        () => readFoundryConfig({}),
        /AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT/,
    );
});