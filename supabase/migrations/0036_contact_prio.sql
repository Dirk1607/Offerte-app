-- ============================================================
-- 0036 — Prioriteit per contact (Prospecten-tab)
-- ============================================================
-- Getal 1-9 (1 = hoogste prioriteit, 9 = standaard/laagste) dat bepaalt in welke
-- volgorde een prospect opgevolgd wordt. Vrij te bewerken/filteren/sorteren in de
-- Prospecten-tab, zoals status/cat1/cat2.
--
-- VEILIG / ADDITIEF: enkel een nieuwe kolom met default.
-- ============================================================

alter table contact add column if not exists prio smallint not null default 9;
alter table contact drop constraint if exists contact_prio_range;
alter table contact add constraint contact_prio_range check (prio between 1 and 9);

notify pgrst, 'reload schema';
