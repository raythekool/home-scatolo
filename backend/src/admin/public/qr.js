// Compact ISO/IEC 18004 QR Code (Byte mode, ECC Level L, Versions 1..6) SVG generator.
// Zero external dependencies; designed for container URLs up to 134 UTF-8 bytes.

const VERSION_SPECS = [
    null,
    { size: 21, dataCodewords: 19, ecCodewords: 7, blocks: 1, align: [] },
    { size: 25, dataCodewords: 34, ecCodewords: 10, blocks: 1, align: [6, 18] },
    { size: 29, dataCodewords: 55, ecCodewords: 15, blocks: 1, align: [6, 22] },
    { size: 33, dataCodewords: 80, ecCodewords: 20, blocks: 1, align: [6, 26] },
    { size: 37, dataCodewords: 108, ecCodewords: 26, blocks: 1, align: [6, 30] },
    { size: 41, dataCodewords: 136, ecCodewords: 18, blocks: 2, align: [6, 34] },
];

// Format info (ECC L = 01, mask 0..7) precomputed with BCH(15,5) and XOR 0x5412
const FORMAT_BITS_L = [
    0x77c4, 0x72f3, 0x7daa, 0x789d, 0x662f, 0x6318, 0x6c41, 0x6976,
];

const GF_EXP = new Uint8Array(512);
const GF_LOG = new Uint8Array(256);
(() => {
    let x = 1;
    for (let i = 0; i < 255; i++) {
        GF_EXP[i] = x;
        GF_LOG[x] = i;
        x <<= 1;
        if (x & 0x100) x ^= 0x11d;
    }
    for (let i = 255; i < 512; i++) {
        GF_EXP[i] = GF_EXP[i - 255];
    }
})();

function gfMul(a, b) {
    if (a === 0 || b === 0) return 0;
    return GF_EXP[GF_LOG[a] + GF_LOG[b]];
}

function rsGeneratorPoly(degree) {
    let poly = [1];
    for (let i = 0; i < degree; i++) {
        const next = new Array(poly.length + 1).fill(0);
        const factor = GF_EXP[i];
        for (let j = 0; j < poly.length; j++) {
            next[j] ^= poly[j];
            next[j + 1] ^= gfMul(poly[j], factor);
        }
        poly = next;
    }
    return poly;
}

function rsEncode(data, ecCount) {
    const gen = rsGeneratorPoly(ecCount);
    const buffer = new Uint8Array(data.length + ecCount);
    buffer.set(data, 0);
    for (let i = 0; i < data.length; i++) {
        const coef = buffer[i];
        if (coef !== 0) {
            for (let j = 1; j < gen.length; j++) {
                buffer[i + j] ^= gfMul(gen[j], coef);
            }
        }
    }
    return buffer.slice(data.length);
}

function encodeBytes(bytes) {
    let version = -1;
    for (let v = 1; v < VERSION_SPECS.length; v++) {
        const capacity = VERSION_SPECS[v].dataCodewords - 2;
        if (bytes.length <= capacity) {
            version = v;
            break;
        }
    }
    if (version === -1) {
        throw new Error('QR payload exceeds supported length (max 134 bytes).');
    }

    const spec = VERSION_SPECS[version];
    const bits = [];
    const pushBits = (val, len) => {
        for (let i = len - 1; i >= 0; i--) {
            bits.push((val >>> i) & 1);
        }
    };

    // Byte mode indicator (0100) + 8-bit character count (Versions 1..9)
    pushBits(0b0100, 4);
    pushBits(bytes.length, 8);
    for (const byte of bytes) {
        pushBits(byte, 8);
    }

    const totalDataBits = spec.dataCodewords * 8;
    const terminator = Math.min(4, totalDataBits - bits.length);
    for (let i = 0; i < terminator; i++) bits.push(0);
    while (bits.length % 8 !== 0) bits.push(0);

    const data = new Uint8Array(spec.dataCodewords);
    for (let i = 0; i < bits.length; i += 8) {
        let b = 0;
        for (let j = 0; j < 8; j++) b = (b << 1) | bits[i + j];
        data[i / 8] = b;
    }

    const padBytes = [0xec, 0x11];
    let padIndex = 0;
    for (let i = bits.length / 8; i < spec.dataCodewords; i++) {
        data[i] = padBytes[padIndex++ % 2];
    }

    // Split into blocks and interleave data + EC codewords
    const blockDataLen = Math.floor(spec.dataCodewords / spec.blocks);
    const dataBlocks = [];
    const ecBlocks = [];
    for (let b = 0; b < spec.blocks; b++) {
        const slice = data.slice(b * blockDataLen, (b + 1) * blockDataLen);
        dataBlocks.push(slice);
        ecBlocks.push(rsEncode(slice, spec.ecCodewords));
    }

    const codewords = [];
    for (let i = 0; i < blockDataLen; i++) {
        for (let b = 0; b < spec.blocks; b++) codewords.push(dataBlocks[b][i]);
    }
    for (let i = 0; i < spec.ecCodewords; i++) {
        for (let b = 0; b < spec.blocks; b++) codewords.push(ecBlocks[b][i]);
    }

    return { version, spec, codewords };
}

