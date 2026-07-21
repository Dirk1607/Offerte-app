-- 0031 — NextStone (artikel): rubriek "Processen (voor de offerte)" wordt "Bijlagen".
-- Zelfde vorm ({ naam, data }), enkel hernoemd naar wat het nu is: vrije bijlages.
alter table artikel rename column processen to bijlagen;
