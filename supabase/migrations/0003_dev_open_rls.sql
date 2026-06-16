-- ============================================================
-- DEV-ONLY: RLS openzetten voor de publishable (anon) key.
-- Hiermee kan de app zonder login lezen/schrijven tijdens de bouw.
-- !! Vóór publicatie vervangen door login (rol 'authenticated'). !!
-- ============================================================

do $$
declare t text;
begin
  foreach t in array array['tarieven','lijn','station','artikel','offerte','offerte_lijn']
  loop
    -- oude (authenticated-only) policy verwijderen
    execute format('drop policy if exists %I on %I;', 'auth_all_' || t, t);
    -- nieuwe policy: iedereen (anon + authenticated) mag alles
    execute format(
      'create policy %I on %I for all to anon, authenticated using (true) with check (true);',
      'dev_all_' || t, t
    );
  end loop;
end;
$$;
