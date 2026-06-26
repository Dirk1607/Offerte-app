-- 0009 — Uitgebreide NextStone-velden.
-- waarom              = "Waarom dit belangrijk is" (educatief stuk voor de klant)
-- clusters            = [{naam, omschrijving}] — gedefinieerde clusters + uitleg (bron voor de WBS-dropdown)
-- implementatieproces = [{wie, actie}] — stappen om de NextStone te installeren
-- gebruiksproces      = [{wie, actie}] — maandelijks gebruiksproces na implementatie
alter table artikel add column if not exists waarom text;
alter table artikel add column if not exists clusters jsonb not null default '[]'::jsonb;
alter table artikel add column if not exists implementatieproces jsonb not null default '[]'::jsonb;
alter table artikel add column if not exists gebruiksproces jsonb not null default '[]'::jsonb;
