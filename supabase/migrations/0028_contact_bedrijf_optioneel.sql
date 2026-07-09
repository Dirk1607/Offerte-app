-- ============================================================
-- 0028 — contact.bedrijf_id optioneel maken
-- ============================================================
-- Een contact mag voortaan LOS van een bedrijf bestaan (persoon/lead zonder
-- gekend bedrijf). Je kunt later alsnog een bedrijf koppelen.
--
-- VEILIG: enkel de NOT NULL-constraint valt weg; de FK (on delete cascade)
-- blijft. Bestaande data ongewijzigd.
-- ============================================================

alter table public.contact alter column bedrijf_id drop not null;

-- De prospects-compat-view op LEFT JOIN zetten, zodat contacten zonder bedrijf
-- niet uit de (nog bestaande) Prospectie-app verdwijnen. Zelfde kolommen/volgorde
-- als 0024, dus create-or-replace behoudt de INSTEAD OF-triggers.
create or replace view public.prospects as
select
  c.rijnr                              as id,
  c.aanspreektitel                     as titel,
  c.voornaam                           as voornaam,
  c.achternaam                         as naam,
  c.email                              as email,
  c.gsm                                as telefoon,
  b.naam                               as bedrijf,
  c.cat1                               as categorie,
  c.cat2                               as notities,
  to_char(c.created_at, 'DD/MM/YYYY')  as datum,
  c.status                             as status,
  c.created_at                         as created_at,
  c.verloop                            as verloop,
  c.samenvatting                       as samenvatting,
  c.volgende_stap                      as volgende_stap,
  c.volgende_stap_datum                as volgende_stap_datum,
  c.bedrijf_id                         as bedrijf_id
from contact c
left join bedrijf b on b.id = c.bedrijf_id;

notify pgrst, 'reload schema';
