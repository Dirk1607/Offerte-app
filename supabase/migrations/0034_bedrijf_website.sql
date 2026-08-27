-- ============================================================
-- 0034 — Website-URL voor bedrijf
-- ============================================================
-- Bedrijf: website-URL, klikbaar in de tool (opent in nieuw tabblad).
--
-- VEILIG / ADDITIEF: enkel een nieuwe nullable kolom.
-- ============================================================

alter table bedrijf add column if not exists website text;
