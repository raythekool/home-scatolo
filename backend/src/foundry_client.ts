import { DefaultAzureCredential } from '@azure/identity';

import { recognitionPrompt, type RecognitionRequest } from './recognition.js';

const cognitiveServicesScope = 'https://cognitiveservices.azure.com/.default';

interface FoundryConfig {
    endpoint: string;
    deployment: string;
    apiVersion: string;
}

const credential = new DefaultAzureCredential();

export async function recognizeWithFoundry(
    request: RecognitionRequest,
): Promise<unknown> {
    const token = await credential.getToken(cognitiveServicesScope);
    if (!token) {
        throw new Error('Azure AI Foundry authentication is unavailable.');
    }

    const foundryRequest = createFoundryRequest(
        request,
        readFoundryConfig(process.env),
        token.token,
    );
    const response = await fetch(foundryRequest.url, foundryRequest.init);
    if (!response.ok) {
        throw new Error(`Azure AI Foundry responded with ${response.status}.`);
    }

    const payload: unknown = await response.json();
    if (!isModelResponse(payload)) {
        throw new Error('Azure AI Foundry returned an invalid response.');
    }

    return JSON.parse(payload.choices[0].message.content);
}

export function readFoundryConfig(
    environment: NodeJS.ProcessEnv,
): FoundryConfig {
    const endpoint = environment.AZURE_OPENAI_ENDPOINT?.replace(/\/$/, '');
    const deployment = environment.AZURE_OPENAI_DEPLOYMENT;
    if (!endpoint || !deployment) {
        throw new Error(
            'AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT must be configured.',
        );
    }

    return {
        endpoint,
        deployment,
        apiVersion: environment.AZURE_OPENAI_API_VERSION ?? '2024-10-21',
    };
}

export function createFoundryRequest(
    request: RecognitionRequest,
    config: FoundryConfig,
    accessToken: string,
): { url: string; init: RequestInit } {
    const url = `${config.endpoint}/openai/deployments/${encodeURIComponent(config.deployment)}/chat/completions?api-version=${encodeURIComponent(config.apiVersion)}`;
    return {
        url,
        init: {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                response_format: { type: 'json_object' },
                messages: [
                    {
                        role: 'system',
                        content: 'You extract visible household inventory from images.',
                    },
                    {
                        role: 'user',
                        content: [
                            {
                                type: 'text',
                                text: recognitionPrompt(request.existingItems),
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

function isModelResponse(
    value: unknown,
): value is { choices: Array<{ message: { content: string } }> } {
    if (typeof value !== 'object' || value === null || !('choices' in value)) {
        return false;
    }
    const choices = value.choices;
    return (
        Array.isArray(choices) &&
        choices.length > 0 &&
        typeof choices[0] === 'object' &&
        choices[0] !== null &&
        'message' in choices[0] &&
        typeof choices[0].message === 'object' &&
        choices[0].message !== null &&
        'content' in choices[0].message &&
        typeof choices[0].message.content === 'string'
    );
}