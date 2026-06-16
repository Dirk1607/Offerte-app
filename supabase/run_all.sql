-- ============================================================
-- TNL Offerte-tool — VOLLEDIGE database-setup in één keer.
-- Plak dit in Supabase → SQL Editor → New query → Run.
-- Bevat migraties 0001 t/m 0005 in de juiste volgorde.
-- Veilig om opnieuw te draaien op een LEEG project.
-- ============================================================


-- ============================================================
-- 0001_init.sql
-- ============================================================
create extension if not exists pgcrypto;

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table tarieven (
  rol         text primary key,
  dagtarief   numeric(10,2) not null,
  updated_at  timestamptz not null default now()
);

create trigger trg_tarieven_updated
  before update on tarieven
  for each row execute function set_updated_at();

insert into tarieven (rol, dagtarief) values
  ('Jr', 800),
  ('Sr', 1200);

create table lijn (
  code   text primary key,
  naam   text not null,
  type   text not null check (type in ('metrolijn','versneller')),
  icon   text,
  sort   int  not null default 0
);

insert into lijn (code, naam, type, icon, sort) values
  ('STR',  'Strategie',            'metrolijn',  '🗺️', 10),
  ('PROD', 'Product / R&D',        'metrolijn',  '🔬', 20),
  ('MKT',  'Marketing',            'metrolijn',  '📣', 30),
  ('SAL',  'Sales',                'metrolijn',  '📈', 40),
  ('OPS',  'Operations',           'metrolijn',  '⚙️', 50),
  ('AFS',  'After Sales',          'metrolijn',  '🤝', 60),
  ('HR',   'HR',                   'metrolijn',  '👥', 70),
  ('FIN',  'Finance',              'metrolijn',  '💰', 80),
  ('IT',   'IT & Digitalisering',  'metrolijn',  '💻', 90),
  ('QUA',  'Kwaliteit',            'metrolijn',  '✅', 100),
  ('SAF',  'Veiligheid',           'metrolijn',  '🦺', 110),
  ('PM',   'Project Management',   'versneller', '📋', 200),
  ('PROC', 'Proces Management',    'versneller', '🔄', 210),
  ('LEAD', 'Leiderschap',          'versneller', '🎯', 220),
  ('CHG',  'Change Management',    'versneller', '🔀', 230),
  ('OWN',  'Eigenaarschap',        'versneller', '🏆', 240);

create table station (
  id         uuid primary key default gen_random_uuid(),
  lijn_code  text not null references lijn(code) on update cascade,
  naam       text not null,
  sort       int  not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_station_lijn on station(lijn_code);

create trigger trg_station_updated
  before update on station
  for each row execute function set_updated_at();

create table artikel (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references station(id) on delete cascade,
  subnaam       text,
  omschrijving  text,
  scope_in      text,
  scope_uit     text,
  beperkingen   text,
  input         text,
  deliverables  text,
  doelstellingen text,
  doorlooptijd  text,
  proces        text,
  wbs           jsonb not null default '[]'::jsonb,
  opties        jsonb not null default '[]'::jsonb,
  niveaus       jsonb not null default '{}'::jsonb,
  actief        boolean not null default true,
  sort          int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index idx_artikel_station on artikel(station_id);
create index idx_artikel_actief  on artikel(actief);

create trigger trg_artikel_updated
  before update on artikel
  for each row execute function set_updated_at();

create table offerte (
  id            uuid primary key default gen_random_uuid(),
  klant_naam    text,
  klant_contact text,
  datum         date not null default current_date,
  status        text not null default 'concept',
  totaal        numeric(12,2) not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger trg_offerte_updated
  before update on offerte
  for each row execute function set_updated_at();

create table offerte_lijn (
  id          uuid primary key default gen_random_uuid(),
  offerte_id  uuid not null references offerte(id) on delete cascade,
  artikel_id  uuid references artikel(id) on delete set null,
  niveau      text not null check (niveau in ('S','M','I')),
  snapshot    jsonb not null,
  prijs       numeric(12,2) not null default 0,
  dagen       numeric(8,2)  not null default 0,
  sort        int not null default 0,
  created_at  timestamptz not null default now()
);

create index idx_offlijn_offerte on offerte_lijn(offerte_id);

alter table tarieven     enable row level security;
alter table lijn         enable row level security;
alter table station      enable row level security;
alter table artikel      enable row level security;
alter table offerte      enable row level security;
alter table offerte_lijn enable row level security;

do $$
declare t text;
begin
  foreach t in array array['tarieven','lijn','station','artikel','offerte','offerte_lijn']
  loop
    execute format(
      'create policy %I on %I for all to authenticated using (true) with check (true);',
      'auth_all_' || t, t
    );
  end loop;
end;
$$;


-- ============================================================
-- 0002_seed_voorbeeld.sql
-- ============================================================
with s as (
  insert into station (lijn_code, naam, sort)
  values ('FIN', 'P&L rapportering', 10)
  returning id
)
insert into artikel (
  station_id, subnaam, omschrijving,
  scope_in, scope_uit, beperkingen, input, deliverables, doelstellingen,
  doorlooptijd, proces, wbs, opties, niveaus, sort
)
select
  s.id,
  'Profit & Loss',
  'We implementeren een maandelijkse P&L-rapportering zodat u altijd weet waar uw marge naartoe gaat.',
  '• Opzetten van een maandelijkse P&L-structuur op maat
• Koppeling aan bestaande boekhouding (manueel of via export)
• Definitie van kostenstructuur en margeberekening
• Excel-dashboard met resultatenrekening per activiteit
• Training van de verantwoordelijke medewerker',
  '• Geen aanpassing of migratie van het boekhoudpakket
• Geen historische reconstructie van meer dan 12 maanden
• Geen consolidatie van meerdere juridische entiteiten
• Geen geautomatiseerde koppeling via API of BI-tool',
  'Vereist een operationele boekhouding met resultatenrekening. Niet geschikt voor bedrijven zonder kostenstructuur of zonder maandelijkse afsluiting.',
  '• Toegang tot het boekhoudpakket of maandelijkse exports
• Overzicht van de kostenstructuur (kostenplaatsen, activiteiten)
• Contactpersoon financiën beschikbaar (2 × ½ dag)',
  '• Excel P&L-template op maat van de organisatie
• Instructiedocument voor maandelijkse invulling
• Dashboard met marge per product / klant / afdeling
• 1 validatiesessie na de eerste maandafsluiting
• Eindrapport met aanbevelingen',
  'Maandelijkse P&L beschikbaar binnen 5 werkdagen na maandafsluiting. Inzicht in bruto- en nettomarge per activiteit. Zaakvoerder kan zelfstandig bijsturen op basis van cijfers.',
  '3-5 weken',
  'Intake → Ontwerp → Implementatie → Training → Validatie',
  '[
    {"activiteit":"Intake & analyse kostenstructuur","type":"consultant","rol":"Sr","dagen":0.5},
    {"activiteit":"Ontwerp P&L-structuur & template","type":"consultant","rol":"Sr","dagen":1},
    {"activiteit":"Koppeling aan boekhouding & test","type":"consultant","rol":"Jr","dagen":1},
    {"activiteit":"Dashboard bouwen","type":"consultant","rol":"Jr","dagen":1},
    {"activiteit":"Training verantwoordelijke","type":"consultant","rol":"Sr","dagen":0.5},
    {"activiteit":"Validatiesessie maand 1","type":"consultant","rol":"Sr","dagen":0.5},
    {"activiteit":"Aanleveren data & exports","type":"klant","rol":null,"dagen":0.5},
    {"activiteit":"Deelname training & validatie","type":"klant","rol":null,"dagen":0.5}
  ]'::jsonb,
  '[
    {"omschrijving":"Cashflow forecast (13-weken rolling)","prijs":1200},
    {"omschrijving":"Automatische koppeling via BI-tool (Power BI / Looker)","prijs":2500},
    {"omschrijving":"Consolidatie meerdere entiteiten","prijs":1800},
    {"omschrijving":"Maandelijkse begeleiding eerste kwartaal (3 × ½ dag)","prijs":1500}
  ]'::jsonb,
  '{
    "S":{"jrDagen":0,"srDagen":1.5,"klantDagen":0.5,"omschrijving":"Diagnose + P&L-template"},
    "M":{"jrDagen":2,"srDagen":2,"klantDagen":1,"omschrijving":"Volledige implementatie + training"},
    "I":{"jrDagen":4,"srDagen":4,"klantDagen":2,"omschrijving":"Uitbouw + dashboard + kwartaalbegeleiding"}
  }'::jsonb,
  10
