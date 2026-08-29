-- ============================================================
-- 0037 — CRM-laag: segment, temperatuur, funnel-status per contact
-- ============================================================
-- Voegt de CRM-opvolging uit "Prompt_CRM_uitbreiding.md" toe aan de
-- Prospecten-tab. VEILIG / ADDITIEF waar mogelijk, maar contact.status en
-- contact.volgende_stap krijgen een striktere betekenis (zie hieronder) —
-- bestaande waarden worden EERST gemigreerd, dan pas komt de check erbij.
--
-- Hergebruik-beslissingen (afgestemd met de gebruiker):
--   • prioriteit  → bestaande contact.prio (1-9) blijft, geen nieuw veld.
--   • bron        → bestaand contact.bron/bedrijf.bron (technische herkomst)
--                    blijft ongemoeid; nieuw veld heet bron_zakelijk.
--   • notities    → geen nieuwe kolom; blijft in contact_notitie (mig. 0033).
--   • datum_laatste_contact/aantal_pogingen → NIET opgeslagen, afgeleid in
--     de app uit bedrijf_interactie (mig. 0035), die nu ook aan één contact
--     gekoppeld kan worden i.p.v. enkel aan het bedrijf.
--   • cat1 (Netwerk/KoudContact/WarmeLead/...) → eenmalig gemigreerd naar
--     segment/temperatuur/verwezen_door hieronder, daarna niet meer actief
--     gebruikt (kolom blijft bestaan voor de geschiedenis).
--   • template_gebruikt → GEEN vaste enum (sjabloon-categorieën zijn zelf
--     een open, door de gebruiker uitbreidbare lijst) maar een echte FK naar
--     templates.categorie (die kolom is al primary key, mig. 0024).
--
-- Terugdraaien: zie het becommentarieerde ROLLBACK-blok onderaan.
-- ============================================================

-- ------------------------------------------------------------
-- (1) Nieuwe classificatie-kolommen — met default, dus meteen ingevuld
--     voor bestaande rijen (Postgres: DEFAULT op een nieuwe kolom is een
--     metadata-only operatie, geen table rewrite nodig).
-- ------------------------------------------------------------
alter table contact add column if not exists segment     text not null default 'A_prospect';
alter table contact add column if not exists temperatuur text not null default 'lauw';
alter table contact add column if not exists bron_zakelijk text;
alter table contact add column if not exists doelgroep     text;

-- ------------------------------------------------------------
-- (2) Databronmigratie: bestaande contact.cat1 → segment/temperatuur.
--     Case-insensitief/whitespace-tolerant gematcht op de waarden die de
--     gebruiker effectief in de Contact-kolom zag staan.
-- ------------------------------------------------------------
update contact set segment = 'D_klant', temperatuur = 'warm'
  where lower(btrim(cat1)) = 'klant';

update contact set segment = 'A_prospect', temperatuur = 'koud'
  where lower(btrim(cat1)) = 'koud contact';

update contact set segment = 'A_prospect', temperatuur = 'warm'
  where lower(btrim(cat1)) = 'warme lead';

-- 'collega' = TNL-collega/freelancer zelf, geen prospect.
update contact set segment = 'C_tnl_expert', temperatuur = 'lauw'
  where lower(btrim(cat1)) = 'collega';

-- ------------------------------------------------------------
-- (3) 'Via <naam>'-notities in cat1 zijn geen categorie maar een verwijzer.
--     Bestaat er precies één contact met die naam, dan koppelen we
--     verwezen_door; anders gaat de originele tekst naar contact_notitie
--     zodat er niets verloren gaat (kolom hieronder toegevoegd vóór dit blok
--     loopt, dus verwezen_door bestaat al op dit punt — zie stap 5).
-- ------------------------------------------------------------
alter table contact add column if not exists verwezen_door uuid references contact(id) on delete set null;

do $$
declare
  r record;
  v_naam text;
  v_id uuid;
  v_aantal int;
begin
  for r in select id, cat1 from contact where cat1 ilike 'via %' loop
    v_naam := btrim(substring(r.cat1 from 5));
    select count(*) into v_aantal from contact
      where lower(btrim(coalesce(voornaam, '') || ' ' || coalesce(achternaam, ''))) = lower(v_naam);
    if v_aantal = 1 then
      select id into v_id from contact
        where lower(btrim(coalesce(voornaam, '') || ' ' || coalesce(achternaam, ''))) = lower(v_naam)
        limit 1;
      update contact set verwezen_door = v_id where id = r.id;
    else
      insert into contact_notitie (contact_id, auteur, tekst)
      values (r.id, 'Migratie v4.0', 'Herkomst (voorheen in de Contact-kolom): ' || r.cat1);
    end if;
  end loop;
