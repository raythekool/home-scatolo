# Architettura — Home Scatolo

## Modello dati

```
House (casa)
 └── Room (stanza)
      └── Container (armadio, scatolone, libreria, cassetto)
           └── Item (oggetto riconosciuto)
```

Ogni `Item` ha: nome, categoria, descrizione (generata da AI), foto sorgente, data di inserimento, container di appartenenza.

## Flusso di riconoscimento

1. L'utente scatta una foto/video di un `Container` dall'app Flutter.
2. Il frontend invia l'immagine (base64) al backend via HTTPS.
3. Il backend inoltra la richiesta a GitHub Models (endpoint OpenAI-compatibile) con un prompt strutturato che chiede di elencare gli oggetti visibili, categoria e descrizione breve.
4. Il backend normalizza la risposta in JSON e la restituisce al client.
5. Il client salva gli `Item` risultanti in storage locale (SQLite/Hive) associati al `Container` corrente.

## Sicurezza

- Il token GitHub Models non è mai esposto al client: risiede solo come variabile d'ambiente/secret sul backend.
- Le immagini vengono inviate solo al momento del riconoscimento, non salvate permanentemente lato server.

## Multi-casa

L'utente può configurare più `House`, ciascuna con il proprio set di stanze e contenitori. Lo switch tra case avviene lato client; i dati restano isolati per `House` nello storage locale.
