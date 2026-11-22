import 'dotenv/config';

import { createApp } from './app.js';
import { InventoryDatabase } from './db.js';
import { resolveVisionProviders } from './vision/providers.js';

const port = Number(process.env.PORT ?? 3000);
const dbPath = process.env.DB_PATH?.trim() || './data/inventory.db';

const db = new InventoryDatabase(dbPath);
const app = createApp({ db, environment: process.env });

const server = app.listen(port, '0.0.0.0', () => {
    const providers = resolveVisionProviders(process.env).map((p) => p.name);
    console.log(
        `Home Scatolo backend listening on port ${port} (db: ${dbPath}, vision providers: ${providers.join(' -> ') || 'none'})`,
    );
});

function shutdown(signal: string): void {
    console.log(`Received ${signal}, closing Home Scatolo backend...`);
    server.close(() => {
        db.close();
        process.exit(0);
    });
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
