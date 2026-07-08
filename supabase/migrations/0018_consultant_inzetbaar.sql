-- 0018 — Consultant: inzetbaarheid per metrolijn/versneller.
-- Veel expertise op een lijn wil niet zeggen dat de consultant daar ook voor
-- ingeschakeld wordt. `inzetbaar` = { CODE: true|false } markeert per metrolijn/
-- versneller of deze consultant er effectief voor kan worden ingezet.
-- Op het TNL Profiel kleurt dit de expertise-balken (blauw = inzetbaar, grijs = enkel expertise).
alter table consultant add column if not exists inzetbaar jsonb not null default '{}'::jsonb;
