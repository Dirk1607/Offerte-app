-- 0011 — Tools: rubriek "Gebruikte processen" met optioneel document per proces.
-- processen = [{ naam, doc_url, doc_naam }]. Documenten gaan naar de bestaande
-- storage-bucket 'tool-fiches' onder pad {tool_id}/docs/...
alter table tools add column if not exists processen jsonb not null default '[]'::jsonb;
