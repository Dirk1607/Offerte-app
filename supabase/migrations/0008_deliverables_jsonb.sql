-- 0008 — Deliverables terug als aparte lijst, nu als jsonb ("wat is af als het af is").
-- Los van de processtappen in de WBS (kolom wbs). In 0006 was de oude text-kolom
-- 'deliverables' gedropt; hier komt ze terug als jsonb-array van strings.
alter table artikel add column if not exists deliverables jsonb not null default '[]'::jsonb;
