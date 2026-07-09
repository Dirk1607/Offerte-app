-- ============================================================
-- 0026 — RLS-LOCKDOWN: enkel nog ingelogde gebruikers (rol 'authenticated')
-- ============================================================
-- Vervangt de dev-open policies (0003 e.v. — anon mag alles) door policies
-- die ENKEL 'authenticated' toestaan, en trekt alle anon-toegang in.
--
-- ⚠️ DRAAI DEZE MIGRATIE PAS NADAT de login in Offerte-app + Prospectie-app
--    bevestigd werkt (anders sluit je jezelf buiten). Volgorde:
--    1) Auth-gebruiker aangemaakt in het dashboard (+ public signups uit)
--    2) login-code gedeployed, jij logt succesvol in (RLS staat dan nog open)
--    3) PAS DAN deze migratie draaien
--    4) verifiëren (zie onderaan)
--
-- De PUBLIEKE quickscan blijft werken: die schrijft via de SECURITY DEFINER-
-- functie registreer_quickscan (draait met eigenaarsrechten → omzeilt RLS) en
-- heeft dus GEEN login nodig. Die grant blijft expliciet behouden.
-- ============================================================

-- ---- (a) alle DATA-tabellen: RLS aan, enkel 'authenticated' mag alles ----
do $$
declare
  t text;
  p record;
  tabellen text[] := array[
    'bedrijf','contact','quickscan','offerte','offerte_lijn','artikel',
    'tools','consultant','tarieven','lijn','station','klant',
    'templates','instellingen','wijziging_voorstel'
  ];
begin
  foreach t in array tabellen loop
    -- RLS afdwingen
    execute format('alter table public.%I enable row level security;', t);
    -- élke bestaande policy (incl. de dev-open anon-policies) weghalen
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy if exists %I on public.%I;', p.policyname, t);
    end loop;
    -- nieuwe policy: enkel ingelogde gebruikers, alles toegestaan
    execute format(
      'create policy %I on public.%I for all to authenticated using (true) with check (true);',
      'tnl_auth_all_' || t, t
    );
    -- rechten: authenticated mag, anon niet (RLS is de poort, dit is dubbele bodem)
    execute format('grant select, insert, update, delete on public.%I to authenticated;', t);
    execute format('revoke all on public.%I from anon;', t);
  end loop;
end $$;

-- ---- (b) prospects (VIEW, geen RLS): anon-grant is hier de poort ----
-- De Prospectie-app leest/schrijft dit als ingelogde gebruiker; anon niet meer.
do $$ begin
  execute 'revoke all on public.prospects from anon';
  execute 'grant select, insert, update, delete on public.prospects to authenticated';
exception when undefined_table then null; end $$;

-- ---- (c) gevoelige functies enkel voor ingelogde gebruikers ----
do $$ begin execute 'revoke execute on function public.zoek_gelijkaardige_bedrijven(text, real) from anon';
exception when undefined_function then null; end $$;
do $$ begin execute 'revoke execute on function public.dubbele_bedrijven(real) from anon';
exception when undefined_function then null; end $$;
do $$ begin execute 'revoke execute on function public.voeg_bedrijven_samen(uuid, uuid) from anon';
exception when undefined_function then null; end $$;

-- ---- (d) DE PUBLIEKE QUICKSCAN blijft werken (SECURITY DEFINER) ----
do $$ begin execute 'grant execute on function public.registreer_quickscan(jsonb) to anon, authenticated';
exception when undefined_function then null; end $$;

-- PostgREST de gewijzigde rechten/policies laten oppikken.
notify pgrst, 'reload schema';

-- ============================================================
-- VERIFICATIE (na het draaien), met de PUBLISHABLE (anon) key:
--   curl -s -o /dev/null -w "%{http_code}\n" \
--     -H "apikey: <anon>" -H "Authorization: Bearer <anon>" \
--     "https://sphmxlfpzzowsekzjltd.supabase.co/rest/v1/bedrijf?select=id&limit=1"
--   -> verwacht nu 401/403 (of lege [] i.p.v. data). Ingelogd via de app = wel.
--   De publieke quickscan (registreer_quickscan) moet nog een echte scan wegschrijven.
-- ============================================================

-- ============================================================
-- ROLLBACK (indien nodig, zet weer dev-open — NIET voor productie):
--   do $$ declare t text; begin
--     foreach t in array array['bedrijf','contact','quickscan','offerte','offerte_lijn',
--       'artikel','tools','consultant','tarieven','lijn','station','klant',
--       'templates','instellingen','wijziging_voorstel'] loop
--       execute format('drop policy if exists %I on public.%I;', 'tnl_auth_all_'||t, t);
--       execute format('create policy %I on public.%I for all to anon, authenticated using (true) with check (true);', 'dev_all_'||t, t);
--       execute format('grant select, insert, update, delete on public.%I to anon, authenticated;', t);
--     end loop; end $$;
--   grant select, insert, update, delete on public.prospects to anon, authenticated;
--   notify pgrst, 'reload schema';
-- ============================================================
