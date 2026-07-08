-- ============================================================
-- 0022 — Adres van een bedrijf opsplitsen in aparte velden
-- ============================================================
-- Het losse tekstveld `adres` wordt vervangen door gestructureerde velden:
-- straat, huisnummer, bus, postcode, gemeente. Handig voor nette adressering
-- op de offerte én voor de latere km/verplaatsing-berekening (postcode/gemeente).
--
-- VEILIG / ADDITIEF: nieuwe (nullable) kolommen; de oude kolom `adres` blijft
-- staan als terugval en wordt niet gedropt. Slechts 2 bestaande adressen worden
-- hieronder handmatig verdeeld.
-- ============================================================

alter table bedrijf add column if not exists straat     text;
alter table bedrijf add column if not exists huisnummer text;
alter table bedrijf add column if not exists bus        text;
alter table bedrijf add column if not exists postcode   text;
alter table bedrijf add column if not exists gemeente   text;

-- Bestaande adressen verdelen (de enige twee met een ingevuld adres).
update bedrijf set straat = 'Bosduinstraat', huisnummer = '51'
  where naam_norm = norm_naam('Garden Passion') and coalesce(straat,'') = '';

update bedrijf set straat = 'Kustlei', huisnummer = '20', postcode = '2900', gemeente = 'Schoten'
  where naam_norm = norm_naam('Clavani Consultancy') and coalesce(straat,'') = '';
