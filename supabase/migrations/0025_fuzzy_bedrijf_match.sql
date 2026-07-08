-- ============================================================
-- 0025 — Slimme "gelijkaardig bedrijf"-check (fuzzy, zonder AI)
-- ============================================================
-- pg_trgm-gelijkenis om bijna-dubbele bedrijfsnamen te herkennen die de
-- gewone normalisatie mist (typfouten, '&' vs 'en', spaties, woordvolgorde).
-- Gebruikt bij het invoeren (waarschuwing) en om bestaande dubbels op te sporen.
--
-- VEILIG: enkel een extensie + twee functies. Geen datawijziging.
-- ============================================================

create extension if not exists pg_trgm;

-- Zoek bestaande bedrijven die op p_naam lijken (gelijkenis 0..1).
create or replace function zoek_gelijkaardige_bedrijven(p_naam text, p_drempel real default 0.4)
returns table (id uuid, naam text, status text, gelijkenis real, aantal_contacten bigint)
language sql stable security definer set search_path = public as $$
  select b.id, b.naam, b.status,
         similarity(norm_naam(b.naam), norm_naam(p_naam)) as gelijkenis,
         (select count(*) from contact c where c.bedrijf_id = b.id) as aantal_contacten
  from bedrijf b
  where norm_naam(coalesce(p_naam,'')) <> ''
    and similarity(norm_naam(b.naam), norm_naam(p_naam)) >= p_drempel
  order by gelijkenis desc, b.naam
  limit 8;
$$;
grant execute on function zoek_gelijkaardige_bedrijven(text, real) to anon, authenticated;

-- Alle bijna-dubbele PAREN in de database (voor de opruim-scanner).
-- Geeft elk paar één keer terug (a.id < b.id) boven de drempel.
create or replace function dubbele_bedrijven(p_drempel real default 0.55)
returns table (id_a uuid, naam_a text, contacten_a bigint,
               id_b uuid, naam_b text, contacten_b bigint, gelijkenis real)
language sql stable security definer set search_path = public as $$
  select a.id, a.naam, (select count(*) from contact c where c.bedrijf_id = a.id),
         b.id, b.naam, (select count(*) from contact c where c.bedrijf_id = b.id),
         similarity(norm_naam(a.naam), norm_naam(b.naam)) as gelijkenis
  from bedrijf a
  join bedrijf b on a.id < b.id
  where similarity(norm_naam(a.naam), norm_naam(b.naam)) >= p_drempel
  order by gelijkenis desc, a.naam;
$$;
grant execute on function dubbele_bedrijven(real) to anon, authenticated;

-- Twee bedrijven samenvoegen: alle contacten/quickscans/offertes van
-- p_verwijder herkoppelen aan p_behoud, daarna p_verwijder wissen.
create or replace function voeg_bedrijven_samen(p_behoud uuid, p_verwijder uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_behoud is null or p_verwijder is null or p_behoud = p_verwijder then return; end if;
  update contact   set bedrijf_id = p_behoud where bedrijf_id = p_verwijder;
  update quickscan  set bedrijf_id = p_behoud where bedrijf_id = p_verwijder;
  update offerte    set bedrijf_id = p_behoud where bedrijf_id = p_verwijder;
  delete from bedrijf where id = p_verwijder;
end $$;
grant execute on function voeg_bedrijven_samen(uuid, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
