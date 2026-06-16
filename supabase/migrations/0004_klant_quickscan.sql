-- ============================================================
-- Bedrijfsdossier + quickscan-historiek.
-- Een dossier (quickscan) is uniek op: datum inlezen + bedrijf + invuller.
-- 'klant' groepeert alles per bedrijf zodat je later kan terugvallen.
-- ============================================================

-- ------------------------------------------------------------
-- KLANT  (bedrijfsdossier)
-- ------------------------------------------------------------
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

-- Eén dossier per bedrijf (case-/spatie-ongevoelig) — veiligheidsnet tegen dubbels.
create unique index klant_bedrijf_uniek on klant (lower(btrim(bedrijf)));

create trigger trg_klant_updated
  before update on klant
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- QUICKSCAN  (scan-resultaat, historiek per bedrijf)
-- ------------------------------------------------------------
create table quickscan (
  id               uuid primary key default gen_random_uuid(),
  klant_id         uuid not null references klant(id) on delete cascade,
  datum            date not null default current_date,  -- datum van inlezen
  invuller         text,                                -- naam invuller
  gemiddelde_score numeric(4,2),
  scores           jsonb not null default '{}'::jsonb,  -- {STR:2.9, FIN:3.3, …}
  labels           jsonb not null default '{}'::jsonb,  -- {STR:'Goed ontwikkeld', …}
  ruwe_mail        text,                                -- originele mail, bewaard
  created_at       timestamptz not null default now(),
  -- identiteit van een dossier:
  unique (klant_id, datum, invuller)
);

create index idx_quickscan_klant on quickscan(klant_id);

-- ------------------------------------------------------------
-- OFFERTE koppelen aan een bedrijf
-- ------------------------------------------------------------
alter table offerte
  add column klant_id uuid references klant(id) on delete set null;

create index idx_offerte_klant on offerte(klant_id);

-- ============================================================
-- RLS (dev: anon mag alles, net als de andere tabellen)
-- ============================================================
alter table klant     enable row level security;
alter table quickscan enable row level security;

create policy dev_all_klant     on klant     for all to anon, authenticated using (true) with check (true);
create policy dev_all_quickscan on quickscan for all to anon, authenticated using (true) with check (true);
