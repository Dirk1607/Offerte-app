-- 0012 — NextStone (artikel): rubriek "Processen" voor de offerte.
-- Voorlopig bewaren we enkel de bestandsnaam van elk gekozen proces
-- (de bestanden staan nu nog in een map op de pc; opslag/upload volgt later).
-- processen = [{ naam }]
alter table artikel add column if not exists processen jsonb not null default '[]'::jsonb;