from s;


-- ============================================================
-- 0003_dev_open_rls.sql  (DEV: anon mag alles — tijdelijk!)
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['tarieven','lijn','station','artikel','offerte','offerte_lijn']
  loop
    execute format('drop policy if exists %I on %I;', 'auth_all_' || t, t);
    execute format(
      'create policy %I on %I for all to anon, authenticated using (true) with check (true);',
      'dev_all_' || t, t
    );
  end loop;
end;
$$;


-- ============================================================
-- 0004_klant_quickscan.sql
-- ============================================================
create table klant (
  id             uuid primary key default gen_random_uuid(),
  bedrijf        text not null,
  contactpersoon text,
  email          text,
  functie        text,
  sector         text,
  medewerkers    text,
  telefoon       text,
  notities       text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create unique index klant_bedrijf_uniek on klant (lower(btrim(bedrijf)));

create trigger trg_klant_updated
  before update on klant
  for each row execute function set_updated_at();

create table quickscan (
  id               uuid primary key default gen_random_uuid(),
  klant_id         uuid not null references klant(id) on delete cascade,
  datum            date not null default current_date,
  invuller         text,
  gemiddelde_score numeric(4,2),
  scores           jsonb not null default '{}'::jsonb,
  labels           jsonb not null default '{}'::jsonb,
  ruwe_mail        text,
  created_at       timestamptz not null default now(),
  unique (klant_id, datum, invuller)
);

create index idx_quickscan_klant on quickscan(klant_id);

alter table offerte
  add column klant_id uuid references klant(id) on delete set null;

create index idx_offerte_klant on offerte(klant_id);

alter table klant     enable row level security;
alter table quickscan enable row level security;

create policy dev_all_klant     on klant     for all to anon, authenticated using (true) with check (true);
create policy dev_all_quickscan on quickscan for all to anon, authenticated using (true) with check (true);


-- ============================================================
-- 0005_tarieven_eenheden.sql
-- ============================================================
alter table tarieven
  add column if not exists uurprijs      numeric(10,2),
  add column if not exists halvedagprijs  numeric(10,2),
  add column if not exists heledagprijs   numeric(10,2);

update tarieven set
  heledagprijs  = coalesce(heledagprijs, dagtarief),
  halvedagprijs = coalesce(halvedagprijs, round(dagtarief / 2, 2)),
  uurprijs      = coalesce(uurprijs, round(dagtarief / 8, 2))
where dagtarief is not null;

alter table tarieven drop column if exists dagtarief;
