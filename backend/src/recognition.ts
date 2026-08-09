export interface InventoryItemSummary {
    id: number;
    name: string;
    category: string;
    quantity: number;
}

export interface RecognitionRequest {
    imageBase64: string;
    mimeType: 'image/jpeg' | 'image/png' | 'image/webp';
    existingItems: InventoryItemSummary[];
}

export interface RecognitionCandidate {
    name: string;
    category: string;
    shortDescription: string;
    quantity: number;
    confidence: number;
}

export interface RecognitionResult {
    items: RecognitionCandidate[];
}

const maxImageBytes = 5 * 1024 * 1024;
const supportedMimeTypes = new Set<RecognitionRequest['mimeType']>([
    'image/jpeg',
    'image/png',
    'image/webp',
]);

export function parseRecognitionRequest(value: unknown): RecognitionRequest {
    if (!isRecord(value)) {
        throw new RecognitionValidationError('The request body must be an object.');
    }

    const { imageBase64, mimeType, existingItems } = value;
    if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
        throw new RecognitionValidationError('imageBase64 must be a non-empty string.');
    }
    if (typeof mimeType !== 'string' || !supportedMimeTypes.has(mimeType as RecognitionRequest['mimeType'])) {
        throw new RecognitionValidationError('Unsupported image MIME type.');
    }
    if (!Array.isArray(existingItems) || !existingItems.every(isInventoryItemSummary)) {
        throw new RecognitionValidationError('existingItems must contain valid inventory summaries.');
    }

    const imageBytes = Buffer.byteLength(imageBase64, 'base64');
    if (imageBytes > maxImageBytes) {
        throw new RecognitionValidationError('The image exceeds the 5 MB limit.');
    }

    return {
        imageBase64,
        mimeType: mimeType as RecognitionRequest['mimeType'],
        existingItems,
    };
}

export function parseRecognitionResult(value: unknown): RecognitionResult {
    if (!isRecord(value) || !Array.isArray(value.items)) {
        throw new RecognitionValidationError('The model response has no items array.');
    }
    if (!value.items.every(isRecognitionCandidate)) {
        throw new RecognitionValidationError('The model response contains an invalid item.');
    }
    return { items: value.items };
}

export function recognitionPrompt(existingItems: InventoryItemSummary[]): string {
    return `
Analizza soltanto gli oggetti chiaramente visibili nell'immagine.
Consolida copie indistinguibili dello stesso oggetto in un unico elemento con quantity maggiore di zero.
Non inventare contenuti non visibili. L'inventario esistente del contenitore e':
${JSON.stringify(existingItems)}
Rispondi esclusivamente con JSON valido nel formato:
{"items":[{"name":"string","category":"string","shortDescription":"string","quantity":1,"confidence":0.0}]}
confidence deve essere compreso tra 0 e 1.
`;
}

export class RecognitionValidationError extends Error { }

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

function isInventoryItemSummary(value: unknown): value is InventoryItemSummary {
    return (
        isRecord(value) &&
        typeof value.id === 'number' &&
        typeof value.name === 'string' &&
        typeof value.category === 'string' &&
        typeof value.quantity === 'number' &&
        value.quantity > 0
    );
}

function isRecognitionCandidate(value: unknown): value is RecognitionCandidate {
    return (
        isRecord(value) &&
        typeof value.name === 'string' &&
        typeof value.category === 'string' &&
        typeof value.shortDescription === 'string' &&
        typeof value.quantity === 'number' &&
        value.quantity > 0 &&
        typeof value.confidence === 'number' &&
        value.confidence >= 0 &&
        value.confidence <= 1
    );
}