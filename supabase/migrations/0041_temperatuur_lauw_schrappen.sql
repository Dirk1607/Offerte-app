-- ============================================================
-- 0041 — temperatuur: 'lauw' geschrapt, enkel warm/koud
-- ============================================================
-- 'lauw' bleek in de praktijk geen werkbaar criterium (twijfel zonder ander
-- gedrag). Gebruiker heeft bestaande 'lauw'-contacten al manueel omgezet via
-- de Temp.-kolom in de Prospecten-tab. De update hieronder is dus een
-- defensieve no-op — vangt enkel een eventueel vergeten rij op vóór de
-- striktere check hieronder, kost niets als er al geen 'lauw' meer over is.
--
-- temperatuur is hier een text-kolom + check-constraint, geen native
-- Postgres-enum (zie migratie 0037) — dus geen enum-type-gedoe nodig, enkel
-- de default en de check-constraint aanpassen.
-- ============================================================

update contact set temperatuur = 'koud' where temperatuur = 'lauw';

alter table contact alter column temperatuur set default 'koud';

alter table contact drop constraint if exists contact_temperatuur_check;
alter table contact add constraint contact_temperatuur_check check (
  temperatuur in ('warm', 'koud')
);

notify pgrst, 'reload schema';

-- ROLLBACK: alter table contact alter column temperatuur set default 'lauw';
--           alter table contact drop constraint if exists contact_temperatuur_check;
--           alter table contact add constraint contact_temperatuur_check check (temperatuur in ('warm','lauw','koud'));
--           notify pgrst, 'reload schema';
-- (De rijen die deze migratie zelf van lauw naar koud zette blijven koud —
-- niet te onderscheiden van rijen die de gebruiker zelf al naar koud zette.)
