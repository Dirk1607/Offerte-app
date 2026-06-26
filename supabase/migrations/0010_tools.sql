-- 0010 — Tools-catalogus (productfiches) + koppeling aan NextStones + storage-bucket.
create table if not exists tools (
  id uuid primary key default gen_random_uuid(),
  naam text not null,
  afkorting text,
  type text,
  url text,
  toegang text,
  taal text default 'Nederlands',
  versie text,
  kernwaarde text,
  unieke_kenmerken jsonb not null default '[]'::jsonb,
  modules jsonb not null default '[]'::jsonb,          -- [{naam, omschrijving, wie_beheert}]
  input jsonb not null default '[]'::jsonb,             -- [string]
  output jsonb not null default '[]'::jsonb,            -- [string]
  tnl_setup jsonb not null default '[]'::jsonb,         -- [{label, omschrijving}]
  klant_beheert jsonb not null default '[]'::jsonb,     -- [{label, omschrijving}]
  maatwerk jsonb not null default '[]'::jsonb,          -- [{item, omschrijving, aanpak}]
  rekeningstructuur jsonb not null default '[]'::jsonb, -- [{rubriek, cluster, voorbeeldrekeningen}]
  notities text,
  gerelateerde_nextstones jsonb not null default '[]'::jsonb,   -- [string]
  toekomstige_nextstones jsonb not null default '[]'::jsonb,    -- [string]
  pdf_url text,
  pdf_naam text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table tools enable row level security;
drop policy if exists "tools open" on tools;
create policy "tools open" on tools for all using (true) with check (true);

-- Koppeling NextStone -> tools: jsonb-array van tool-ids op het artikel (consistent met wbs/clusters/deliverables).
alter table artikel add column if not exists tool_ids jsonb not null default '[]'::jsonb;

-- Storage-bucket voor de gegenereerde productfiches (publiek leesbaar).
insert into storage.buckets (id, name, public) values ('tool-fiches', 'tool-fiches', true)
  on conflict (id) do nothing;
drop policy if exists "tool-fiches open" on storage.objects;
create policy "tool-fiches open" on storage.objects for all
  using (bucket_id = 'tool-fiches') with check (bucket_id = 'tool-fiches');
