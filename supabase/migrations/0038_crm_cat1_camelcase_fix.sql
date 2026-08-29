-- ============================================================
-- 0038 — Correctie op 0037: cat1 kwam ook aaneengeschreven voor
-- ============================================================
-- De controlelijst na 0037 toonde veel rijen met cat1 = 'KoudContact' /
-- 'WarmeLead' (geen spatie, camelCase — een restant van de screenshot-import-
-- normalisatie, PROS_CATMAP in app.html) naast de vorm mét spatie die al wel
-- herkend werd. Enkel rijen die nog op de veilige default staan (segment =
-- A_prospect, temperatuur = lauw) worden aangepast — al iets dat de gebruiker
-- intussen zelf aanpaste in de UI wordt niet overschreven.
-- ============================================================

update contact set segment = 'D_klant', temperatuur = 'warm'
  where segment = 'A_prospect' and temperatuur = 'lauw'
    and regexp_replace(lower(cat1), '\s+', '', 'g') = 'klant';

update contact set temperatuur = 'koud'
  where segment = 'A_prospect' and temperatuur = 'lauw'
    and regexp_replace(lower(cat1), '\s+', '', 'g') = 'koudcontact';

update contact set temperatuur = 'warm'
  where segment = 'A_prospect' and temperatuur = 'lauw'
    and regexp_replace(lower(cat1), '\s+', '', 'g') = 'warmelead';

-- segment C heeft een ander statuscodes-bereik dan A/D/E (mig. 0037) — segment
-- en status dus samen in dezelfde update, nooit een tussentijds ongeldige combinatie.
update contact set segment = 'C_tnl_expert', status = 'ex1_aangesproken'
  where segment = 'A_prospect' and temperatuur = 'lauw'
    and regexp_replace(lower(cat1), '\s+', '', 'g') = 'collega';

notify pgrst, 'reload schema';

-- ============================================================
-- CONTROLE — opnieuw draaien na deze migratie; wat nu nog overblijft is
-- écht niet-herkende data (of effectief leeg), niet gewoon een spatie-verschil.
--   select id, voornaam, achternaam, cat1, segment, temperatuur
--   from contact
--   where segment = 'A_prospect' and temperatuur = 'lauw'
--     and regexp_replace(lower(coalesce(cat1,'')), '\s+', '', 'g')
--         not in ('klant','koudcontact','warmelead','collega','')
--     and cat1 not ilike 'via %';
-- ============================================================

-- ============================================================
-- ROLLBACK: niet zinvol te reconstrueren welke rijen exact door déze migratie
-- (i.p.v. 0037) zijn aangepast — bij twijfel de segment/temperatuur-kolommen
-- via de Prospecten-tab handmatig terugzetten voor de betrokken rijen.
-- ============================================================
