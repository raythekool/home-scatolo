import 'dotenv/config';

import cors from 'cors';
import express, { type Request, type Response } from 'express';

import { readFoundryConfig, recognizeWithFoundry } from './foundry_client.js';
import {
    parseRecognitionRequest,
    parseRecognitionResult,
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
    try {
        readFoundryConfig(process.env);
        response.json({ status: 'ok' });
    } catch (_) {
        response.status(503).json({ status: 'configuring' });
    }
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
    return parseRecognitionResult(await recognizeWithFoundry(request));
}