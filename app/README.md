# app/ — Frontend Flutter

Contiene l'app Flutter (Web/PWA, Android, iOS) di Home Scatolo.

## Requisiti

- Flutter SDK ≥ 3.x (stable channel)

## Setup

```bash
cd app
flutter pub get
```

## Avvio

```bash
# Web (PWA)
flutter run -d chrome

# Android
flutter run -d android

# iOS
flutter run -d ios
```

## Build

```bash
# Web
flutter build web

# Android APK
flutter build apk

# iOS
flutter build ios
```

## Test e analisi

```bash
flutter analyze
flutter test
```

## Configurazione backend

L'URL del backend è configurabile in `lib/services/api_client.dart` tramite la costante `_defaultBaseUrl`.
In produzione, sovrascrivila passando il parametro `baseUrl` al costruttore di `ApiClient`.
Nessun token o segreto va inserito nel codice sorgente client.

## Struttura `lib/`

- `models/` — House, Room, Container, Item
- `screens/` — houses, rooms, containers, capture, inventory_list, item_detail, search
- `services/` — api_client, storage_service, camera_service
- `widgets/` — componenti UI riutilizzabili
