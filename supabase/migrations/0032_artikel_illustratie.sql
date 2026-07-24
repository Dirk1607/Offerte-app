-- 0032 — NextStone (artikel): 1 illustratie (afbeelding) die in de offerte
-- tussen de tekst (Waarom/Doel/SMART/Belofte) en de kostentabel verschijnt.
-- illustratie = { naam, data } of null; zelfde vorm als een item uit bijlagen.
alter table artikel add column if not exists illustratie jsonb;
