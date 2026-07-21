# Supabase — Gesprek & Offerte

Databasestructuur en data-laag voor de offertetool.

## Datamodel

Hiërarchie van de catalogus (het "menu"):

```
lijn  (11 metrolijnen + 5 versnellers = 16)   referentiedata
 └─ station  (meerdere per lijn, bv HR→Organogram, PM→PMO)
     └─ artikel / product  (één of meer per station — draagt de inhoud)
```

| Tabel          | Rol |
|----------------|-----|
| `tarieven`     | Bedrijfsbrede dagtarieven per rol (Jr 800 / Sr 1200). |
| `lijn`         | De 16 vaste lijnen. |
| `station`      | Metrostations onder een lijn. |
| `artikel`      | Het verkoopbare product. Scope/WBS/opties/niveaus. `niveaus` bevat enkel **dagen**; prijs = dagen × tarief. |
| `offerte`      | Hoofd van een offerte (klant, datum, status, totaal). |
| `offerte_lijn` | Geselecteerd artikel **als snapshot** (kopie + tarieven), zodat oude offertes correct blijven. |

Prijs per niveau: `jrDagen × tarief(Jr) + srDagen × tarief(Sr)`.

## Installatie

1. Maak een project op [supabase.com](https://supabase.com).
2. SQL Editor → draai in volgorde:
   - `migrations/0001_init.sql` (tabellen + RLS + seed van lijnen & tarieven)
   - `migrations/0002_seed_voorbeeld.sql` (FIN/P&L als voorbeeldartikel)
3. Kopieer `config.example.js` → `config.js` en vul `url` + `anonKey` in
   (Dashboard → Settings → API). `config.js` zit mee in git — dat kan omdat
   het een publishable/anon key is (RLS beschermt de data, niet de key).

## Gebruik in de app

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="supabase/config.js"></script>
<script src="supabase/db.js"></script>
```

De data-laag `TNL` (in `db.js`) biedt o.a.:

```js
await TNL.getCatalogus();          // volledig menu (artikel + station + lijn)
await TNL.getTarieven();           // { Jr: 800, Sr: 1200 }
await TNL.upsertArtikel(artikel);  // product opslaan/bijwerken
await TNL.saveOfferte(kop, selectie); // selectie = [{ artikel, niveau }]
```

## Beveiliging

RLS staat aan met een login-gate (Supabase Auth, sinds v2.58): enkel
**ingelogde** gebruikers mogen iets, anoniem is volledig geblokkeerd
(migraties 0026/0027). Momenteel één organisatie — later eventueel te
verfijnen naar rollen/multi-tenant zonder de structuur te breken.
