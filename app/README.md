# app/ — Frontend Flutter

Contiene l'app Flutter (Web/PWA, Android, iOS) di Home Scatolo.

Da inizializzare con:

```bash
flutter create --platforms web,android,ios .
```

Struttura prevista in `lib/`:
- `models/` — House, Room, Container, Item
- `screens/` — capture, inventory_list, item_detail, search, houses
- `services/` — api_client, storage_service, camera_service
- `widgets/` — componenti UI riutilizzabili
