-- ============================================================
-- Tarieven: van één dagtarief naar 3 prijzen per rol.
-- uurprijs / halvedagprijs / heledagprijs — elk los in te vullen.
-- Bestaande dagtarief wordt omgezet: heledag = dagtarief,
-- halvedag = dagtarief/2, uur = dagtarief/8 (richtwaarden; pas gerust aan).
-- ============================================================

alter table tarieven
  add column if not exists uurprijs      numeric(10,2),
  add column if not exists halvedagprijs  numeric(10,2),
  add column if not exists heledagprijs   numeric(10,2);

update tarieven set
  heledagprijs  = coalesce(heledagprijs, dagtarief),
  halvedagprijs = coalesce(halvedagprijs, round(dagtarief / 2, 2)),
  uurprijs      = coalesce(uurprijs, round(dagtarief / 8, 2))
where dagtarief is not null;

alter table tarieven drop column if exists dagtarief;
