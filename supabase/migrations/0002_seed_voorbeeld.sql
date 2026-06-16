-- ============================================================
-- Seed: bestaand VOORBEELD_STATION (FIN / P&L) omgezet naar de
-- nieuwe lijn -> station -> artikel structuur.
-- niveaus bevatten enkel dágen (tarieven staan centraal).
-- wbs: 'wie' -> 'rol'.
-- ============================================================

with s as (
  insert into station (lijn_code, naam, sort)
  values ('FIN', 'P&L rapportering', 10)
  returning id
)
insert into artikel (
  station_id, subnaam, omschrijving,
  scope_in, scope_uit, beperkingen, input, deliverables, doelstellingen,
  doorlooptijd, proces, wbs, opties, niveaus, sort
)
select
  s.id,
  'Profit & Loss',
  'We implementeren een maandelijkse P&L-rapportering zodat u altijd weet waar uw marge naartoe gaat.',
  '• Opzetten van een maandelijkse P&L-structuur op maat
• Koppeling aan bestaande boekhouding (manueel of via export)
• Definitie van kostenstructuur en margeberekening
• Excel-dashboard met resultatenrekening per activiteit
• Training van de verantwoordelijke medewerker',
  '• Geen aanpassing of migratie van het boekhoudpakket
• Geen historische reconstructie van meer dan 12 maanden
• Geen consolidatie van meerdere juridische entiteiten
• Geen geautomatiseerde koppeling via API of BI-tool',
  'Vereist een operationele boekhouding met resultatenrekening. Niet geschikt voor bedrijven zonder kostenstructuur of zonder maandelijkse afsluiting.',
  '• Toegang tot het boekhoudpakket of maandelijkse exports
• Overzicht van de kostenstructuur (kostenplaatsen, activiteiten)
• Contactpersoon financiën beschikbaar (2 × ½ dag)',
  '• Excel P&L-template op maat van de organisatie
• Instructiedocument voor maandelijkse invulling
• Dashboard met marge per product / klant / afdeling
• 1 validatiesessie na de eerste maandafsluiting
• Eindrapport met aanbevelingen',
  'Maandelijkse P&L beschikbaar binnen 5 werkdagen na maandafsluiting. Inzicht in bruto- en nettomarge per activiteit. Zaakvoerder kan zelfstandig bijsturen op basis van cijfers.',
  '3-5 weken',
  'Intake → Ontwerp → Implementatie → Training → Validatie',
  '[
    {"activiteit":"Intake & analyse kostenstructuur","type":"consultant","rol":"Sr","dagen":0.5},
    {"activiteit":"Ontwerp P&L-structuur & template","type":"consultant","rol":"Sr","dagen":1},
    {"activiteit":"Koppeling aan boekhouding & test","type":"consultant","rol":"Jr","dagen":1},
    {"activiteit":"Dashboard bouwen","type":"consultant","rol":"Jr","dagen":1},
    {"activiteit":"Training verantwoordelijke","type":"consultant","rol":"Sr","dagen":0.5},
    {"activiteit":"Validatiesessie maand 1","type":"consultant","rol":"Sr","dagen":0.5},
    {"activiteit":"Aanleveren data & exports","type":"klant","rol":null,"dagen":0.5},
    {"activiteit":"Deelname training & validatie","type":"klant","rol":null,"dagen":0.5}
  ]'::jsonb,
  '[
    {"omschrijving":"Cashflow forecast (13-weken rolling)","prijs":1200},
    {"omschrijving":"Automatische koppeling via BI-tool (Power BI / Looker)","prijs":2500},
    {"omschrijving":"Consolidatie meerdere entiteiten","prijs":1800},
    {"omschrijving":"Maandelijkse begeleiding eerste kwartaal (3 × ½ dag)","prijs":1500}
  ]'::jsonb,
  '{
    "S":{"jrDagen":0,"srDagen":1.5,"klantDagen":0.5,"omschrijving":"Diagnose + P&L-template"},
    "M":{"jrDagen":2,"srDagen":2,"klantDagen":1,"omschrijving":"Volledige implementatie + training"},
    "I":{"jrDagen":4,"srDagen":4,"klantDagen":2,"omschrijving":"Uitbouw + dashboard + kwartaalbegeleiding"}
  }'::jsonb,
  10
from s;