end $$;

-- ------------------------------------------------------------
-- (4) contact.status: herbouwen tot de rijke, segment-afhankelijke funnel-
--     status. Volgorde is belangrijk — segment (stap 2/3) staat al vast,
--     dus segment C krijgt meteen een geldige C-status i.p.v. een A/D/E-code.
-- ------------------------------------------------------------
update contact set status = case
  when segment = 'C_tnl_expert' then 'ex1_aangesproken'
  when nog_te_contacteren then 's01_nieuw'
  when lower(btrim(coalesce(status, ''))) = 'quickscan verstuurd' then 's06_quickscan_aangeboden'
  when lower(btrim(coalesce(status, ''))) = 'quickscan ingevuld' or quickscan_ingevuld then 's07_quickscan_ingevuld'
  else 's02_gecontacteerd'
end;
-- DEFAULT is nodig, niet enkel NOT NULL: verschillende insert-plekken in de app (Database-
-- tab, Offerte-tab) laten 'status' gewoon weg bij het aanmaken van een nieuw contact en
-- vertrouwden tot nu toe op de kolom die dan leeg bleef. Zonder default zou zo'n insert
-- vanaf nu gewoon falen; met deze default krijgt zo'n nieuw contact braaf de startstatus.
alter table contact alter column status set default 's01_nieuw';
alter table contact alter column status set not null;

-- ------------------------------------------------------------
-- (5) contact.volgende_stap: was vrije tekst, wordt een vaste keuzelijst.
--     Bestaande vrije tekst gaat NIET verloren — die verhuist naar het
--     nieuwe toelichting-veld; volgende_stap zelf wordt leeg tot iemand
--     bewust een geldige actie kiest (in plaats van een gok te forceren).
-- ------------------------------------------------------------
alter table contact add column if not exists volgende_stap_toelichting text;
update contact set volgende_stap_toelichting = volgende_stap
  where volgende_stap is not null and btrim(volgende_stap) <> '';
update contact set volgende_stap = null
  where volgende_stap is not null
    and volgende_stap not in (
      'mail_versturen', 'opvolgmail', 'bellen', 'gesprek_plannen',
      'quickscan_opvolgen', 'voorstel_maken', 'kwartaalmail', 'geen_actie'
    );

-- ------------------------------------------------------------
-- (6) Overige nieuwe velden.
-- ------------------------------------------------------------
alter table contact add column if not exists template_gebruikt text references templates(categorie) on delete set null;
alter table contact add column if not exists hoofdcontact_bedrijf boolean not null default false;

-- Interacties-tijdlijn (mig. 0035) optioneel aan één contact koppelen i.p.v.
-- enkel aan het bedrijf; leeg = geldt voor het hele bedrijf (huidig gedrag).
alter table bedrijf_interactie add column if not exists contact_id uuid references contact(id) on delete set null;
create index if not exists idx_bedrijf_interactie_contact on bedrijf_interactie (contact_id) where contact_id is not null;

-- ------------------------------------------------------------
-- (7) Check-constraints — pas nu toevoegen, ná de backfill hierboven zodat
--     geen enkele bestaande rij zichzelf ongeldig maakt.
-- ------------------------------------------------------------
alter table contact drop constraint if exists contact_segment_check;
alter table contact add constraint contact_segment_check check (
  segment in ('A_prospect', 'B_lead_generator', 'C_tnl_expert', 'D_klant', 'E_ex_klant')
);

alter table contact drop constraint if exists contact_temperatuur_check;
alter table contact add constraint contact_temperatuur_check check (
  temperatuur in ('warm', 'lauw', 'koud')
);

alter table contact drop constraint if exists contact_bron_zakelijk_check;
alter table contact add constraint contact_bron_zakelijk_check check (
  bron_zakelijk is null or bron_zakelijk in (
    'eigen_netwerk', 'doorverwezen', 'event_spreekbeurt', 'website', 'vroegere_samenwerking', 'andere'
  )
);

alter table contact drop constraint if exists contact_doelgroep_check;
alter table contact add constraint contact_doelgroep_check check (
  doelgroep is null or doelgroep in ('kmo', 'familiebedrijf', 'scale_up', 'investeerder_pe', 'nvt')
);

