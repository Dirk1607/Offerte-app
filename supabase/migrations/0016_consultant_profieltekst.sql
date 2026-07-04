-- 0016 — Consultant: beschrijvende profieltekst + tweede (detail) rapport-URL.
-- De DB houdt zowel de gestructureerde "onderdelen" (ervaring, opleidingen, …)
-- als de "beschrijvende tekst" bij; uit dezelfde data worden 2 rapporten gemaakt:
-- TNL Expert Profiel (kort, essentie) en TNL Expert Profiel Detail (uitgebreid).
alter table consultant add column if not exists profiel_tekst text;       -- beschrijvende tekst (komt op het profiel)
alter table consultant add column if not exists pdf_detail_url text;      -- gegenereerde detail-PDF
alter table consultant add column if not exists pdf_detail_naam text;
