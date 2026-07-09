-- ============================================================
-- 0027 — Aanvulling op 0026: gevoelige functies écht dichtzetten
-- ============================================================
-- Postgres geeft functies standaard EXECUTE aan de rol PUBLIC. Het intrekken
-- van EXECUTE bij 'anon' (in 0026) volstond dus NIET: anon behield het recht
-- via PUBLIC. Hier trekken we EXECUTE in bij PUBLIC én anon, en geven we het
-- enkel aan 'authenticated'.
--
-- Betreft o.a. de DESTRUCTIEVE, SECURITY DEFINER-functie voeg_bedrijven_samen
-- (voegt bedrijven samen + verwijdert). registreer_quickscan blijft BEWUST
-- publiek (de publieke quickscan schrijft ermee).
-- ============================================================

do $$ begin
  execute 'revoke execute on function public.zoek_gelijkaardige_bedrijven(text, real) from public, anon';
  execute 'grant  execute on function public.zoek_gelijkaardige_bedrijven(text, real) to authenticated';
exception when undefined_function then null; end $$;

do $$ begin
  execute 'revoke execute on function public.dubbele_bedrijven(real) from public, anon';
  execute 'grant  execute on function public.dubbele_bedrijven(real) to authenticated';
exception when undefined_function then null; end $$;

do $$ begin
  execute 'revoke execute on function public.voeg_bedrijven_samen(uuid, uuid) from public, anon';
  execute 'grant  execute on function public.voeg_bedrijven_samen(uuid, uuid) to authenticated';
exception when undefined_function then null; end $$;

-- De publieke quickscan blijft werken (voor de zekerheid opnieuw bevestigd).
do $$ begin
  execute 'grant execute on function public.registreer_quickscan(jsonb) to anon, authenticated';
exception when undefined_function then null; end $$;

notify pgrst, 'reload schema';
