-- ============================================================
-- 0040 — segment B (Lead generator): nieuwe startstatus + hernoeming
-- ============================================================
-- 'lg1_test_mail' werd hernoemd naar "Eerste mail verstuurd" (zelfde code,
-- enkel het label in de UI wijzigt — geen migratie nodig voor bestaande
-- rijen). Nieuw: 'lg0_nog_aan_te_schrijven' als startstatus vóór lg1, net
-- zoals s01_nieuw dat is voor segment A/D/E. Geen backfill nodig: er stond
-- nog geen enkel contact op segment B (mig. 0037/0038 mapte niets daarnaar).
-- ============================================================

alter table contact drop constraint if exists contact_status_segment_check;
alter table contact add constraint contact_status_segment_check check (
  (segment in ('A_prospect', 'D_klant', 'E_ex_klant') and status in (
    's01_nieuw', 's02_gecontacteerd', 's03_opvolging_verstuurd', 's04_gereageerd', 's05_gesprek_gehad',
    's06_quickscan_aangeboden', 's07_quickscan_ingevuld', 's08_voorstel_lopend', 's09_klant_traject',
    'x1_nee_nu_niet', 'x2_geen_interesse', 'x3_slapend'
  ))
  or (segment = 'B_lead_generator' and status in (
    'lg0_nog_aan_te_schrijven', 'lg1_test_mail', 'lg2_reminder', 'lg3_gereageerd', 'lg4_fee_uitnodiging', 'lg5_actief_verwijzer',
    'x1_nee_nu_niet', 'x2_geen_interesse', 'x3_slapend'
  ))
  or (segment = 'C_tnl_expert' and status in (
    'ex1_aangesproken', 'ex2_kennismaking', 'ex3_beschikbaar',
    'x2_geen_interesse', 'x3_slapend'
  ))
);

notify pgrst, 'reload schema';

-- ROLLBACK: herstel de vorige check (zonder lg0) met dezelfde drop+add-aanpak,
-- maar dan zonder 'lg0_nog_aan_te_schrijven' in de B-lijst. Enkel zinvol als
-- er dan ook geen enkel contact meer op lg0 staat.
