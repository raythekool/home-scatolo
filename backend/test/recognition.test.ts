import assert from 'node:assert/strict';
import test from 'node:test';

import {
    parseRecognitionRequest,
    parseRecognitionResult,
    RecognitionValidationError,
} from '../src/recognition.js';

test('accepts a supported image and inventory summary', () => {
    const request = parseRecognitionRequest({
        imageBase64: Buffer.from('fixture').toString('base64'),
        mimeType: 'image/jpeg',
        existingItems: [
            { id: 1, name: 'Libro', category: 'Libri', quantity: 2 },
        ],
    });

    assert.equal(request.existingItems[0]?.name, 'Libro');
});

test('rejects unsupported image types', () => {
    assert.throws(
        () => parseRecognitionRequest({
            imageBase64: 'Zm9v',
            mimeType: 'image/gif',
            existingItems: [],
        }),
        RecognitionValidationError,
    );
});

test('rejects invalid inventory quantities', () => {
    assert.throws(
        () => parseRecognitionRequest({
            imageBase64: 'Zm9v',
            mimeType: 'image/png',
            existingItems: [
                { id: 1, name: 'Libro', category: 'Libri', quantity: 0 },
            ],
        }),
        RecognitionValidationError,
    );
});

test('accepts a structured model response', () => {
    const result = parseRecognitionResult({
        items: [
            {
                name: 'Libro',
                category: 'Libri',
                shortDescription: 'Copertina blu',
                quantity: 2,
                confidence: 0.9,
            },
        ],
    });

    assert.equal(result.items[0]?.quantity, 2);
});