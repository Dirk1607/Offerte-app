-- ============================================================
-- 0006 — Artikel ➜ "TNL Fix" structuur (projectmatig).
-- Doel/objectief/belofte op de kop; WBS = deliverables met
-- scope-groep, rol+capaciteit, optie, klant-input/inspanning, week.
-- Niveaus (S/M/I) en losse scope/proces-velden vervallen.
-- ============================================================

-- Kop-velden
alter table artikel rename column omschrijving to doel;
alter table artikel add column if not exists meetbaar_objectief text;
alter table artikel add column if not exists belofte text;
alter table artikel add column if not exists out_of_scope jsonb not null default '[]'::jsonb;

-- Vervallen velden
alter table artikel drop column if exists scope_in;
alter table artikel drop column if exists scope_uit;
alter table artikel drop column if exists beperkingen;
alter table artikel drop column if exists input;
alter table artikel drop column if exists deliverables;
alter table artikel drop column if exists doelstellingen;
alter table artikel drop column if exists doorlooptijd;
alter table artikel drop column if exists proces;
alter table artikel drop column if exists niveaus;
alter table artikel drop column if exists opties;

-- 'wbs' blijft jsonb maar krijgt een nieuwe vorm; oude testdata opruimen.
delete from artikel;
delete from station where naam = 'P&L rapportering';

-- ------------------------------------------------------------
-- Voorbeeld-Fix opnieuw, in het nieuwe formaat.
-- ------------------------------------------------------------
with s as (
  insert into station (lijn_code, naam, sort)
  values ('FIN', 'P&L rapportering', 10)
  returning id
)
insert into artikel (
  station_id, subnaam, doel, meetbaar_objectief, belofte, wbs, out_of_scope, sort
)
select
  s.id,
  'Profit & Loss',
  'Een maandelijkse P&L-rapportering implementeren zodat u altijd weet waar uw marge naartoe gaat.',
  'Elke maand op de 7e beschik ik over de cijfers van de vorige maand, vergelijkbaar met vorige periodes, zodat ik weloverwogen kan beslissen over omzet, operationele kosten, overhead en winstgevendheid.',
  'Na deze Fix stuurt u maandelijks bij op basis van cijfers in plaats van buikgevoel.',
  '[
    {"omschrijving":"Beschreven proces voor de maandelijkse P&L-afsluiting","scopeGroep":"Fundament","rol":"Sr","eenheid":"halvedag","aantal":1,"optie":false,"klantInput":"","klantAantal":0,"klantEenheid":"dag","week":1,"vast":true},
    {"omschrijving":"Gecoördineerd project (opvolging & afstemming)","scopeGroep":"Fundament","rol":"Sr","eenheid":"halvedag","aantal":1,"optie":false,"klantInput":"","klantAantal":0,"klantEenheid":"dag","week":1,"vast":true},
    {"omschrijving":"P&L-structuur & Excel-template op maat","scopeGroep":"Opzet","rol":"Sr","eenheid":"heledag","aantal":1,"optie":false,"klantInput":"Overzicht kostenstructuur (kostenplaatsen, activiteiten)","klantAantal":0.5,"klantEenheid":"dag","week":1,"vast":false},
    {"omschrijving":"Koppeling aan boekhouding + test","scopeGroep":"Opzet","rol":"Jr","eenheid":"heledag","aantal":1,"optie":false,"klantInput":"Toegang of maandelijkse exports boekhouding","klantAantal":0.5,"klantEenheid":"dag","week":2,"vast":false},
    {"omschrijving":"Dashboard met marge per activiteit","scopeGroep":"Dashboard","rol":"Jr","eenheid":"heledag","aantal":1,"optie":false,"klantInput":"","klantAantal":0,"klantEenheid":"dag","week":2,"vast":false},
    {"omschrijving":"Training van de verantwoordelijke","scopeGroep":"Overdracht","rol":"Sr","eenheid":"halvedag","aantal":1,"optie":false,"klantInput":"Beschikbaarheid verantwoordelijke","klantAantal":0.5,"klantEenheid":"dag","week":3,"vast":false},
    {"omschrijving":"Validatiesessie na eerste maandafsluiting","scopeGroep":"Overdracht","rol":"Sr","eenheid":"halvedag","aantal":1,"optie":true,"klantInput":"","klantAantal":0.5,"klantEenheid":"dag","week":4,"vast":false}
  ]'::jsonb,
  '[
    {"groep":"Boekhouding","omschrijving":"Geen aanpassing of migratie van het boekhoudpakket"},
    {"groep":"Boekhouding","omschrijving":"Geen historische reconstructie van meer dan 12 maanden"},
    {"groep":"Scope","omschrijving":"Geen consolidatie van meerdere juridische entiteiten"},
    {"groep":"Integratie","omschrijving":"Geen geautomatiseerde koppeling via API of BI-tool"}
  ]'::jsonb,
  10
from s;
