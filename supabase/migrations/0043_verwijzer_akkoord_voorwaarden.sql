-- ============================================================
-- 0043 — Verwijzers: akkoord met de voorwaarden + extra lead-velden
-- ============================================================
-- (a) Het publieke aanmeld-appje toont eerst de Finder's Fee-voorwaarden
--     (voorwaarden.html) en laat de verwijzer "ik ga akkoord" aanvinken vóór
--     hij kan aanmelden. Dat akkoord (tijdstip + versie) leggen we vast op de
--     verwijzer-rij — "zo goed als contract".
-- (b) Extra (optionele) velden per lead: telefoon van de contactpersoon,
--     sector en aantal werknemers van het bedrijf.
--
-- VEILIG / ADDITIEF: enkel nieuwe kolommen + de bijgewerkte aanmeldfunctie.
-- ============================================================

alter table verwijzer add column if not exists akkoord_voorwaarden_op      timestamptz;
alter table verwijzer add column if not exists akkoord_voorwaarden_versie  text;

alter table verwijzer_lead add column if not exists telefoon          text;
alter table verwijzer_lead add column if not exists sector            text;
alter table verwijzer_lead add column if not exists aantal_werknemers text;

-- ------------------------------------------------------------
-- registreer_verwijzer_aanmelding — zelfde als 0042, plus de velden hierboven.
-- Bij herhaalde aanmelding met dezelfde e-mail wordt het akkoord bijgewerkt
-- naar de meest recente aanvaarding.
-- ------------------------------------------------------------
create or replace function registreer_verwijzer_aanmelding(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v          jsonb := coalesce(payload->'verwijzer', '{}'::jsonb);
  v_email    text  := lower(btrim(coalesce(v->>'email', '')));
  v_id       uuid;
  l          jsonb;
  v_lead_id  uuid;
  v_lead_ids uuid[] := '{}';
  v_aantal   int := 0;
begin
  if v_email = '' then
    raise exception 'e-mail van de verwijzer is verplicht';
  end if;
  if jsonb_array_length(coalesce(payload->'leads', '[]'::jsonb)) = 0 then
    raise exception 'minstens één lead is verplicht';
  end if;

  insert into verwijzer (
    aanspreking, voornaam, achternaam, bedrijf, functie, email, telefoon,
    adres, kan_factureren, ondernemingsnummer,
    akkoord_voorwaarden_op, akkoord_voorwaarden_versie
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
    nullif(btrim(coalesce(v->>'ondernemingsnummer','')), ''),
    case when v ? 'akkoord_voorwaarden_op' and v->>'akkoord_voorwaarden_op' <> ''
         then (v->>'akkoord_voorwaarden_op')::timestamptz end,
    nullif(btrim(coalesce(v->>'akkoord_voorwaarden_versie','')), '')
  )
  on conflict (lower(btrim(email))) do update set
    aanspreking                = coalesce(verwijzer.aanspreking,        excluded.aanspreking),
    voornaam                   = coalesce(verwijzer.voornaam,           excluded.voornaam),
    achternaam                 = coalesce(verwijzer.achternaam,         excluded.achternaam),
    bedrijf                    = coalesce(verwijzer.bedrijf,            excluded.bedrijf),
    functie                    = coalesce(verwijzer.functie,            excluded.functie),
    telefoon                   = coalesce(verwijzer.telefoon,           excluded.telefoon),
    adres                      = coalesce(verwijzer.adres,              excluded.adres),
    kan_factureren             = coalesce(verwijzer.kan_factureren,     excluded.kan_factureren),
    ondernemingsnummer         = coalesce(verwijzer.ondernemingsnummer, excluded.ondernemingsnummer),
    akkoord_voorwaarden_op     = coalesce(excluded.akkoord_voorwaarden_op,     verwijzer.akkoord_voorwaarden_op),
    akkoord_voorwaarden_versie = coalesce(excluded.akkoord_voorwaarden_versie, verwijzer.akkoord_voorwaarden_versie),
    updated_at                 = now()
  returning id into v_id;

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
      email, telefoon, sector, aantal_werknemers, kwalificatienota,
      relatie_tot_contact, al_gesproken, signaal, ingeschatte_uitdaging, urgentie, naam_noemen,
      ai_score, ai_niveau, ai_beoordeling, ai_advies
    )
    values (
      v_id,
      nullif(btrim(coalesce(l->>'aanspreking','')), ''),
      nullif(btrim(coalesce(l->>'voornaam','')), ''),
      nullif(btrim(coalesce(l->>'achternaam','')), ''),
      btrim(l->>'bedrijf'),
      nullif(btrim(coalesce(l->>'functietitel','')), ''),
      nullif(btrim(coalesce(l->>'email','')), ''),
      nullif(btrim(coalesce(l->>'telefoon','')), ''),
      nullif(btrim(coalesce(l->>'sector','')), ''),
      nullif(btrim(coalesce(l->>'aantal_werknemers','')), ''),
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

grant execute on function registreer_verwijzer_aanmelding(jsonb) to anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- ROLLBACK:
--   alter table verwijzer_lead drop column if exists aantal_werknemers;
--   alter table verwijzer_lead drop column if exists sector;
--   alter table verwijzer_lead drop column if exists telefoon;
--   alter table verwijzer drop column if exists akkoord_voorwaarden_op;
--   alter table verwijzer drop column if exists akkoord_voorwaarden_versie;
--   notify pgrst, 'reload schema';
-- ============================================================
