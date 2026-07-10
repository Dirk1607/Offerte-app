-- ============================================================
-- 0030 — Zelfbeschrijvende quickscan: bewaar de vragen mee met de scan
-- ============================================================
-- De quickscan stuurt nu payload.vragen mee = een lijst [{h,n,t}] index-gelijk
-- met payload.antwoorden. Zo blijft de koppeling antwoord→vraag→lijn/versneller
-- betrouwbaar, ook als de vragenlijst later wijzigt (geen afhankelijkheid meer
-- van een hardgecodeerde kopie in de offerte-app).
--
-- Bevat: nieuwe kolom quickscan.vragen (jsonb) + registreer_quickscan die ze
-- opslaat. Voor de rest identiek aan 0029 (koppel-gedrag, sector/medewerkers).
-- ============================================================

alter table public.quickscan
  add column if not exists vragen jsonb;

create or replace function registreer_quickscan(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf     text := btrim(coalesce(payload->>'bedrijf', ''));
  v_invuller    text := btrim(coalesce(payload->>'invuller', ''));
  v_sector      text := nullif(btrim(coalesce(payload->>'sector', '')), '');
  v_medewerkers text := nullif(btrim(coalesce(payload->>'medewerkers', '')), '');
  v_functie     text := nullif(btrim(coalesce(payload->>'invuller_functie', '')), '');
  v_email       text := nullif(btrim(coalesce(payload->>'invuller_email', payload->>'email', '')), '');
  v_tel         text := nullif(btrim(coalesce(payload->>'telefoon', '')), '');
  v_datum       date := coalesce((payload->>'datum')::date, current_date);
  v_voornaam    text := nullif(split_part(v_invuller, ' ', 1), '');
  v_achternaam  text := nullif(btrim(substr(v_invuller, length(coalesce(split_part(v_invuller,' ',1),'')) + 1)), '');
  v_koppel      boolean := lower(coalesce(payload->>'koppel','')) in ('ja','true','1','y','yes');
  v_klant_id    uuid;
  v_bedrijf_id  uuid;
  v_contact_id  uuid;
  v_scan_id     uuid;
  r_bedrijf     bedrijf%rowtype;
  r_contact     contact%rowtype;
begin
  if v_bedrijf = '' then
    raise exception 'bedrijf is verplicht';
  end if;

  -- (1) OUD dossier — terugval.
  insert into klant (bedrijf, sector, medewerkers, telefoon, contactpersoon, email)
  values (v_bedrijf, v_sector, v_medewerkers, v_tel, nullif(v_invuller, ''), v_email)
  on conflict (lower(btrim(bedrijf))) do update set
    sector      = coalesce(klant.sector,      excluded.sector),
    medewerkers = coalesce(klant.medewerkers, excluded.medewerkers),
    telefoon    = coalesce(klant.telefoon,    excluded.telefoon),
    updated_at  = now()
  returning id into v_klant_id;

  -- (2+3) NIEUW model — ENKEL bij expliciet koppelen (manuele plak-tab).
  if v_koppel then
    select * into r_bedrijf from bedrijf where naam_norm = norm_naam(v_bedrijf) limit 1;
    if not found then
      insert into bedrijf (naam, sector, aantal_medewerkers, status, bron)
      values (v_bedrijf, v_sector, v_medewerkers, 'prospect', 'quickscan')
      returning id into v_bedrijf_id;
    else
      v_bedrijf_id := r_bedrijf.id;
      perform log_wijziging_voorstel('bedrijf', v_bedrijf_id, 'sector',             r_bedrijf.sector,             v_sector,      'quickscan');
      perform log_wijziging_voorstel('bedrijf', v_bedrijf_id, 'aantal_medewerkers', r_bedrijf.aantal_medewerkers, v_medewerkers, 'quickscan');
      update bedrijf set
        sector             = coalesce(sector,             v_sector),
        aantal_medewerkers = coalesce(aantal_medewerkers, v_medewerkers)
      where id = v_bedrijf_id;
    end if;

    if v_email is not null then
      select * into r_contact from contact
        where bedrijf_id = v_bedrijf_id and lower(email) = lower(v_email) limit 1;
    end if;
    if r_contact.id is null and v_invuller <> '' then
      select * into r_contact from contact
        where bedrijf_id = v_bedrijf_id
          and lower(btrim(coalesce(voornaam,'') || ' ' || coalesce(achternaam,''))) = lower(v_invuller)
        limit 1;
    end if;

    if r_contact.id is null then
      insert into contact (bedrijf_id, voornaam, achternaam, email, gsm, functie, quickscan_ingevuld, status, bron)
      values (v_bedrijf_id, v_voornaam, v_achternaam, v_email, v_tel, v_functie, true, 'Quickscan ingevuld', 'quickscan')
      returning id into v_contact_id;
    else
      v_contact_id := r_contact.id;
      perform log_wijziging_voorstel('contact', v_contact_id, 'functie', r_contact.functie, v_functie, 'quickscan');
      perform log_wijziging_voorstel('contact', v_contact_id, 'gsm',     r_contact.gsm,     v_tel,     'quickscan');
      perform log_wijziging_voorstel('contact', v_contact_id, 'email',   r_contact.email,   v_email,   'quickscan');
      update contact set
        functie            = coalesce(functie, v_functie),
        gsm                = coalesce(gsm,     v_tel),
        email              = coalesce(email,   v_email),
        status             = 'Quickscan ingevuld',
        quickscan_ingevuld = true
      where id = v_contact_id;
    end if;
  end if;

  -- (4) Scan-rij — incl. de zelfbeschrijvende vragen-lijst.
  insert into quickscan (
    klant_id, bedrijf_id, contact_id, datum, invuller, invuller_functie, invuller_email,
    gemiddelde_score, scores, labels, antwoorden, vragen, ruwe_mail, sector, medewerkers
  )
  values (
    v_klant_id, v_bedrijf_id, v_contact_id, v_datum, nullif(v_invuller, ''), v_functie, v_email,
    (payload->>'gemiddelde')::numeric,
    coalesce(payload->'scores',     '{}'::jsonb),
    coalesce(payload->'labels',     '{}'::jsonb),
    coalesce(payload->'antwoorden', '{}'::jsonb),
    payload->'vragen',
    nullif(payload->>'ruwe_mail', ''),
    v_sector, v_medewerkers
  )
  on conflict (klant_id, datum, invuller) do update set
    bedrijf_id       = coalesce(excluded.bedrijf_id, quickscan.bedrijf_id),
    contact_id       = coalesce(excluded.contact_id, quickscan.contact_id),
    invuller_functie = excluded.invuller_functie,
    invuller_email   = excluded.invuller_email,
    gemiddelde_score = excluded.gemiddelde_score,
    scores           = excluded.scores,
    labels           = excluded.labels,
    antwoorden       = excluded.antwoorden,
    vragen           = coalesce(excluded.vragen, quickscan.vragen),
    ruwe_mail        = excluded.ruwe_mail,
    sector           = coalesce(excluded.sector,      quickscan.sector),
    medewerkers      = coalesce(excluded.medewerkers, quickscan.medewerkers)
  returning id into v_scan_id;

  return jsonb_build_object(
    'klant_id', v_klant_id, 'bedrijf_id', v_bedrijf_id,
    'contact_id', v_contact_id, 'quickscan_id', v_scan_id
  );
end;
$$;

grant execute on function registreer_quickscan(jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
