-- 0014 — Klant uitbreiden voor de offerte: adres, BTW-nummer en een losse
-- verwijzing naar de prospect (uit het aparte Prospectie-project; enkel de id).
alter table klant add column if not exists adres text;
alter table klant add column if not exists btw_nummer text;
alter table klant add column if not exists prospect_id text;
