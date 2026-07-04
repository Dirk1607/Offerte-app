-- 0017 — Consultant: apart Management-Profile-document (naast CV).
-- Foto, CV én Management Profile zijn bijlagen van de consultant ("stoef"-documenten,
-- achievements/accomplishments); ze worden NIET in het TNL Profiel verwerkt.
alter table consultant add column if not exists mgmt_profile_url text;
alter table consultant add column if not exists mgmt_profile_naam text;
