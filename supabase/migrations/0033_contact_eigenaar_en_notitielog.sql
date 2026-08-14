-- ============================================================
-- 0033 — Eigenaar per prospect (Dirk/Ilse) + echte per-auteur notitielog
-- ============================================================
-- (a) contact.eigenaar: wie deze prospect "bezit" (vrije tekst, net als status/
--     cat1/cat2 elders in dit schema — geen check-constraint, de UI biedt een
--     vaste keuzelijst aan). Bestaande rijen krijgen automatisch 'Dirk' mee
--     via de DEFAULT (dit waren tot nu toe allemaal Dirk z'n prospects).
alter table contact add column if not exists eigenaar text not null default 'Dirk';

-- (b) contact_notitie: losse, tijdgestempelde notitie-items per contact i.p.v.
--     één gedeeld vrij-tekstveld (contact.verloop) — zodat bij gebruik door
--     meerdere personen elke notitie een auteur en eigen tijdstip heeft i.p.v.
--     "laatste opslag wint, wie schreef wat is onbekend".
create table if not exists contact_notitie (
  id         uuid primary key default gen_random_uuid(),
  contact_id uuid not null references contact(id) on delete cascade,
  auteur     text not null,
  tekst      text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_contact_notitie_contact
  on contact_notitie (contact_id, created_at desc);

alter table contact_notitie enable row level security;
drop policy if exists tnl_auth_all_contact_notitie on contact_notitie;
create policy tnl_auth_all_contact_notitie on contact_notitie
  for all to authenticated using (true) with check (true);
grant select, insert, update, delete on contact_notitie to authenticated;
revoke all on contact_notitie from anon;

-- (c) bestaande contact.verloop-tekst (het oude gedeelde vrije-tekstveld) ÉÉNMALIG
--     overzetten naar één notitie-item per contact, zodat lopende geschiedenis niet
--     verloren gaat. contact.verloop zelf blijft ongewijzigd bestaan (de
--     prospects-compat-view uit 0024/0028 leest 'm nog) maar wordt door de app
--     niet langer gebruikt/getoond.
insert into contact_notitie (contact_id, auteur, tekst, created_at)
select id, 'Dirk', verloop, coalesce(updated_at, created_at)
from contact
where verloop is not null and btrim(verloop) <> '';

notify pgrst, 'reload schema';
