-- 0007 — Afkorting per rol (plaatsbesparing in de WBS-weergave).
alter table tarieven add column if not exists afkorting text;
