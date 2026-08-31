-- ============================================================
-- 0042 — Verwijzers (Finder's Fee): aanmeldsysteem voor aanbrengers
-- ============================================================
-- Freelance consultants ("verwijzers"/"aanbrengers") melden via een APART
-- publiek appje (aanmelden.thenextlevel.consulting) een bedrijf ("lead") aan.
-- Die data komt hier terecht; de opvolging gebeurt door Dirk in de Offerte-app
-- (nieuwe "Verwijzers"-tab). De verwijzer heeft GEEN login en GEEN tabeltoegang.
--
-- Isolatiemodel = exact dat van de publieke QuickScan (migratie 0019/0026):
--   • RLS: enkel 'authenticated' mag lezen/schrijven  → dus enkel Dirk, ingelogd.
--   • anon schrijft uitsluitend via één SECURITY DEFINER-functie
--     (registreer_verwijzer_aanmelding) — nooit rechtstreeks in de tabellen.
--   • De AI-beoordeling van een lead gebeurt server-side in de Edge Function
--     'verwijzer-intake' (die de Claude-sleutel als secret houdt) en geeft de
--     score/het advies mee aan deze functie; anon ziet de tabellen nooit.
--
-- VEILIG / ADDITIEF: enkel nieuwe tabellen + één nieuwe functie.
-- Terugdraaien: zie het ROLLBACK-blok onderaan.
-- ============================================================

-- ------------------------------------------------------------
-- (1) VERWIJZER — de aanbrenger zelf. Eén rij per persoon (op e-mail).
-- ------------------------------------------------------------
create table if not exists verwijzer (
  id                uuid primary key default gen_random_uuid(),
  aanspreking       text,                              -- 'Dhr' | 'Mevr'
  voornaam          text,
  achternaam        text,
  bedrijf           text,                              -- vennootschap/eenmanszaak van de verwijzer
  functie           text,
  email             text not null,
  telefoon          text,
  adres             text,
  kan_factureren    boolean,                           -- nee = buiten scope v1 (spec §8)
  ondernemingsnummer text,
  status            text not null default 'nieuw',     -- 'nieuw' | 'actief' | 'gestopt'
  contact_id        uuid references contact(id) on delete set null,  -- de B_lead_generator-contactrij (gevuld bij bevestiging)
  opmerking_intern  text,                              -- enkel voor Dirk
  aangemeld_at      timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- Eén verwijzer per e-mailadres (upsert-sleutel voor de aanmeldfunctie).
create unique index if not exists verwijzer_email_uniek on verwijzer (lower(btrim(email)));

alter table verwijzer drop constraint if exists verwijzer_status_check;
alter table verwijzer add constraint verwijzer_status_check
  check (status in ('nieuw', 'actief', 'gestopt'));

drop trigger if exists trg_verwijzer_updated on verwijzer;
create trigger trg_verwijzer_updated
  before update on verwijzer
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- (2) VERWIJZER_LEAD — één aangemeld bedrijf. Timestamp = officiële
--     aanmelddatum (spec §6, "eerste-aanmelding-geldt").
-- ------------------------------------------------------------
create table if not exists verwijzer_lead (
  id                   uuid primary key default gen_random_uuid(),
  verwijzer_id         uuid not null references verwijzer(id) on delete cascade,

  -- Spec §6 — verplichte velden van de aangemelde contactpersoon.
  aanspreking          text,
  voornaam             text,
  achternaam           text,
  bedrijf              text not null,
  functietitel         text,
  adres                text,
  email                text,
  kwalificatienota     text not null,                  -- spec §6: 1 zin, verplicht

  -- Extra kwalificatievragen (sturen op "warm", niet blokkerend).
  relatie_tot_contact  text,   -- oud_collega | klant_van_mij | netwerkcontact | vriend_familie | anders
  al_gesproken         text,   -- nog_niet | kort_vermeld | verwacht_contact
  signaal              text,   -- concreet signaal / aanleiding (waarom nu?)
  ingeschatte_uitdaging text,
  urgentie             text,   -- nu | zes_maanden | geen_timing
  naam_noemen          boolean,-- mag TNL de verwijzer vermelden bij contactname?

  -- AI-beoordeling (ingevuld door de Edge Function 'verwijzer-intake').
  ai_score             int,                            -- 0..100
  ai_niveau            text,                            -- 'koud' | 'lauw' | 'warm'
  ai_beoordeling       jsonb,                           -- volledige rubric-output
  ai_advies            text,

  -- Opvolging door Dirk.
  status               text not null default 'aangemeld',
    -- 'aangemeld' | 'in_behandeling' | 'geregistreerd' | 'geweigerd' | 'dubbel'
  reden_weigering      text,                            -- intern, niet naar de verwijzer
  behandeld_at         timestamptz,
  bedrijf_id           uuid references bedrijf(id) on delete set null,   -- gevuld bij promotie
  contact_id           uuid references contact(id) on delete set null,   -- gevuld bij promotie

  aangemeld_at         timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists idx_verwijzer_lead_verwijzer on verwijzer_lead (verwijzer_id);
create index if not exists idx_verwijzer_lead_status     on verwijzer_lead (status);
create index if not exists idx_verwijzer_lead_open       on verwijzer_lead (aangemeld_at) where status = 'aangemeld';

alter table verwijzer_lead drop constraint if exists verwijzer_lead_status_check;
alter table verwijzer_lead add constraint verwijzer_lead_status_check check (
  status in ('aangemeld', 'in_behandeling', 'geregistreerd', 'geweigerd', 'dubbel')
);

alter table verwijzer_lead drop constraint if exists verwijzer_lead_niveau_check;
alter table verwijzer_lead add constraint verwijzer_lead_niveau_check check (
  ai_niveau is null or ai_niveau in ('koud', 'lauw', 'warm')
);

drop trigger if exists trg_verwijzer_lead_updated on verwijzer_lead;
create trigger trg_verwijzer_lead_updated
  before update on verwijzer_lead
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- (3) RLS — enkel ingelogde gebruikers (= Dirk in de Offerte-app).
--     Zelfde patroon als contact_notitie / bedrijf_interactie.
-- ------------------------------------------------------------
alter table verwijzer      enable row level security;
alter table verwijzer_lead enable row level security;

drop policy if exists tnl_auth_all_verwijzer on verwijzer;
create policy tnl_auth_all_verwijzer on verwijzer
  for all to authenticated using (true) with check (true);

drop policy if exists tnl_auth_all_verwijzer_lead on verwijzer_lead;
create policy tnl_auth_all_verwijzer_lead on verwijzer_lead
  for all to authenticated using (true) with check (true);

grant select, insert, update, delete on verwijzer      to authenticated;
grant select, insert, update, delete on verwijzer_lead to authenticated;
revoke all on verwijzer      from anon;
revoke all on verwijzer_lead from anon;

-- ------------------------------------------------------------
-- (4) SECURITY DEFINER-functie: het publieke appje meldt hiermee aan
--     ZONDER tabeltoegang. De Edge Function roept ze aan met de anon-key,
--     nadat ze de AI-score per lead heeft berekend.
--
--     payload = {
--       verwijzer: { aanspreking, voornaam, achternaam, bedrijf, functie,
--                    email, telefoon, adres, kan_factureren, ondernemingsnummer },
--       leads: [ { aanspreking, voornaam, achternaam, bedrijf, functietitel,
--                  adres, email, kwalificatienota, relatie_tot_contact,
--                  al_gesproken, signaal, ingeschatte_uitdaging, urgentie,
--                  naam_noemen, ai_score, ai_niveau, ai_beoordeling, ai_advies } ]
--     }
-- ------------------------------------------------------------
create or replace function registreer_verwijzer_aanmelding(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v         jsonb := coalesce(payload->'verwijzer', '{}'::jsonb);
  v_email   text  := lower(btrim(coalesce(v->>'email', '')));
  v_id      uuid;
  l         jsonb;
  v_lead_id uuid;
  v_lead_ids uuid[] := '{}';
  v_aantal  int := 0;
begin
  if v_email = '' then
    raise exception 'e-mail van de verwijzer is verplicht';
  end if;
  if jsonb_array_length(coalesce(payload->'leads', '[]'::jsonb)) = 0 then
    raise exception 'minstens één lead is verplicht';
  end if;

  -- Verwijzer upserten op e-mail. Bestaande gegevens enkel aanvullen waar leeg
  -- (de verwijzer kan later opnieuw aanmelden met dezelfde mail).
  insert into verwijzer (
    aanspreking, voornaam, achternaam, bedrijf, functie, email, telefoon,
    adres, kan_factureren, ondernemingsnummer
  )
  values (
    nullif(btrim(coalesce(v->>'aanspreking','')), ''),
    nullif(btrim(coalesce(v->>'voornaam','')), ''),
    nullif(btrim(coalesce(v->>'achternaam','')), ''),
    nullif(btrim(coalesce(v->>'bedrijf','')), ''),
    nullif(btrim(coalesce(v->>'functie','')), ''),
    btrim(coalesce(v->>'email','')),
    nullif(btrim(coalesce(v->>'telefoon','')), ''),
    nullif(btrim(coalesce(v->>'adres','')), ''),
    case when v ? 'kan_factureren' and v->>'kan_factureren' <> '' then (v->>'kan_factureren')::boolean end,
    nullif(btrim(coalesce(v->>'ondernemingsnummer','')), '')
  )
  on conflict (lower(btrim(email))) do update set
    aanspreking        = coalesce(verwijzer.aanspreking,        excluded.aanspreking),
    voornaam           = coalesce(verwijzer.voornaam,           excluded.voornaam),
    achternaam         = coalesce(verwijzer.achternaam,         excluded.achternaam),
    bedrijf            = coalesce(verwijzer.bedrijf,            excluded.bedrijf),
    functie            = coalesce(verwijzer.functie,            excluded.functie),
    telefoon           = coalesce(verwijzer.telefoon,           excluded.telefoon),
    adres              = coalesce(verwijzer.adres,              excluded.adres),
    kan_factureren     = coalesce(verwijzer.kan_factureren,     excluded.kan_factureren),
    ondernemingsnummer = coalesce(verwijzer.ondernemingsnummer, excluded.ondernemingsnummer),
    updated_at         = now()
  returning id into v_id;

  -- Eén rij per lead. Timestamp (aangemeld_at) = officiële aanmelddatum.
  for l in select * from jsonb_array_elements(payload->'leads')
  loop
    if btrim(coalesce(l->>'bedrijf','')) = '' then
      raise exception 'lead zonder bedrijf';
    end if;
    if btrim(coalesce(l->>'kwalificatienota','')) = '' then
      raise exception 'lead zonder kwalificatienota (verplicht)';
    end if;

    insert into verwijzer_lead (
      verwijzer_id, aanspreking, voornaam, achternaam, bedrijf, functietitel,
      adres, email, kwalificatienota, relatie_tot_contact, al_gesproken, signaal,
      ingeschatte_uitdaging, urgentie, naam_noemen,
      ai_score, ai_niveau, ai_beoordeling, ai_advies
    )
    values (
      v_id,
      nullif(btrim(coalesce(l->>'aanspreking','')), ''),
      nullif(btrim(coalesce(l->>'voornaam','')), ''),
      nullif(btrim(coalesce(l->>'achternaam','')), ''),
      btrim(l->>'bedrijf'),
      nullif(btrim(coalesce(l->>'functietitel','')), ''),
      nullif(btrim(coalesce(l->>'adres','')), ''),
      nullif(btrim(coalesce(l->>'email','')), ''),
      btrim(l->>'kwalificatienota'),
      nullif(btrim(coalesce(l->>'relatie_tot_contact','')), ''),
      nullif(btrim(coalesce(l->>'al_gesproken','')), ''),
      nullif(btrim(coalesce(l->>'signaal','')), ''),
      nullif(btrim(coalesce(l->>'ingeschatte_uitdaging','')), ''),
      nullif(btrim(coalesce(l->>'urgentie','')), ''),
      case when l ? 'naam_noemen' and l->>'naam_noemen' <> '' then (l->>'naam_noemen')::boolean end,
      case when l ? 'ai_score' and l->>'ai_score' <> '' then (l->>'ai_score')::int end,
      nullif(btrim(coalesce(l->>'ai_niveau','')), ''),
      l->'ai_beoordeling',
      nullif(btrim(coalesce(l->>'ai_advies','')), '')
    )
    returning id into v_lead_id;

    v_lead_ids := v_lead_ids || v_lead_id;
    v_aantal := v_aantal + 1;
  end loop;

  return jsonb_build_object('verwijzer_id', v_id, 'lead_ids', to_jsonb(v_lead_ids), 'aantal', v_aantal);
end;
$$;

-- Enkel deze ene functie is aanroepbaar met de publieke (anon) sleutel.
grant execute on function registreer_verwijzer_aanmelding(jsonb) to anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- VERIFICATIE (na het draaien), met de PUBLISHABLE (anon) key:
--   curl -s -o /dev/null -w "%{http_code}\n" \
--     -H "apikey: <anon>" -H "Authorization: Bearer <anon>" \
--     "https://sphmxlfpzzowsekzjltd.supabase.co/rest/v1/verwijzer?select=id&limit=1"
--   -> verwacht 401/403 of []  (anon mag de tabel niet lezen).
--   De aanmeldfunctie moet wél werken:
--   curl -s -X POST \
--     -H "apikey: <anon>" -H "Authorization: Bearer <anon>" -H "content-type: application/json" \
--     -d '{"payload":{"verwijzer":{"email":"test@example.com","voornaam":"Test"},"leads":[{"bedrijf":"ACME","kwalificatienota":"test"}]}}' \
--     "https://sphmxlfpzzowsekzjltd.supabase.co/rest/v1/rpc/registreer_verwijzer_aanmelding"
-- ============================================================

-- ============================================================
-- ROLLBACK (indien nodig):
--   drop function if exists registreer_verwijzer_aanmelding(jsonb);
--   drop table if exists verwijzer_lead;
--   drop table if exists verwijzer;
--   notify pgrst, 'reload schema';
-- ============================================================
