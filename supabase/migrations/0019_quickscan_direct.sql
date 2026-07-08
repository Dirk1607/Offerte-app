-- 0019 — Quickscan rechtstreeks vanuit de publieke scan-pagina wegschrijven.
--
-- Doel:
--  (a) De ruwe antwoorden per vraag bewaren als ENIGE bron van waarheid
--      (domeinscores/labels/gemiddelde blijven herberekenbaar).  [vraag 3]
--  (b) Invuller-gebonden velden (functie, e-mail) op de SCAN-rij i.p.v. op
--      de klant, zodat meerdere personen van hetzelfde bedrijf naast elkaar
--      bewaard blijven zonder elkaar te overschrijven.              [vraag 4]
--  (c) Eén SECURITY DEFINER-functie waarmee de publieke quickscan mag
--      wegschrijven (upsert klant + insert scan) ZONDER dat de anon-key
--      rechtstreeks in de tabellen mag lezen/schrijven.             [vraag 2]
--
-- De bestaande dev-open RLS blijft voorlopig staan (de offerte-app draait nog
-- op de anon-key zonder login); het echt dichtzetten gebeurt samen met de login.

-- ------------------------------------------------------------
-- (a)+(b) Kolommen op de scan-rij
-- ------------------------------------------------------------
alter table quickscan add column if not exists antwoorden       jsonb not null default '{}'::jsonb; -- { "1":2, "2":4, ... } ruwe antwoorden 1..4 per vraag-index
alter table quickscan add column if not exists invuller_functie text;
alter table quickscan add column if not exists invuller_email   text;

-- ------------------------------------------------------------
-- (c) Registratie-functie: aangeroepen door de publieke quickscan.
--     Draait met de rechten van de eigenaar (SECURITY DEFINER), dus de
--     anon-rol heeft zelf GEEN directe tabeltoegang nodig.
-- ------------------------------------------------------------
create or replace function registreer_quickscan(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf  text := btrim(coalesce(payload->>'bedrijf', ''));
  v_klant_id uuid;
  v_scan_id  uuid;
  v_datum    date := coalesce((payload->>'datum')::date, current_date);
  v_invuller text := btrim(coalesce(payload->>'invuller', ''));
begin
  if v_bedrijf = '' then
    raise exception 'bedrijf is verplicht';
  end if;

  -- Klantdossier upserten op genormaliseerde bedrijfsnaam.
  -- Bedrijfsniveau-velden enkel invullen als ze nog leeg zijn (niet overschrijven).
  insert into klant (bedrijf, sector, medewerkers, telefoon, contactpersoon, email)
  values (
    v_bedrijf,
    nullif(btrim(coalesce(payload->>'sector','')), ''),
    nullif(btrim(coalesce(payload->>'medewerkers','')), ''),
    nullif(btrim(coalesce(payload->>'telefoon','')), ''),
    nullif(v_invuller, ''),
    nullif(btrim(coalesce(payload->>'email','')), '')
  )
  on conflict (lower(btrim(bedrijf))) do update set
    sector      = coalesce(klant.sector,      excluded.sector),
    medewerkers = coalesce(klant.medewerkers, excluded.medewerkers),
    telefoon    = coalesce(klant.telefoon,    excluded.telefoon),
    updated_at  = now()
  returning id into v_klant_id;

  -- Scan-rij. Meerdere invullers = meerdere rijen; dezelfde invuller die op
  -- dezelfde dag opnieuw indient, overschrijft zijn eigen rij.
  insert into quickscan (
    klant_id, datum, invuller, invuller_functie, invuller_email,
    gemiddelde_score, scores, labels, antwoorden, ruwe_mail
  )
  values (
    v_klant_id, v_datum, nullif(v_invuller,''),
    nullif(btrim(coalesce(payload->>'invuller_functie','')), ''),
    nullif(btrim(coalesce(payload->>'invuller_email','')), ''),
    (payload->>'gemiddelde')::numeric,
    coalesce(payload->'scores',     '{}'::jsonb),
    coalesce(payload->'labels',     '{}'::jsonb),
    coalesce(payload->'antwoorden', '{}'::jsonb),
    nullif(payload->>'ruwe_mail', '')
  )
  on conflict (klant_id, datum, invuller) do update set
    invuller_functie = excluded.invuller_functie,
    invuller_email   = excluded.invuller_email,
    gemiddelde_score = excluded.gemiddelde_score,
    scores           = excluded.scores,
    labels           = excluded.labels,
    antwoorden       = excluded.antwoorden,
    ruwe_mail        = excluded.ruwe_mail
  returning id into v_scan_id;

  return jsonb_build_object('klant_id', v_klant_id, 'quickscan_id', v_scan_id);
end;
$$;

-- Enkel deze ene functie is aanroepbaar door de publieke (anon) sleutel.
grant execute on function registreer_quickscan(jsonb) to anon, authenticated;