alter table contact drop constraint if exists contact_volgende_stap_check;
alter table contact add constraint contact_volgende_stap_check check (
  volgende_stap is null or volgende_stap in (
    'mail_versturen', 'opvolgmail', 'bellen', 'gesprek_plannen',
    'quickscan_opvolgen', 'voorstel_maken', 'kwartaalmail', 'geen_actie'
  )
);

alter table contact drop constraint if exists contact_hoofdcontact_vereist_bedrijf;
alter table contact add constraint contact_hoofdcontact_vereist_bedrijf check (
  not hoofdcontact_bedrijf or bedrijf_id is not null
);

alter table contact drop constraint if exists contact_verwezen_door_niet_zelf;
alter table contact add constraint contact_verwezen_door_niet_zelf check (
  verwezen_door is null or verwezen_door <> id
);

-- Status moet passen bij segment (Stap 2, businessregel 1 uit de prompt).
alter table contact drop constraint if exists contact_status_segment_check;
alter table contact add constraint contact_status_segment_check check (
  (segment in ('A_prospect', 'D_klant', 'E_ex_klant') and status in (
    's01_nieuw', 's02_gecontacteerd', 's03_opvolging_verstuurd', 's04_gereageerd', 's05_gesprek_gehad',
    's06_quickscan_aangeboden', 's07_quickscan_ingevuld', 's08_voorstel_lopend', 's09_klant_traject',
    'x1_nee_nu_niet', 'x2_geen_interesse', 'x3_slapend'
  ))
  or (segment = 'B_lead_generator' and status in (
    'lg1_test_mail', 'lg2_reminder', 'lg3_gereageerd', 'lg4_fee_uitnodiging', 'lg5_actief_verwijzer',
    'x1_nee_nu_niet', 'x2_geen_interesse', 'x3_slapend'
  ))
  or (segment = 'C_tnl_expert' and status in (
    'ex1_aangesproken', 'ex2_kennismaking', 'ex3_beschikbaar',
    'x2_geen_interesse', 'x3_slapend'
  ))
);

-- Eén hoofdcontact per bedrijf (Stap 2, businessregel 2). NULL-bedrijf_id-
-- rijen botsen nooit met elkaar (Postgres: NULL <> NULL in een unique index).
create unique index if not exists contact_hoofdcontact_uniek
  on contact (bedrijf_id) where hoofdcontact_bedrijf;

notify pgrst, 'reload schema';

-- ============================================================
-- CONTROLELIJST — na het draaien even nalopen: contacten die op de veilige
-- default (A_prospect/lauw) zijn blijven staan omdat hun oude Contact-waarde
-- niet één van de herkende labels was (of leeg was).
--   select id, voornaam, achternaam, cat1, segment, temperatuur
--   from contact
--   where lower(btrim(coalesce(cat1,''))) not in ('klant','koud contact','warme lead','collega')
--     and cat1 not ilike 'via %';
-- ============================================================

-- ============================================================
-- ROLLBACK (indien nodig — let op: dit verwijdert de gemigreerde CRM-data,
-- de ORIGINELE cat1/status/volgende_stap-waarden blijven wel intact staan
-- want die zijn nooit overschreven, enkel gelezen):
--
--   alter table contact drop constraint if exists contact_status_segment_check;
--   alter table contact drop constraint if exists contact_verwezen_door_niet_zelf;
--   alter table contact drop constraint if exists contact_hoofdcontact_vereist_bedrijf;
--   alter table contact drop constraint if exists contact_volgende_stap_check;
--   alter table contact drop constraint if exists contact_doelgroep_check;
--   alter table contact drop constraint if exists contact_bron_zakelijk_check;
--   alter table contact drop constraint if exists contact_temperatuur_check;
--   alter table contact drop constraint if exists contact_segment_check;
--   drop index if exists contact_hoofdcontact_uniek;
--   drop index if exists idx_bedrijf_interactie_contact;
--   alter table bedrijf_interactie drop column if exists contact_id;
--   alter table contact drop column if exists hoofdcontact_bedrijf;
--   alter table contact drop column if exists template_gebruikt;
--   alter table contact drop column if exists volgende_stap_toelichting;
--   alter table contact drop column if exists verwezen_door;
--   alter table contact drop column if exists doelgroep;
--   alter table contact drop column if exists bron_zakelijk;
--   alter table contact drop column if exists temperatuur;
--   alter table contact drop column if exists segment;
--   -- LET OP: volgende_stap en status staan dan weer "open" (geen check),
--   -- maar de waarden die deze migratie er zelf in zette (s01_nieuw, enz.)
--   -- blijven gewoon staan — dat is geen schema-breuk, enkel geen check meer.
--   notify pgrst, 'reload schema';
-- ============================================================
