-- 0013 — App-brede instellingen (key-value). Eerste gebruik: km-vergoeding.
-- waarde voor sleutel 'km_vergoeding' = { kost_per_km, snelheid_kmu, uren_factor }
create table if not exists instellingen (
  sleutel text primary key,
  waarde jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table instellingen enable row level security;
drop policy if exists "instellingen open" on instellingen;
create policy "instellingen open" on instellingen for all using (true) with check (true);
