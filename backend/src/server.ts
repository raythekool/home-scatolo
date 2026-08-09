import 'dotenv/config';

import cors from 'cors';
import express, { type Request, type Response } from 'express';

import {
    parseRecognitionRequest,
    parseRecognitionResult,
    recognitionPrompt,
    RecognitionValidationError,
    type RecognitionResult,
} from './recognition.js';

const app = express();
const port = Number(process.env.PORT ?? 3000);
const allowedOrigins = (process.env.ALLOWED_ORIGINS ?? 'http://localhost:8080,http://localhost:3000')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

app.use(cors({ origin: allowedOrigins }));
app.use(express.json({ limit: '7mb' }));

app.get('/health', (_request: Request, response: Response) => {
    response.json({ status: 'ok' });
});

app.post('/recognize', async (request: Request, response: Response) => {
    try {
        const recognitionRequest = parseRecognitionRequest(request.body);
        const result = await recognizeImage(recognitionRequest);
        response.json(result);
    } catch (error) {
        if (error instanceof RecognitionValidationError) {
            response.status(400).json({ error: error.message });
            return;
        }

        response.status(502).json({ error: 'Recognition is currently unavailable.' });
    }
});

app.listen(port, '0.0.0.0', () => {
    console.log(`Home Scatolo backend listening on port ${port}`);
});

async function recognizeImage(
    request: ReturnType<typeof parseRecognitionRequest>,
): Promise<RecognitionResult> {
    const token = process.env.GITHUB_MODELS_TOKEN;
    if (!token) {
        throw new Error('GITHUB_MODELS_TOKEN is not configured.');
    }

    const endpoint = process.env.GITHUB_MODELS_ENDPOINT ??
        'https://models.github.ai/inference/chat/completions';
    const model = process.env.MODEL_NAME ?? 'openai/gpt-4o';
    const modelResponse = await fetch(endpoint, {
        method: 'POST',
        headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            model,
            response_format: { type: 'json_object' },
            messages: [
                {
                    role: 'system',
                    content: 'You extract visible household inventory from images.',
                },
                {
                    role: 'user',
                    content: [
                        { type: 'text', text: recognitionPrompt(request.existingItems) },
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
    });

    if (!modelResponse.ok) {
        throw new Error(`GitHub Models responded with ${modelResponse.status}.`);
    }

    const payload: unknown = await modelResponse.json();
    if (!isModelResponse(payload)) {
        throw new RecognitionValidationError('The model returned an invalid response.');
    }
    return parseRecognitionResult(JSON.parse(payload.choices[0].message.content));
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