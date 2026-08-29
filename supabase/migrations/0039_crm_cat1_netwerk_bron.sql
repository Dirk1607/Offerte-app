-- ============================================================
-- 0039 — cat1 'Netwerk' → bron_zakelijk = eigen_netwerk
-- ============================================================
-- De 62 resterende contacten op de controlelijst na 0037/0038 hebben allemaal
-- cat1 = 'Netwerk' (de consultants-CSV-import). Segment (A_prospect) en
-- temperatuur (lauw) kloppen daar al als veilige default — enkel bron_zakelijk
-- was nog leeg terwijl cat1 letterlijk zegt waar ze vandaan komen.
-- ============================================================

update contact set bron_zakelijk = 'eigen_netwerk'
  where segment = 'A_prospect' and temperatuur = 'lauw' and bron_zakelijk is null
    and regexp_replace(lower(cat1), '\s+', '', 'g') = 'netwerk';

notify pgrst, 'reload schema';

-- ROLLBACK: update contact set bron_zakelijk = null where bron_zakelijk = 'eigen_netwerk'
-- and regexp_replace(lower(cat1), '\s+', '', 'g') = 'netwerk'; -- (raakt ook eventueel
-- handmatig nadien op eigen_netwerk gezette rijen — enkel gebruiken vlak na het draaien).
