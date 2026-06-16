-- ============================================================
-- TNL Gesprek & Offerte — initiële databasestructuur
-- Supabase / PostgreSQL
-- Hiërarchie: lijn -> station -> artikel (product)
-- Offerte bewaart een snapshot van de geselecteerde artikelen.
-- ============================================================

-- Zorg dat gen_random_uuid() beschikbaar is
create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- Hulpfunctie: updated_at automatisch bijwerken
-- ------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- TARIEVEN  (bedrijfsbreed, dagtarieven per rol)
-- ------------------------------------------------------------
create table tarieven (
  rol         text primary key,            -- 'Jr', 'Sr'
  dagtarief   numeric(10,2) not null,
  updated_at  timestamptz not null default now()
);

create trigger trg_tarieven_updated
  before update on tarieven
  for each row execute function set_updated_at();

insert into tarieven (rol, dagtarief) values
  ('Jr', 800),
  ('Sr', 1200);

-- ------------------------------------------------------------
-- LIJN  (11 metrolijnen + 5 versnellers = 16, referentiedata)
-- ------------------------------------------------------------
create table lijn (
  code   text primary key,                 -- HR, PM, STR…
  naam   text not null,
  type   text not null check (type in ('metrolijn','versneller')),
  icon   text,
  sort   int  not null default 0
);

insert into lijn (code, naam, type, icon, sort) values
  -- Metrolijnen
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
  -- Versnellers
  ('PM',   'Project Management',   'versneller', '📋', 200),
  ('PROC', 'Proces Management',    'versneller', '🔄', 210),
  ('LEAD', 'Leiderschap',          'versneller', '🎯', 220),
  ('CHG',  'Change Management',    'versneller', '🔀', 230),
  ('OWN',  'Eigenaarschap',        'versneller', '🏆', 240);

-- ------------------------------------------------------------
-- STATION  (metrostation, meerdere per lijn)
-- ------------------------------------------------------------
create table station (
  id         uuid primary key default gen_random_uuid(),
  lijn_code  text not null references lijn(code) on update cascade,
  naam       text not null,                 -- 'Organogram', 'PMO'…
  sort       int  not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_station_lijn on station(lijn_code);

create trigger trg_station_updated
  before update on station
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- ARTIKEL  (= product, strikt bij één station)
-- Hybride: scalairen als kolom, lijsten als jsonb.
-- niveaus bevat enkel dágen; prijs komt uit tarieven.
-- ------------------------------------------------------------
create table artikel (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references station(id) on delete cascade,
  subnaam       text,                        -- optioneel, bv 'light' / 'volledig'
  omschrijving  text,
  scope_in      text,
  scope_uit     text,
  beperkingen   text,
  input         text,
  deliverables  text,
  doelstellingen text,
  doorlooptijd  text,
  proces        text,
  wbs           jsonb not null default '[]'::jsonb,  -- [{activiteit,type,rol,dagen}]
  opties        jsonb not null default '[]'::jsonb,  -- [{omschrijving,prijs}]
  niveaus       jsonb not null default '{}'::jsonb,  -- {S|M|I:{jrDagen,srDagen,klantDagen,omschrijving}}
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

-- ------------------------------------------------------------
-- OFFERTE
-- ------------------------------------------------------------
create table offerte (
  id            uuid primary key default gen_random_uuid(),
  klant_naam    text,
  klant_contact text,
  datum         date not null default current_date,
  status        text not null default 'concept',  -- concept / verzonden / aanvaard / verloren
  totaal        numeric(12,2) not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger trg_offerte_updated
  before update on offerte
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- OFFERTE_LIJN  (snapshot van een geselecteerd artikel)
-- artikel_id is enkel referentie/traceability; de inhoud zit
-- in 'snapshot' zodat de offerte correct blijft na prijswijziging.
-- ------------------------------------------------------------
create table offerte_lijn (
  id          uuid primary key default gen_random_uuid(),
  offerte_id  uuid not null references offerte(id) on delete cascade,
  artikel_id  uuid references artikel(id) on delete set null,
  niveau      text not null check (niveau in ('S','M','I')),
  snapshot    jsonb not null,               -- volledige kopie artikel + tarieven op dat moment
  prijs       numeric(12,2) not null default 0,
  dagen       numeric(8,2)  not null default 0,
  sort        int not null default 0,
  created_at  timestamptz not null default now()
);

create index idx_offlijn_offerte on offerte_lijn(offerte_id);

-- ============================================================
-- ROW LEVEL SECURITY
-- Eén organisatie: elke ingelogde gebruiker mag alles.
-- (Later te verfijnen naar rollen/multi-tenant.)
-- ============================================================
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
