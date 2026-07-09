// ============================================================
// TNL Gesprek & Offerte — data-laag bovenop Supabase
// Vereist: supabase-js v2 (CDN) + window.TNL_SUPABASE (config.js)
//
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script src="supabase/config.js"></script>
//   <script src="supabase/db.js"></script>
//
// Alle functies zijn async en geven { data, error } door, of gooien
// bij een harde fout. Sluit aan op het schema lijn -> station -> artikel.
// ============================================================

const TNL = (() => {
  let sb = null;

  function client() {
    if (sb) return sb;
    if (!window.TNL_SUPABASE) throw new Error('config.js ontbreekt (window.TNL_SUPABASE)');
    if (!window.supabase)     throw new Error('supabase-js (CDN) niet geladen');
    sb = window.supabase.createClient(window.TNL_SUPABASE.url, window.TNL_SUPABASE.anonKey);
    return sb;
  }

  // ---------- helpers ----------
  function check({ data, error }) {
    if (error) throw error;
    return data;
  }

  // Prijs/dagen van een artikel-niveau, op basis van centrale tarieven.
  // tarieven = { Partner: 1500, Senior: 1200, ... }
  // niveau.dagen = { Senior: 2, Junior: 1, ... }  (dagen per rol)
  // Blijft ook werken met het oude formaat { jrDagen, srDagen }.
  function berekenNiveau(niveau, tarieven) {
    if (!niveau) return { prijs: 0, dagen: 0, klantDagen: 0 };
    // Oud formaat (jr/sr) → omzetten naar rol-map
    let map = niveau.dagen;
    if (!map && (niveau.jrDagen != null || niveau.srDagen != null)) {
      map = { Jr: niveau.jrDagen || 0, Sr: niveau.srDagen || 0 };
    }
    map = map || {};
    let prijs = 0, dagen = 0;
    for (const rol in map) {
      const d = Number(map[rol]) || 0;
      dagen += d;
      // interim: dag = hele-dag-prijs (tarieven[rol] kan getal of object zijn)
      const t = tarieven[rol];
      const dagtarief = (t && typeof t === 'object') ? (Number(t.heledagprijs) || 0) : (Number(t) || 0);
      prijs += d * dagtarief;
    }
    return { prijs, dagen, klantDagen: niveau.klantDagen || 0 };
  }

  // ---------- tarieven (rollen + 3 prijzen) ----------
  // Map { rol: { uurprijs, halvedagprijs, heledagprijs } } — voor berekeningen.
  async function getTarieven() {
    const rows = check(await client().from('tarieven')
      .select('rol, uurprijs, halvedagprijs, heledagprijs'));
    return Object.fromEntries(rows.map(r => [r.rol, {
      uurprijs: Number(r.uurprijs) || 0,
      halvedagprijs: Number(r.halvedagprijs) || 0,
      heledagprijs: Number(r.heledagprijs) || 0
    }]));
  }

  // Geordende lijst (duurste hele dag eerst = meest senior) — voor het beheer-scherm.
  async function getTarievenLijst() {
    return check(await client().from('tarieven')
      .select('rol, afkorting, uurprijs, halvedagprijs, heledagprijs')
      .order('heledagprijs', { ascending: false, nullsFirst: false }));
  }

  // prijzen = { uurprijs, halvedagprijs, heledagprijs }
  async function setTarief(rol, prijzen) {
    return check(await client().from('tarieven')
      .upsert({ rol, ...prijzen }).select().single());
  }

  // Prijs van een ingezette eenheid (uur/halvedag/heledag) voor een rol.
  function prijsVanEenheid(rol, eenheid, aantal, tarieven) {
    const t = tarieven[rol]; if (!t) return 0;
    const tarief = eenheid === 'uur' ? t.uurprijs
                 : eenheid === 'halvedag' ? t.halvedagprijs
                 : eenheid === 'heledag' ? t.heledagprijs : 0;
    return (Number(aantal) || 0) * (Number(tarief) || 0);
  }

  async function verwijderTarief(rol) {
    return check(await client().from('tarieven').delete().eq('rol', rol));
  }

  // ---------- app-brede instellingen (key-value) ----------
  async function getInstelling(sleutel) {
    const row = check(await client().from('instellingen')
      .select('waarde').eq('sleutel', sleutel).maybeSingle());
    return row ? row.waarde : null;
  }
  async function setInstelling(sleutel, waarde) {
    return check(await client().from('instellingen')
      .upsert({ sleutel, waarde, updated_at: new Date().toISOString() }).select().single());
  }

  // Rekenkern van een TNL Fix: kost per scope-groep, totalen, doorlooptijd
  // en klant-inspanning. Deliverables met optie=true tellen apart (niet in basis).
  //   fix.wbs = [{ rol, eenheid, aantal, scopeGroep, optie, week, klantAantal, klantEenheid }]
  function berekenFix(fix, tarieven) {
    const wbs = (fix && fix.wbs) || [];
    let basis = 0, opties = 0, doorlooptijd = 0;
    const perGroep = {};          // { scopeGroep: kost }   (alleen niet-optie = in-scope)
    const klant = {};             // { dag: x, uur: y }
    wbs.forEach(d => {
      const g = (d.scopeGroep || '').trim();
      if (g === 'OutOfScope' || g === 'Maatwerk') return;        // geen auto-kost
      if (g === 'Optioneel' && d.gekozen === false) return;      // niet-gekozen optie telt niet
      const kost = prijsVanEenheid(d.rol, d.eenheid, d.aantal, tarieven);
      if (g === 'Optioneel') { opties += kost; }
      else {                                                     // standaard: telt altijd mee
        basis += kost;
        perGroep[g || '(geen groep)'] = (perGroep[g || '(geen groep)'] || 0) + kost;
      }
      const wk = (Number(d.aantal) > 0) ? Math.floor(Number(d.week) || 0) : 0;
      if (wk > doorlooptijd) doorlooptijd = wk;
      const ka = Number(d.klantAantal) || 0;
      if (ka) { const e = d.klantEenheid || 'dag'; klant[e] = (klant[e] || 0) + ka; }
    });
    return { basis, opties, totaal: basis + opties, doorlooptijd, perGroep, klant };
  }

  // ---------- lijnen ----------
  async function getLijnen() {
    return check(await client().from('lijn')
      .select('*').order('sort'));
  }

  // ---------- stations ----------
  async function getStations(lijnCode = null) {
    let q = client().from('station').select('*').order('sort');
    if (lijnCode) q = q.eq('lijn_code', lijnCode);
    return check(await q);
  }

  async function upsertStation(station) {
    return check(await client().from('station')
      .upsert(station).select().single());
  }

  async function deleteStation(id) {
    return check(await client().from('station').delete().eq('id', id));
  }

  // ---------- artikelen (producten) ----------
  // Volledige catalogus met lijn/station-info, klaar om als menu te tonen.
  async function getCatalogus({ alleenActief = true } = {}) {
    let q = client().from('artikel')
      .select('*, station:station_id ( id, naam, sort, lijn:lijn_code ( code, naam, type, icon, sort ) )')
      .order('sort');
    if (alleenActief) q = q.eq('actief', true);
    return check(await q);
  }

  async function getArtikel(id) {
    return check(await client().from('artikel').select('*').eq('id', id).single());
  }

  async function upsertArtikel(artikel) {
    return check(await client().from('artikel')
      .upsert(artikel).select().single());
  }

  async function updateArtikel(id, patch) {
    return check(await client().from('artikel')
      .update(patch).eq('id', id).select().single());
  }

  async function deleteArtikel(id) {
    return check(await client().from('artikel').delete().eq('id', id));
  }

  // ---------- offertes ----------
  // selectie = [{ artikel, niveau }]  (artikel = volledig artikel-object incl. lijn/station)
  // Bouwt per regel een snapshot (artikel + tarieven + berekende prijs) en
  // bewaart offerte + regels. Oude offertes blijven zo correct.
  async function saveOfferte({ klant_naam, klant_contact, datum, status }, selectie) {
    const tarieven = await getTarieven();

    let totaal = 0;
    const lijnen = selectie.map((sel, i) => {
      const calc = berekenNiveau(sel.artikel.niveaus?.[sel.niveau], tarieven);
      totaal += calc.prijs;
      return {
        artikel_id: sel.artikel.id,
        niveau: sel.niveau,
        snapshot: { artikel: sel.artikel, tarieven, berekend: calc },
        prijs: calc.prijs,
        dagen: calc.dagen,
        sort: i * 10
      };
    });

    const offerte = check(await client().from('offerte')
      .insert({ klant_naam, klant_contact, datum, status, totaal })
      .select().single());

    if (lijnen.length) {
      check(await client().from('offerte_lijn')
        .insert(lijnen.map(l => ({ ...l, offerte_id: offerte.id }))));
    }
    return offerte;
  }

  // ---------- klant (bedrijfsdossier) ----------
  async function getKlanten() {
    return check(await client().from('klant').select('*').order('bedrijf'));
  }

  // Zoek bestaand bedrijf (case-/spatie-ongevoelig) of geef null.
  async function vindKlantOpBedrijf(bedrijf) {
    if (!bedrijf) return null;
    const rows = check(await client().from('klant')
      .select('*').ilike('bedrijf', bedrijf.trim()).limit(1));
    return rows[0] || null;
  }

  // Maak/werk bedrijfsdossier bij (gematcht op bedrijfsnaam).
  async function upsertKlant(klant) {
    const bestaand = await vindKlantOpBedrijf(klant.bedrijf);
    if (bestaand) {
      return check(await client().from('klant')
        .update(klant).eq('id', bestaand.id).select().single());
    }
    return check(await client().from('klant').insert(klant).select().single());
  }

  // Werk enkele velden van een bedrijfsdossier bij (bv. prospect_id koppelen).
  async function updateKlant(id, patch) {
    return check(await client().from('klant').update(patch).eq('id', id).select().single());
  }

  // ---------- bedrijf + contact (unified CRM-model, migratie 0020) ----------
  async function getBedrijven() {
    return check(await client().from('bedrijf').select('*').order('naam'));
  }
  async function getContacten() {
    return check(await client().from('contact').select('*').order('achternaam'));
  }
  async function updateBedrijf(id, patch) {
    return check(await client().from('bedrijf')
      .update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id).select().single());
  }
  async function updateContact(id, patch) {
    return check(await client().from('contact')
      .update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id).select().single());
  }
  async function insertBedrijf(bedrijf) {
    return check(await client().from('bedrijf').insert(bedrijf).select().single());
  }
  async function insertContact(contact) {
    return check(await client().from('contact').insert(contact).select().single());
  }
  async function deleteBedrijf(id) {
    return check(await client().from('bedrijf').delete().eq('id', id));
  }
  async function deleteContact(id) {
    return check(await client().from('contact').delete().eq('id', id));
  }
  // Werk enkele velden van een scan bij (bv. een scan aan een contact/bedrijf koppelen).
  async function deleteQuickscan(id) {
    return check(await client().from('quickscan').delete().eq('id', id));
  }
  async function updateQuickscan(id, patch) {
    return check(await client().from('quickscan').update(patch).eq('id', id).select().single());
  }

  // ---------- fuzzy bedrijf-match (migratie 0025) ----------
  async function zoekGelijkaardigeBedrijven(naam, drempel = 0.4) {
    return check(await client().rpc('zoek_gelijkaardige_bedrijven', { p_naam: naam, p_drempel: drempel }));
  }
  async function dubbeleBedrijven(drempel = 0.55) {
    return check(await client().rpc('dubbele_bedrijven', { p_drempel: drempel }));
  }
  async function voegBedrijvenSamen(behoudId, verwijderId) {
    return check(await client().rpc('voeg_bedrijven_samen', { p_behoud: behoudId, p_verwijder: verwijderId }));
  }

  // ---------- mailsjablonen (Prospecten/Mails-tab) ----------
  async function getTemplates() {
    return check(await client().from('templates').select('*').order('categorie'));
  }
  async function upsertTemplate(t) {
    return check(await client().from('templates').upsert(t, { onConflict: 'categorie' }).select().single());
  }

  // ---------- goedkeurings-queue (voorgestelde wijzigingen) ----------
  async function getVoorstellen(status = 'open') {
    let q = client().from('wijziging_voorstel').select('*').order('created_at', { ascending: false });
    if (status) q = q.eq('status', status);
    return check(await q);
  }
  async function updateVoorstel(id, patch) {
    return check(await client().from('wijziging_voorstel')
      .update(patch).eq('id', id).select().single());
  }

  // ---------- prospecten (read-only uit het aparte Prospectie-project) ----------
  const PROSPECTIE = {
    url: 'https://pylfvfcieyrwegcvlwwa.supabase.co',
    anonKey: 'sb_publishable_jINc1spJu3sUcltJSABpLQ_r_jBNBud'
  };
  let sbp = null;
  function prospectieClient() {
    if (sbp) return sbp;
    if (!window.supabase) throw new Error('supabase-js (CDN) niet geladen');
    sbp = window.supabase.createClient(PROSPECTIE.url, PROSPECTIE.anonKey);
    return sbp;
  }
  async function getProspects() {
    return check(await prospectieClient().from('prospects')
      .select('id, titel, voornaam, naam, bedrijf, email, telefoon, categorie, status, notities')
      .order('bedrijf', { ascending: true }));
  }

  // ---------- quickscan (scan opslaan/ophalen) ----------
  // Slaat klant + scan op. Scan is uniek op (klant_id, datum, invuller):
  // zelfde combinatie opnieuw inlezen werkt het bestaande dossier bij.
  async function saveGesprek({ klant, scores, labels, gemiddelde, ruweMail, datum }) {
    const k = await upsertKlant({
      bedrijf: klant.bedrijf || '(onbekend)',
      contactpersoon: klant.naam || null,
      email: klant.email || null,
      functie: klant.functie || null,
      sector: klant.sector || null,
      medewerkers: klant.medewerkers || null,
      telefoon: klant.tel || null
    });

    const scan = {
      klant_id: k.id,
      datum: datum || new Date().toISOString().slice(0, 10),
      invuller: klant.naam || null,
      gemiddelde_score: gemiddelde ?? null,
      scores, labels: labels || {},
      ruwe_mail: ruweMail || null
    };
    const opgeslagen = check(await client().from('quickscan')
      .upsert(scan, { onConflict: 'klant_id,datum,invuller' }).select().single());

    return { klant: k, quickscan: opgeslagen };
  }

  async function getScansVanKlant(klantId) {
    return check(await client().from('quickscan')
      .select('*').eq('klant_id', klantId).order('datum', { ascending: false }));
  }

  // Alle scans in één keer (voor het dossier-overzicht; groeperen gebeurt in de UI).
  async function getAlleScans() {
    return check(await client().from('quickscan')
      .select('*').order('datum', { ascending: false }));
  }

  async function getOffertes() {
    return check(await client().from('offerte')
      .select('*').order('created_at', { ascending: false }));
  }

  async function getOfferte(id) {
    const offerte = check(await client().from('offerte').select('*').eq('id', id).single());
    const lijnen  = check(await client().from('offerte_lijn')
      .select('*').eq('offerte_id', id).order('sort'));
    return { ...offerte, lijnen };
  }

  // ---------- tools ----------
  async function getTools() {
    return check(await client().from('tools').select('*').order('naam'));
  }
  async function getTool(id) {
    return check(await client().from('tools').select('*').eq('id', id).single());
  }
  async function upsertTool(tool) {
    return check(await client().from('tools')
      .upsert({ ...tool, updated_at: new Date().toISOString() }).select().single());
  }
  async function updateTool(id, patch) {
    return check(await client().from('tools')
      .update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id).select().single());
  }
  async function deleteTool(id) {
    return check(await client().from('tools').delete().eq('id', id));
  }
  // Los document bij een tool-proces naar Storage (tool-fiches/{id}/docs/...).
  async function uploadToolDoc(toolId, file) {
    const safe = (file.name || 'document').replace(/[^\w.\-]+/g, '_');
    const pad = toolId + '/docs/' + Date.now() + '-' + safe;
    const { error } = await client().storage.from('tool-fiches').upload(pad, file, { upsert: true });
    if (error) throw error;
    const { data } = client().storage.from('tool-fiches').getPublicUrl(pad);
    return { url: data.publicUrl, naam: file.name };
  }
  // PDF-productfiche naar Storage (zelfde pad -> overschrijven bij regeneratie).
  async function uploadToolPdf(toolId, blob) {
    const pad = toolId + '/productfiche.pdf';
    const { error } = await client().storage.from('tool-fiches')
      .upload(pad, blob, { upsert: true, contentType: 'application/pdf' });
    if (error) throw error;
    const { data } = client().storage.from('tool-fiches').getPublicUrl(pad);
    return { pad, url: data.publicUrl + '?t=' + Date.now() };
  }

  // ---------- consultants (profielenbibliotheek) ----------
  async function getConsultants() {
    return check(await client().from('consultant').select('*').order('naam'));
  }
  async function getConsultant(id) {
    return check(await client().from('consultant').select('*').eq('id', id).single());
  }
  async function upsertConsultant(c) {
    return check(await client().from('consultant')
      .upsert({ ...c, updated_at: new Date().toISOString() }).select().single());
  }
  async function updateConsultant(id, patch) {
    return check(await client().from('consultant')
      .update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id).select().single());
  }
  async function deleteConsultant(id) {
    return check(await client().from('consultant').delete().eq('id', id));
  }
  // Foto of CV naar Storage (consultant-fiches/{id}/{soort}-...). soort = 'foto' | 'cv'.
  async function uploadConsultantFile(consultantId, file, soort) {
    const safe = (file.name || soort).replace(/[^\w.\-]+/g, '_');
    const pad = consultantId + '/' + soort + '-' + Date.now() + '-' + safe;
    const { error } = await client().storage.from('consultant-fiches').upload(pad, file, { upsert: true });
    if (error) throw error;
    const { data } = client().storage.from('consultant-fiches').getPublicUrl(pad);
    return { url: data.publicUrl, naam: file.name };
  }
  // Gegenereerde profiel-PDF naar Storage. soort = 'kort' | 'detail' (aparte bestanden).
  async function uploadConsultantPdf(consultantId, blob, soort) {
    const pad = consultantId + '/profiel-' + (soort === 'detail' ? 'detail' : 'kort') + '.pdf';
    const { error } = await client().storage.from('consultant-fiches')
      .upload(pad, blob, { upsert: true, contentType: 'application/pdf' });
    if (error) throw error;
    const { data } = client().storage.from('consultant-fiches').getPublicUrl(pad);
    return { pad, url: data.publicUrl + '?t=' + Date.now() };
  }

  // ---------- auth (login-beveiliging) ----------
  // De interne apps vereisen een ingelogde gebruiker (rol 'authenticated').
  // De publieke quickscan schrijft los hiervan via de SECURITY DEFINER-functie
  // registreer_quickscan en heeft dus GEEN login nodig.
  async function getSession() {
    const { data } = await client().auth.getSession();
    return data.session || null;
  }
  async function signIn(email, password) {
    const { data, error } = await client().auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data.session;
  }
  async function signOut() {
    try { await client().auth.signOut(); } catch (_) {}
  }
  function onAuth(cb) {
    client().auth.onAuthStateChange((_evt, session) => cb(session || null));
  }

  return {
    client, berekenNiveau, berekenFix,
    getSession, signIn, signOut, onAuth,
    getTools, getTool, upsertTool, updateTool, deleteTool, uploadToolPdf, uploadToolDoc,
    getConsultants, getConsultant, upsertConsultant, updateConsultant, deleteConsultant,
    uploadConsultantFile, uploadConsultantPdf,
    getTarieven, getTarievenLijst, setTarief, verwijderTarief, prijsVanEenheid,
    getInstelling, setInstelling,
    getLijnen,
    getStations, upsertStation, deleteStation,
    getCatalogus, getArtikel, upsertArtikel, updateArtikel, deleteArtikel,
    getKlanten, vindKlantOpBedrijf, upsertKlant, updateKlant, saveGesprek, getScansVanKlant, getAlleScans,
    getBedrijven, getContacten, updateBedrijf, updateContact, insertBedrijf, insertContact,
    deleteBedrijf, deleteContact, updateQuickscan, deleteQuickscan,
    zoekGelijkaardigeBedrijven, dubbeleBedrijven, voegBedrijvenSamen,
    getVoorstellen, updateVoorstel,
    getTemplates, upsertTemplate,
    getProspects,
    saveOfferte, getOffertes, getOfferte
  };
})();
