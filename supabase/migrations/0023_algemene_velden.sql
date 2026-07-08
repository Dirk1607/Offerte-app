-- ============================================================
-- 0023 — Algemene beschrijvende velden voor bedrijf en contact
-- ============================================================
-- Bedrijf: algemeen telefoonnummer + algemeen e-mailadres (los van de gsm/
-- e-mail per contact) + land (voor eventuele buitenlandse bedrijven).
-- Contact: LinkedIn-URL + correspondentietaal (NL/FR/EN).
--
-- VEILIG / ADDITIEF: enkel nieuwe nullable kolommen.
-- ============================================================

-- ---- BEDRIJF ----
alter table bedrijf add column if not exists telefoon text;
alter table bedrijf add column if not exists email    text;
alter table bedrijf add column if not exists land     text default 'België';

-- Bestaande (Belgische) bedrijven het land invullen.
update bedrijf set land = 'België' where land is null;

-- ---- CONTACT ----
alter table contact add column if not exists linkedin_url text;
alter table contact add column if not exists taal         text;   -- 'NL' | 'FR' | 'EN'
