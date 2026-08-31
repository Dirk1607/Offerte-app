-- ============================================================
-- 0044 — Introducer-gegevens ophalen bij een nieuwe aanmelding
-- ============================================================
-- Wie al eens een bedrijf aanmeldde, moet de maand nadien niet opnieuw al zijn
-- eigen gegevens intypen. Het publieke aanmeld-appje
-- (aanmelden.thenextlevel.consulting) biedt daarom "Al eens aangemeld? Vul je
-- gegevens automatisch in": de introducer geeft e-mail + achternaam op en de
-- pagina vult "Jouw gegevens" voor.
--
-- Isolatiemodel = exact dat van 0042/0043:
--   • anon heeft GEEN tabeltoegang; alles loopt via SECURITY DEFINER-functies.
--   • Deze functie geeft ENKEL de eigen, herbruikbare velden van één introducer
--     terug, en enkel bij een EXACTE match op e-mail EN achternaam samen.
--     Nooit interne velden (status, opmerking_intern, akkoord…), geen lijst,
--     geen "lijkt op". Kent iemand enkel een e-mailadres, dan krijgt hij niets.
--
-- VEILIG / ADDITIEF: enkel één nieuwe functie. Geen tabel- of kolomwijziging.
-- Terugdraaien = het ROLLBACK-blok onderaan (één drop). Na terugdraaien faalt
-- de "gegevens ophalen"-knop stil; de aanmeldpagina blijft verder werken.
-- ============================================================

create or replace function introducer_ophalen(p_email text, p_achternaam text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r verwijzer%rowtype;
begin
  -- Beide velden verplicht — e-mail alleen volstaat bewust niet.
  if btrim(coalesce(p_email, '')) = '' or btrim(coalesce(p_achternaam, '')) = '' then
    return null;
  end if;

  select * into r
  from verwijzer
  where lower(btrim(email)) = lower(btrim(p_email))
    and lower(btrim(coalesce(achternaam, ''))) = lower(btrim(p_achternaam))
  limit 1;

  if not found then
    return null;
  end if;

  -- Enkel de velden die "Jouw gegevens" op de aanmeldpagina nodig heeft.
  return jsonb_build_object(
    'aanspreking',        r.aanspreking,
    'voornaam',           r.voornaam,
    'achternaam',         r.achternaam,
    'bedrijf',            r.bedrijf,
    'functie',            r.functie,
    'email',              r.email,
    'telefoon',           r.telefoon,
    'adres',              r.adres,
    'ondernemingsnummer', r.ondernemingsnummer
  );
end;
$$;

revoke execute on function introducer_ophalen(text, text) from public;
grant  execute on function introducer_ophalen(text, text) to anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- VERIFICATIE (met de PUBLISHABLE / anon key):
--   curl -s -X POST \
--     -H "apikey: <anon>" -H "Authorization: Bearer <anon>" -H "content-type: application/json" \
--     -d '{"p_email":"bestaand@adres.be","p_achternaam":"Peeters"}' \
--     "https://sphmxlfpzzowsekzjltd.supabase.co/rest/v1/rpc/introducer_ophalen"
--   -> JSON met de velden bij match; 'null' bij geen match of ontbrekend veld.
--   Tabel blijft onleesbaar voor anon:
--   curl -s -o /dev/null -w "%{http_code}\n" \
--     -H "apikey: <anon>" -H "Authorization: Bearer <anon>" \
--     "https://sphmxlfpzzowsekzjltd.supabase.co/rest/v1/verwijzer?select=id&limit=1"  -> 401/403 of []
-- ============================================================

-- ============================================================
-- ROLLBACK (indien de functie niet bevalt):
--   drop function if exists introducer_ophalen(text, text);
--   notify pgrst, 'reload schema';
-- ============================================================
