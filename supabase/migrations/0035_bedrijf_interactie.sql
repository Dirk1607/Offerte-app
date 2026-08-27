-- ============================================================
-- 0035 — Interacties-tijdlijn per bedrijf (mail/call/meeting-log)
-- ============================================================
-- Losse, tijdgestempelde interactie-items per bedrijf (geplakte mailtekst,
-- gespreksnotitie, …) met optioneel een AI-samenvatting erbij — zodat je
-- vóór een volgend contactmoment snel kunt (laten) samenvatten wat er al
-- speelde bij dat bedrijf. Zelfde patroon als contact_notitie (migratie 0033).
--
-- VEILIG / ADDITIEF: enkel een nieuwe tabel.
-- ============================================================

create table if not exists bedrijf_interactie (
  id           uuid primary key default gen_random_uuid(),
  bedrijf_id   uuid not null references bedrijf(id) on delete cascade,
  type         text not null default 'mail',   -- 'mail' | 'call' | 'meeting' | 'anders'
  datum        date not null default current_date,
  ruwe_tekst   text,                            -- geplakte mail/notitie, ongewijzigd
  samenvatting text,                            -- AI- of manuele samenvatting
  auteur       text not null default 'Dirk',
  created_at   timestamptz not null default now()
);

create index if not exists idx_bedrijf_interactie_bedrijf
  on bedrijf_interactie (bedrijf_id, datum desc);

alter table bedrijf_interactie enable row level security;
drop policy if exists tnl_auth_all_bedrijf_interactie on bedrijf_interactie;
create policy tnl_auth_all_bedrijf_interactie on bedrijf_interactie
  for all to authenticated using (true) with check (true);
grant select, insert, update, delete on bedrijf_interactie to authenticated;
revoke all on bedrijf_interactie from anon;

notify pgrst, 'reload schema';
