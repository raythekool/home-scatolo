import assert from 'node:assert/strict';
import test from 'node:test';

import {
    InventoryDatabase,
    InventoryNotFoundError,
    InventoryValidationError,
} from '../src/db.js';

test('manages full House -> Room -> Container -> Item hierarchy and cascade delete', () => {
    const db = new InventoryDatabase(':memory:');
    try {
        const house = db.createHouse('Casa Vaiano');
        const room = db.createRoom({ name: 'Cantina', houseId: house.id });
        const container = db.createContainer({
            name: 'Scatolone Cavi',
            type: 'scatolone',
            roomId: room.id,
            notes: 'Ripiano alto',
        });
        const item = db.createItem({
            name: 'Cavo HDMI 2m',
            category: 'Elettronica',
            shortDescription: 'Cavo nero intrecciato',
            containerId: container.id,
            quantity: 2,
        });

        assert.equal(db.listHouses().length, 1);
        assert.equal(db.listRooms(house.id).length, 1);
        assert.equal(db.listContainers(room.id).length, 1);
        assert.equal(db.listItems(container.id).length, 1);

        const enriched = db.getItem(item.id);
        assert.ok(enriched);
        assert.equal(enriched.houseName, 'Casa Vaiano');
        assert.equal(enriched.roomName, 'Cantina');
        assert.equal(enriched.containerName, 'Scatolone Cavi');
        assert.equal(enriched.quantity, 2);

        const incremented = db.incrementItemQuantity(item.id, 3);
        assert.equal(incremented.quantity, 5);

        const secondContainer = db.createContainer({
            name: 'Armadio Studio',
            type: 'armadio',
            roomId: room.id,
        });
        const moved = db.updateItem(item.id, {
            containerId: secondContainer.id,
            notes: 'Spostato dopo riordino',
        });
        assert.equal(moved.containerId, secondContainer.id);
        assert.equal(moved.containerName, 'Armadio Studio');
        assert.equal(moved.notes, 'Spostato dopo riordino');

        db.deleteHouse(house.id);
        assert.equal(db.listHouses().length, 0);
        assert.equal(db.listRooms().length, 0);
        assert.equal(db.listContainers().length, 0);
        assert.equal(db.listItems().length, 0);
    } finally {
        db.close();
    }
});

test('getOrCreateQuickScanContainer creates defaults once and reuses them', () => {
    const db = new InventoryDatabase(':memory:');
    try {
        const first = db.getOrCreateQuickScanContainer();
        const second = db.getOrCreateQuickScanContainer();

        assert.deepEqual(second, first);
        assert.equal(db.listHouses()[0]?.name, 'La mia casa');
        assert.equal(db.listRooms(first.houseId)[0]?.name, 'Ingresso');
        assert.equal(db.listContainers(first.roomId)[0]?.name, 'Da ordinare');
        assert.equal(db.getState('activeHouseId'), String(first.houseId));
    } finally {
        db.close();
    }
});

test('searches items with FTS5, diacritics folding, location path, and filters', () => {
    const db = new InventoryDatabase(':memory:');
    try {
        const vaiano = db.createHouse('Casa Vaiano');
        const mare = db.createHouse('Casa Mare');
        const garage = db.createRoom({ name: 'Garage', houseId: vaiano.id });
        const sala = db.createRoom({ name: 'Sala', houseId: mare.id });
        const scaffale = db.createContainer({
            name: 'Scaffale Attrezzi',
            type: 'libreria',
            roomId: garage.id,
        });
        const cassetto = db.createContainer({
            name: 'Cassetto TV',
            type: 'cassetto',
            roomId: sala.id,
        });

        db.createItem({
            name: 'Cacciavite a stella',
            category: 'Attrezzi',
            shortDescription: 'Impugnatura gommata',
            notes: 'Usato per mobili cucina',
            containerId: scaffale.id,
        });
        db.createItem({
            name: 'Caffè macinato',
            category: 'Dispensa',
            shortDescription: 'Latta da 250g',
            containerId: cassetto.id,
        });

        const byAccentFold = db.searchItems({ q: 'caffe' });
        assert.equal(byAccentFold.length, 1);
        assert.equal(byAccentFold[0]?.houseName, 'Casa Mare');
        assert.equal(byAccentFold[0]?.roomName, 'Sala');
        assert.equal(byAccentFold[0]?.containerName, 'Cassetto TV');

        const byNote = db.searchItems({ q: 'mobili' });
        assert.equal(byNote.length, 1);
        assert.equal(byNote[0]?.name, 'Cacciavite a stella');

        const byHouseFilter = db.searchItems({ q: 'c', houseId: vaiano.id });
        assert.equal(byHouseFilter.length, 1);
        assert.equal(byHouseFilter[0]?.houseId, vaiano.id);

        const byCategoryOnly = db.searchItems({ category: 'Attrezzi' });
        assert.equal(byCategoryOnly.length, 1);
        assert.equal(byCategoryOnly[0]?.name, 'Cacciavite a stella');

        const exported = db.exportAll();
        assert.equal(exported.version, 1);
        assert.equal(exported.houses.length, 2);
        assert.equal(exported.items.length, 2);
    } finally {
        db.close();
    }
});

test('validates inputs and throws not-found errors appropriately', () => {
    const db = new InventoryDatabase(':memory:');
    try {
        assert.throws(() => db.createHouse('   '), InventoryValidationError);
        assert.throws(
            () => db.createRoom({ name: 'Cucina', houseId: 999 }),
            InventoryNotFoundError,
        );
        assert.throws(
            () => db.incrementItemQuantity(123, 0),
            InventoryValidationError,
        );
        assert.throws(
            () => db.incrementItemQuantity(123, 1),
            InventoryNotFoundError,
        );
    } finally {
        db.close();
    }
});
