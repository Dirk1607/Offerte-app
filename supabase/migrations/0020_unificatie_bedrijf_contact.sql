-- ============================================================
-- 0020 — UNIFICATIE, FASE 1: schema `bedrijf` + `contact`
-- ============================================================
-- Doel: één datamodel voor prospect én klant. Een BEDRIJF is de kapstok
-- (met status prospect|klant); daaronder hangen CONTACTEN (personen).
-- Quickscan en offerte gaan verwijzen naar bedrijf + contact.
--
-- VEILIG / ADDITIEF: dit maakt enkel NIEUWE, lege tabellen en voegt
-- NIEUWE (nullable) kolommen toe. Bestaande tabellen (klant, quickscan,
-- offerte, en het aparte prospects-project) blijven volledig ongewijzigd.
-- Terugdraaien = de nieuwe tabellen/kolommen droppen.
-- ============================================================

-- ------------------------------------------------------------
-- Normalisatie-sleutel voor het matchen/ontdubbelen van bedrijfsnamen.
-- Kleine letters, leestekens weg, spaties collapsen, rechtsvorm afstrippen.
-- "Het Metaal NV" en "Het Metaal" krijgen zo dezelfde naam_norm.
-- ------------------------------------------------------------
create or replace function norm_naam(p text)
returns text language sql immutable as $$
  select btrim(regexp_replace(
    regexp_replace(
      regexp_replace(lower(btrim(coalesce(p, ''))), '[.,]', '', 'g'),
      '\s+', ' ', 'g'),
    '\s+(nv|bv|bvba|cvba|comm\s?v|sa|sprl|srl|vzw|ltd|gmbh|cv|se|esv)$', '', 'g'))
$$;

-- ------------------------------------------------------------
-- BEDRIJF (de kapstok)
-- ------------------------------------------------------------
create table bedrijf (
  id                 uuid primary key default gen_random_uuid(),
  naam               text not null,
  naam_norm          text,                                   -- auto ingevuld door trigger
  adres              text,
  btw_nummer         text,
  sector             text,
  aantal_medewerkers text,
  status             text not null default 'prospect',       -- 'prospect' | 'klant'
  notities           text,
  bron               text,                                   -- waar dit dossier vandaan kwam ('prospectie'/'quickscan'/'manueel')
  prospect_ref       text,                                   -- oorspronkelijke prospects.id (traceerbaarheid na migratie)
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create or replace function set_bedrijf_norm() returns trigger language plpgsql as $$
begin
  new.naam_norm  := norm_naam(new.naam);
  new.updated_at := now();
  return new;
end $$;

create trigger trg_bedrijf_norm
  before insert or update on bedrijf
  for each row execute function set_bedrijf_norm();

-- Eén bedrijf per genormaliseerde naam (auto-dedupe-vangnet).
create unique index bedrijf_naam_norm_uniek on bedrijf (naam_norm);

-- ------------------------------------------------------------
-- CONTACT (personen onder een bedrijf; meerdere per bedrijf)
-- ------------------------------------------------------------
create table contact (
  id                  uuid primary key default gen_random_uuid(),
  bedrijf_id          uuid not null references bedrijf(id) on delete cascade,
  aanspreektitel      text,                                  -- 'Dhr.' | 'Mevr.' | ...
  voornaam            text,
  achternaam          text,
  email               text,
  gsm                 text,
  functie             text,
  quickscan_ingevuld  boolean not null default false,
  nog_te_contacteren  boolean not null default false,
  cat1                text,
  cat2                text,
  -- funnel / opvolging (uit de Prospectie-app)
  verloop             text,
  samenvatting        text,
  volgende_stap       text,
  volgende_stap_datum date,
  notities            text,
  bron                text,
  prospect_ref        text,                                  -- oorspronkelijke prospects.id
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index idx_contact_bedrijf on contact (bedrijf_id);
create index idx_contact_email   on contact (lower(email));

create trigger trg_contact_updated
  before update on contact
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- Quickscan & offerte laten verwijzen naar bedrijf + contact.
-- (klant_id blijft staan voor de terugval tot fase 2 bewezen is.)
-- ------------------------------------------------------------
alter table quickscan add column if not exists bedrijf_id uuid references bedrijf(id) on delete set null;
alter table quickscan add column if not exists contact_id uuid references contact(id) on delete set null;
alter table offerte   add column if not exists bedrijf_id uuid references bedrijf(id) on delete set null;
alter table offerte   add column if not exists contact_id uuid references contact(id) on delete set null;

create index if not exists idx_quickscan_bedrijf on quickscan (bedrijf_id);
create index if not exists idx_quickscan_contact on quickscan (contact_id);
create index if not exists idx_offerte_bedrijf   on offerte (bedrijf_id);

-- ------------------------------------------------------------
-- Goedkeurings-queue: voorgestelde wijzigingen aan reeds ingevulde velden.
-- Lege velden worden meteen aangevuld; een WIJZIGING van een bestaande
-- waarde komt hier terecht en wacht op ja/nee van de gebruiker.
-- ------------------------------------------------------------
create table wijziging_voorstel (
  id           uuid primary key default gen_random_uuid(),
  entiteit     text not null,                 -- 'bedrijf' | 'contact'
  record_id    uuid not null,                 -- id in bedrijf/contact
  veld         text not null,                 -- kolomnaam
  oude_waarde  text,
  nieuwe_waarde text,
  bron         text,                          -- 'quickscan' | 'prospectie' | ...
  status       text not null default 'open',  -- 'open' | 'goedgekeurd' | 'afgewezen'
  created_at   timestamptz not null default now(),
  behandeld_at timestamptz
);

create index idx_wijziging_open on wijziging_voorstel (status) where status = 'open';

-- ------------------------------------------------------------
-- RLS — voorlopig dev-open (net als de bestaande tabellen), tot fase 5
-- de login + strikte RLS invoert.
-- ------------------------------------------------------------
alter table bedrijf            enable row level security;
alter table contact            enable row level security;
alter table wijziging_voorstel enable row level security;

create policy dev_all_bedrijf   on bedrijf            for all to anon, authenticated using (true) with check (true);
create policy dev_all_contact   on contact            for all to anon, authenticated using (true) with check (true);
create policy dev_all_wijziging on wijziging_voorstel for all to anon, authenticated using (true) with check (true);

-- ============================================================
-- cat1/cat2-keuzelijsten worden (net als consultant-regio/sector) bewaard
-- in de bestaande `instellingen`-tabel onder sleutels 'contact_cat1_opties'
-- en 'contact_cat2_opties' (jsonb-array). Geen schema-wijziging nodig;
-- de app vult ze aan bij "Andere…".
-- ============================================================
