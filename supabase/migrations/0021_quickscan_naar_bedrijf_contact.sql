-- ============================================================
-- 0021 — UNIFICATIE, FASE 3: quickscan schrijft ook naar bedrijf + contact
-- ============================================================
-- registreer_quickscan() upsertte tot nu toe enkel het OUDE dossier
-- (klant + quickscan.klant_id). Deze migratie breidt de functie ADDITIEF uit:
--
--   1. het oude klant-pad blijft volledig behouden (terugval/vangnet);
--   2. daarnaast wordt nu ook een `bedrijf` (op genormaliseerde naam) en een
--      `contact` (op e-mail, anders naam) aangemaakt/bijgewerkt;
--   3. de scan-rij krijgt bedrijf_id + contact_id mee.
--
-- VOEDINGSREGEL:
--   • lege velden op bedrijf/contact worden meteen aangevuld;
--   • een AFWIJKENDE waarde voor een reeds ingevuld veld overschrijft NIET,
--     maar komt als voorstel in `wijziging_voorstel` (status 'open') en wacht
--     op goedkeuring in de app.
--
-- Niets aan de publieke quickscan-pagina hoeft te wijzigen: de payload die ze
-- al stuurt (bedrijf/invuller/email/functie/sector/medewerkers/telefoon/…)
-- volstaat. VEILIG: enkel een functie herschrijven + 1 hulpfunctie toevoegen.
-- ============================================================

-- ------------------------------------------------------------
-- Hulpfunctie: log een wijzigingsvoorstel, MAAR alleen als het echt een
-- botsing is (nieuw niet leeg, oud niet leeg, verschillend) en er nog geen
-- identiek open voorstel bestaat. Lege velden worden elders auto-aangevuld.
-- ------------------------------------------------------------
create or replace function log_wijziging_voorstel(
  p_entiteit text, p_record uuid, p_veld text,
  p_oud text, p_nieuw text, p_bron text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  p_nieuw := nullif(btrim(coalesce(p_nieuw, '')), '');
  p_oud   := nullif(btrim(coalesce(p_oud, '')), '');
  if p_nieuw is null then return; end if;                 -- niets nieuws aangeleverd
  if p_oud   is null then return; end if;                 -- leeg veld → wordt auto-gevuld
  if lower(p_oud) = lower(p_nieuw) then return; end if;    -- feitelijk gelijk
  if exists (
    select 1 from wijziging_voorstel
    where entiteit = p_entiteit and record_id = p_record and veld = p_veld
      and nieuwe_waarde = p_nieuw and status = 'open'
  ) then return; end if;                                   -- al in de wachtrij
  insert into wijziging_voorstel (entiteit, record_id, veld, oude_waarde, nieuwe_waarde, bron)
  values (p_entiteit, p_record, p_veld, p_oud, p_nieuw, p_bron);
end $$;

-- ------------------------------------------------------------
-- Herschreven registratie-functie.
-- ------------------------------------------------------------
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

  -- ========================================================
  -- (1) OUD dossier — ongewijzigd behouden als terugval.
  -- ========================================================
  insert into klant (bedrijf, sector, medewerkers, telefoon, contactpersoon, email)
  values (v_bedrijf, v_sector, v_medewerkers, v_tel, nullif(v_invuller, ''), v_email)
  on conflict (lower(btrim(bedrijf))) do update set
    sector      = coalesce(klant.sector,      excluded.sector),
    medewerkers = coalesce(klant.medewerkers, excluded.medewerkers),
    telefoon    = coalesce(klant.telefoon,    excluded.telefoon),
    updated_at  = now()
  returning id into v_klant_id;

  -- ========================================================
  -- (2) NIEUW model — bedrijf (match op genormaliseerde naam).
  -- ========================================================
  select * into r_bedrijf from bedrijf where naam_norm = norm_naam(v_bedrijf) limit 1;
  if not found then
    insert into bedrijf (naam, sector, aantal_medewerkers, status, bron)
    values (v_bedrijf, v_sector, v_medewerkers, 'prospect', 'quickscan')
    returning id into v_bedrijf_id;
  else
    v_bedrijf_id := r_bedrijf.id;
    -- afwijkende ingevulde waarde → voorstel; leeg → hieronder auto-aanvullen
    perform log_wijziging_voorstel('bedrijf', v_bedrijf_id, 'sector',             r_bedrijf.sector,             v_sector,      'quickscan');
    perform log_wijziging_voorstel('bedrijf', v_bedrijf_id, 'aantal_medewerkers', r_bedrijf.aantal_medewerkers, v_medewerkers, 'quickscan');
    update bedrijf set
      sector             = coalesce(sector,             v_sector),
      aantal_medewerkers = coalesce(aantal_medewerkers, v_medewerkers)
    where id = v_bedrijf_id;
  end if;

  -- ========================================================
  -- (3) NIEUW model — contact (match op e-mail binnen het bedrijf, anders naam).
  -- ========================================================
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
    insert into contact (bedrijf_id, voornaam, achternaam, email, gsm, functie, quickscan_ingevuld, bron)
    values (v_bedrijf_id, v_voornaam, v_achternaam, v_email, v_tel, v_functie, true, 'quickscan')
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
      quickscan_ingevuld = true
    where id = v_contact_id;
  end if;

  -- ========================================================
  -- (4) Scan-rij — klant_id (verplicht, terugval) + bedrijf_id + contact_id.
  -- ========================================================
  insert into quickscan (
    klant_id, bedrijf_id, contact_id, datum, invuller, invuller_functie, invuller_email,
    gemiddelde_score, scores, labels, antwoorden, ruwe_mail
  )
  values (
    v_klant_id, v_bedrijf_id, v_contact_id, v_datum, nullif(v_invuller, ''), v_functie, v_email,
    (payload->>'gemiddelde')::numeric,
    coalesce(payload->'scores',     '{}'::jsonb),
    coalesce(payload->'labels',     '{}'::jsonb),
    coalesce(payload->'antwoorden', '{}'::jsonb),
    nullif(payload->>'ruwe_mail', '')
  )
  on conflict (klant_id, datum, invuller) do update set
    bedrijf_id       = excluded.bedrijf_id,
    contact_id       = excluded.contact_id,
    invuller_functie = excluded.invuller_functie,
    invuller_email   = excluded.invuller_email,
    gemiddelde_score = excluded.gemiddelde_score,
    scores           = excluded.scores,
    labels           = excluded.labels,
    antwoorden       = excluded.antwoorden,
    ruwe_mail        = excluded.ruwe_mail
  returning id into v_scan_id;

  return jsonb_build_object(
    'klant_id', v_klant_id, 'bedrijf_id', v_bedrijf_id,
    'contact_id', v_contact_id, 'quickscan_id', v_scan_id
  );
end;
$$;

grant execute on function registreer_quickscan(jsonb) to anon, authenticated;