function buildMatrix(text) {
    const bytes = new TextEncoder().encode(text);
    const { version, spec, codewords } = encodeBytes(bytes);
    const n = spec.size;
    const modules = Array.from({ length: n }, () => new Uint8Array(n));
    const isFunc = Array.from({ length: n }, () => new Uint8Array(n));

    const setFunc = (r, c, dark) => {
        if (r < 0 || r >= n || c < 0 || c >= n) return;
        modules[r][c] = dark ? 1 : 0;
        isFunc[r][c] = 1;
    };

    const drawFinder = (top, left) => {
        for (let dr = -1; dr <= 7; dr++) {
            for (let dc = -1; dc <= 7; dc++) {
                const r = top + dr;
                const c = left + dc;
                if (r < 0 || r >= n || c < 0 || c >= n) continue;
                const inOuter =
                    dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6 &&
                    (dr === 0 || dr === 6 || dc === 0 || dc === 6);
                const inInner = dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4;
                setFunc(r, c, inOuter || inInner);
            }
        }
    };

    drawFinder(0, 0);
    drawFinder(0, n - 7);
    drawFinder(n - 7, 0);

    // Alignment patterns
    for (const r of spec.align) {
        for (const c of spec.align) {
            if (isFunc[r][c]) continue;
            for (let dr = -2; dr <= 2; dr++) {
                for (let dc = -2; dc <= 2; dc++) {
                    const dist = Math.max(Math.abs(dr), Math.abs(dc));
                    setFunc(r + dr, c + dc, dist === 2 || dist === 0);
                }
            }
        }
    }

    // Timing patterns
    for (let i = 8; i < n - 8; i++) {
        setFunc(6, i, i % 2 === 0);
        setFunc(i, 6, i % 2 === 0);
    }

    // Reserve format info areas + dark module
    for (let i = 0; i <= 8; i++) {
        if (i !== 6) {
            setFunc(8, i, false);
            setFunc(i, 8, false);
        }
    }
    for (let i = n - 8; i < n; i++) {
        setFunc(8, i, false);
        setFunc(i, 8, false);
    }
    setFunc(4 * version + 9, 8, true);

    // Place data bits in zig-zag columns
    let bitIndex = 0;
    const totalBits = codewords.length * 8;
    let upward = true;
    for (let right = n - 1; right >= 1; right -= 2) {
        if (right === 6) right = 5;
        for (let step = 0; step < n; step++) {
            const r = upward ? n - 1 - step : step;
            for (let dx = 0; dx < 2; dx++) {
                const c = right - dx;
                if (isFunc[r][c]) continue;
                let dark = 0;
                if (bitIndex < totalBits) {
                    dark = (codewords[bitIndex >>> 3] >>> (7 - (bitIndex & 7))) & 1;
                    bitIndex++;
                }
                modules[r][c] = dark;
            }
        }
        upward = !upward;
    }

    // Apply mask 0 ((r + c) % 2 === 0) and write format bits for ECC L + mask 0
    const maskId = 0;
    for (let r = 0; r < n; r++) {
        for (let c = 0; c < n; c++) {
            if (!isFunc[r][c] && (r + c) % 2 === 0) {
                modules[r][c] ^= 1;
            }
        }
    }

    const format = FORMAT_BITS_L[maskId];
    const fmtBit = (i) => (format >>> i) & 1;
    for (let i = 0; i <= 5; i++) modules[8][i] = fmtBit(14 - i);
    modules[8][7] = fmtBit(8);
    modules[8][8] = fmtBit(7);
    modules[7][8] = fmtBit(6);
    for (let i = 0; i <= 5; i++) modules[5 - i][8] = fmtBit(5 - i);

    for (let i = 0; i <= 7; i++) modules[8][n - 1 - i] = fmtBit(i);
    for (let i = 0; i <= 6; i++) modules[n - 1 - i][8] = fmtBit(14 - i);

    return modules;
}

export function renderQrSvgElement(text, { sizePx = 148, margin = 4 } = {}) {
    const matrix = buildMatrix(text);
    const n = matrix.length;
    const total = n + margin * 2;
    const paths = [];

    for (let r = 0; r < n; r++) {
        for (let c = 0; c < n; c++) {
            if (matrix[r][c]) {
                paths.push(`M${c + margin},${r + margin}h1v1h-1z`);
            }
        }
    }

    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', `0 0 ${total} ${total}`);
    svg.setAttribute('width', String(sizePx));
    svg.setAttribute('height', String(sizePx));
    svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', `Codice QR per ${text}`);
    svg.setAttribute('shape-rendering', 'crispEdges');

    const bg = document.createElementNS(ns, 'rect');
    bg.setAttribute('width', String(total));
    bg.setAttribute('height', String(total));
    bg.setAttribute('fill', '#ffffff');
    svg.appendChild(bg);

    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', paths.join(''));
    path.setAttribute('fill', '#123447');
    svg.appendChild(path);

    return svg;
}
