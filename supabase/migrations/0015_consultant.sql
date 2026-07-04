-- 0015 — Consultant-bibliotheek (profielen) + storage-bucket voor foto/CV/1-pager.
-- De consultant vult alles zelf in (CV-data + expertise-scores + tarief). De 1-pager
-- (TNL Profiel) wordt hieruit gegenereerd, net zoals de tool-productfiches.
create table if not exists consultant (
  id uuid primary key default gen_random_uuid(),
  voornaam text,
  naam text not null,
  titel text,                                          -- bv. "Senior Consultant"
  email text,
  telefoon text,
  linkedin_url text,
  regios jsonb not null default '[]'::jsonb,           -- ["Antwerpen","Brussel","Gent"]
  foto_url text,
  cv_url text,
  cv_naam text,
  status text default 'actief',                        -- actief / inactief / kandidaat
  intern_notities text,
  pitch text,                                          -- oneliner
  achtergrond text,                                    -- ACHTERGROND-alinea
  verwachting text,                                    -- "Wat u van mij mag verwachten"
  kerncompetenties jsonb not null default '[]'::jsonb, -- [{titel, subtitel}]
  kpi jsonb not null default '[]'::jsonb,              -- [{getal, label}]
  skills jsonb not null default '[]'::jsonb,           -- [string]
  talen jsonb not null default '[]'::jsonb,            -- [{taal, niveau}]
  sectoren jsonb not null default '[]'::jsonb,         -- [string]
  ervaring jsonb not null default '[]'::jsonb,         -- [{periode, rol, bedrijf, omschrijving}]
  opleidingen jsonb not null default '[]'::jsonb,      -- [{jaar, titel, instelling}]
  testimonials jsonb not null default '[]'::jsonb,     -- [{quote, naam, functie}]
  expertise jsonb not null default '{}'::jsonb,        -- {STR:8, FIN:9, PROC:7, ...} score 0-10 per metrolijn/versneller
  tool_ids jsonb not null default '[]'::jsonb,         -- -> tools (tools die ik kan implementeren)
  nextstone_ids jsonb not null default '[]'::jsonb,    -- -> artikel (NextStones die ik lever)
  tarief jsonb not null default '{}'::jsonb,           -- {uur, halvedag, heledag} = consultant-tarief (voor latere marge)
  pdf_url text,
  pdf_naam text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Dev: open RLS (consistent met de rest). Wordt later dichtgezet samen met het invul-appje.
alter table consultant enable row level security;
drop policy if exists "consultant open" on consultant;
create policy "consultant open" on consultant for all using (true) with check (true);

-- Storage-bucket voor foto, CV en de gegenereerde 1-pager (publiek leesbaar).
insert into storage.buckets (id, name, public) values ('consultant-fiches', 'consultant-fiches', true)
  on conflict (id) do nothing;
drop policy if exists "consultant-fiches open" on storage.objects;
create policy "consultant-fiches open" on storage.objects for all
  using (bucket_id = 'consultant-fiches') with check (bucket_id = 'consultant-fiches');
