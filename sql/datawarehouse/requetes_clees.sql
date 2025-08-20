-- 1) KPI par magasin et par mois
-- Suivre chaque mois le CA, le nombre de paiements et le panier moyen par magasin.
-- Pour comparer les magasins et repérer la saisonnalité.
SELECT
  COALESCE(m.source_magasin_id, -1) AS magasin_id,
  DATE_TRUNC('month', d.date)::date AS mois,
  COUNT(DISTINCT f.source_paiement_id) AS nb_paiements,
  SUM(f.montant)::numeric(12,2) AS ca,
  (SUM(f.montant)/NULLIF(COUNT(DISTINCT f.source_paiement_id),0))::numeric(12,2) AS panier_moyen
FROM public.fact_paiement f
JOIN public.dim_date d ON d.date_key=f.date_key
LEFT JOIN public.dim_magasin m ON m.magasin_key=f.magasin_key
GROUP BY COALESCE(m.source_magasin_id, -1), DATE_TRUNC('month', d.date)
ORDER BY magasin_id, mois;





-- 2) Top catégories par CA (historique complet)
-- Identifier les catégories qui génèrent le plus de chiffre d’affaires.
-- Pour prioriser les familles de produits à pousser.
SELECT
  COALESCE(c.nom_categorie, 'Inconnu') AS nom_categorie,
  SUM(f.montant)::numeric(12,2) AS ca,
  COUNT(DISTINCT f.source_paiement_id) AS nb_paiements
FROM public.fact_paiement f
JOIN public.dim_date d ON d.date_key=f.date_key
LEFT JOIN public.dim_categorie c ON c.categorie_key=f.categorie_key
GROUP BY COALESCE(c.nom_categorie, 'Inconnu')
HAVING SUM(f.montant) IS NOT NULL
ORDER BY ca DESC
LIMIT 10;




-- 3) Top 10 films par revenu :
-- Classer les films par revenu total pour repérer les best-sellers.
-- Aide à décider des mises en avant et du réassort.
SELECT
  COALESCE(fi.titre_film, 'Inconnu') AS titre_film,
  SUM(f.montant)::numeric(12,2) AS ca,
  COUNT(*) AS nb_paiements
FROM public.fact_paiement f
JOIN public.dim_date d ON d.date_key=f.date_key
LEFT JOIN public.dim_film fi ON fi.film_key=f.film_key
GROUP BY COALESCE(fi.titre_film, 'Inconnu')
HAVING SUM(f.montant) IS NOT NULL
ORDER BY ca DESC
LIMIT 10;



-- 4) Clients fidèles (fréquence et valeur) :
-- Lister les clients avec au moins 3 paiements et mesurer leur CA cumulé.
-- Pour les actions de fidélisation/CRM.
SELECT
  c.source_client_id AS client_id,
  c.nom_client,
  COUNT(DISTINCT f.source_paiement_id) AS nb_paiements,
  SUM(f.montant)::numeric(12,2) AS ca
FROM public.fact_paiement f
JOIN public.dim_date d ON d.date_key=f.date_key
JOIN public.dim_client c ON c.client_key=f.client_key
GROUP BY c.source_client_id, c.nom_client
HAVING COUNT(DISTINCT f.source_paiement_id)>=3
ORDER BY nb_paiements DESC, ca DESC
LIMIT 50;



-- 5) Nouveaux vs récurrents (12 derniers mois) :
-- Distinguer les nouveaux clients des récurrents et mesurer leur part de CA.
-- Pour suivre l’acquisition vs la rétention.
WITH ref AS (
  SELECT MAX(d.date) AS maxd
  FROM public.fact_paiement f JOIN public.dim_date d ON d.date_key=f.date_key
),
premier_achat AS (
  SELECT c.client_key, MIN(d.date) AS first_purchase
  FROM public.fact_paiement f
  JOIN public.dim_date d ON d.date_key=f.date_key
  JOIN public.dim_client c ON c.client_key=f.client_key
  GROUP BY c.client_key
),
periode AS (
  SELECT f.*, d.date
  FROM public.fact_paiement f
  JOIN public.dim_date d ON d.date_key=f.date_key
  JOIN ref r ON TRUE
  WHERE d.date BETWEEN (date_trunc('month', r.maxd) - INTERVAL '11 months')::date AND r.maxd
)
SELECT
  CASE WHEN p.first_purchase BETWEEN (date_trunc('month', r.maxd) - INTERVAL '11 months')::date AND r.maxd
       THEN 'Nouveau' ELSE 'Récurrent' END AS segment,
  COUNT(DISTINCT pr.source_paiement_id) AS nb_paiements,
  SUM(pr.montant)::numeric(12,2) AS ca
FROM periode pr
JOIN premier_achat p ON p.client_key=pr.client_key
JOIN ref r ON TRUE
GROUP BY 1
ORDER BY segment;



-- 6) Tendance CA mensuelle :
-- Suivre l’évolution du chiffre d’affaires (CA) mois par mois pour voir tendance et saisonnalité.
-- Variante : ajouter l’identifiant magasin pour comparer les magasins entre eux.

SELECT
  DATE_TRUNC('month', d.date)::date AS mois,
  SUM(f.montant)::numeric(12,2) AS ca_total
FROM fact_paiement f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY DATE_TRUNC('month', d.date)
ORDER BY mois;




-- 7) Heatmap CA par magasin × catégorie :
-- Mesurer la contribution du CA par couple magasin–catégorie.
-- Pour repérer les combinaisons fortes/faibles.
SELECT
  COALESCE(m.source_magasin_id, -1) AS magasin_id,
  COALESCE(c.nom_categorie, 'Inconnu') AS nom_categorie,
  SUM(f.montant)::numeric(12,2) AS ca
FROM public.fact_paiement f
JOIN public.dim_date d ON d.date_key=f.date_key
LEFT JOIN public.dim_magasin m ON m.magasin_key=f.magasin_key
LEFT JOIN public.dim_categorie c ON c.categorie_key=f.categorie_key
GROUP BY COALESCE(m.source_magasin_id, -1), COALESCE(c.nom_categorie, 'Inconnu')
ORDER BY magasin_id, ca DESC;




-- 8) Cohortes d’acquisition :
-- Regroupe les clients par mois de 1er achat, puis compte combien restent actifs mois après mois.
-- Utile pour mesurer la rétention et l’efficacité de l’acquisition.

WITH first_buy AS (
  SELECT c.client_key, DATE_TRUNC('month', MIN(d.date))::date AS mois_cohort
  FROM fact_paiement f
  JOIN dim_date d ON d.date_key=f.date_key
  JOIN dim_client c ON c.client_key=f.client_key
  GROUP BY c.client_key
),
activity AS (
  SELECT c.client_key, DATE_TRUNC('month', d.date)::date AS mois_activite
  FROM fact_paiement f
  JOIN dim_date d ON d.date_key=f.date_key
  JOIN dim_client c ON c.client_key=f.client_key
)
SELECT
  fb.mois_cohort,
  a.mois_activite,
  EXTRACT(YEAR FROM age(a.mois_activite, fb.mois_cohort))*12
    + EXTRACT(MONTH FROM age(a.mois_activite, fb.mois_cohort)) AS mois_depuis_acquisition,
  COUNT(DISTINCT a.client_key) AS clients_actifs
FROM first_buy fb
JOIN activity a ON a.client_key=fb.client_key
GROUP BY fb.mois_cohort, a.mois_activite
ORDER BY fb.mois_cohort, a.mois_activite;



-- 9) RFM simplifié :
-- Donne à chaque client un score R (Récence), F (Fréquence), M (Montant) de 1 à 5.
-- Sert à segmenter : ex. 5-5-5 = clients VIP récents et très actifs.
WITH ref AS (SELECT MAX(d.date) AS d_ref FROM fact_paiement f JOIN dim_date d ON d.date_key=f.date_key),
base AS (
  SELECT
    c.client_key,
    MAX(d.date) AS last_purchase,
    COUNT(DISTINCT f.source_paiement_id) AS freq,
    SUM(f.montant) AS monetary
  FROM fact_paiement f
  JOIN dim_date d ON d.date_key=f.date_key
  JOIN dim_client c ON c.client_key=f.client_key
  GROUP BY c.client_key
),
rfm AS (
  SELECT
    b.*,
    (SELECT d_ref FROM ref) - b.last_purchase AS recency_interval
  FROM base b
)
SELECT
  client_key,
  NTILE(5) OVER (ORDER BY recency_interval DESC) AS R_score, -- plus récent = meilleur score (5)
  NTILE(5) OVER (ORDER BY freq ASC) AS F_score,
  NTILE(5) OVER (ORDER BY monetary ASC) AS M_score
FROM rfm;



-- 10) Jours “anormaux” (z-score du CA quotidien) :
-- Détecter les jours avec un CA inhabituel (pics/creux) pour enquête.
-- Sert à expliquer promotions, incidents ou événements particuliers.
WITH daily AS (
  SELECT d.date, SUM(f.montant) AS ca_jour
  FROM public.fact_paiement f
  JOIN public.dim_date d ON d.date_key=f.date_key
  GROUP BY d.date
),
stats AS (
  SELECT AVG(ca_jour) AS mu, STDDEV_POP(ca_jour) AS sigma FROM daily
)
SELECT *
FROM (
  SELECT
    dy.date,
    dy.ca_jour,
    CASE WHEN st.sigma=0 THEN 0
         ELSE (dy.ca_jour - st.mu)/st.sigma
    END AS zscore
  FROM daily dy CROSS JOIN stats st
  WHERE st.sigma>0
) t
ORDER BY ABS(t.zscore) DESC
LIMIT 30;



-- (11) Croissance MoM / YoY :
-- Calcule la variation du CA par rapport au mois précédent (MoM) et au même mois l’année d’avant (YoY),
-- en valeur et en pourcentage, pour suivre la croissance.
WITH m AS (
  SELECT DATE_TRUNC('month', d.date)::date AS mois, SUM(f.montant) AS ca
  FROM fact_paiement f JOIN dim_date d ON d.date_key=f.date_key
  GROUP BY DATE_TRUNC('month', d.date)
)
SELECT
  m1.mois,
  m1.ca AS ca_mois,
  (m1.ca - LAG(m1.ca)  OVER (ORDER BY m1.mois)) AS var_mom,
  CASE WHEN LAG(m1.ca) OVER (ORDER BY m1.mois)=0 THEN NULL
       ELSE (m1.ca - LAG(m1.ca) OVER (ORDER BY m1.mois)) / LAG(m1.ca) OVER (ORDER BY m1.mois)
  END AS pct_mom,
  (m1.ca - LAG(m1.ca,12) OVER (ORDER BY m1.mois)) AS var_yoy,
  CASE WHEN LAG(m1.ca,12) OVER (ORDER BY m1.mois)=0 THEN NULL
       ELSE (m1.ca - LAG(m1.ca,12) OVER (ORDER BY m1.mois)) / LAG(m1.ca,12) OVER (ORDER BY m1.mois)
  END AS pct_yoy
FROM m m1
ORDER BY m1.mois;



-- 12) CA roulant 30 jours (par magasin) :
-- Somme du CA des 30 derniers jours glissants, par magasin.
-- Lisse le quotidien et met en évidence la tendance récente.
SELECT
  m.source_magasin_id AS magasin_id,
  d.date,
  SUM(f.montant) OVER (
    PARTITION BY m.source_magasin_id
    ORDER BY d.date
    ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
  )::numeric(14,2) AS ca_rolling_30j
FROM fact_paiement f
JOIN dim_date d ON d.date_key=f.date_key
LEFT JOIN dim_magasin m ON m.magasin_key=f.magasin_key
ORDER BY magasin_id, d.date;



-- Agrégats mensuels par magasin (ajout de date_key_mois en dernière colonne)
CREATE OR REPLACE VIEW v_agg_mensuel_magasin AS
SELECT
  m.magasin_key,
  date_trunc('month', d.date)::date AS mois,
  SUM(f.montant)::numeric(14,2) AS ca,
  COUNT(DISTINCT f.source_paiement_id) AS nb_paiements,
  (EXTRACT(YEAR FROM d.date)::int*10000 + EXTRACT(MONTH FROM d.date)::int*100 + 1)::int AS date_key_mois
FROM fact_paiement f
JOIN dim_date d ON d.date_key=f.date_key
LEFT JOIN dim_magasin m ON m.magasin_key=f.magasin_key
GROUP BY
  m.magasin_key,
  date_trunc('month', d.date),
  (EXTRACT(YEAR FROM d.date)::int*10000 + EXTRACT(MONTH FROM d.date)::int*100 + 1)::int;

-- Agrégats mensuels par catégorie (ajout de date_key_mois en dernière colonne)
CREATE OR REPLACE VIEW v_agg_mensuel_categorie AS
SELECT
  c.categorie_key,
  date_trunc('month', d.date)::date AS mois,
  SUM(f.montant)::numeric(14,2) AS ca,
  COUNT(DISTINCT f.source_paiement_id) AS nb_paiements,
  (EXTRACT(YEAR FROM d.date)::int*10000 + EXTRACT(MONTH FROM d.date)::int*100 + 1)::int AS date_key_mois
FROM fact_paiement f
JOIN dim_date d ON d.date_key=f.date_key
LEFT JOIN dim_categorie c ON c.categorie_key=f.categorie_key
GROUP BY
  c.categorie_key,
  date_trunc('month', d.date),
  (EXTRACT(YEAR FROM d.date)::int*10000 + EXTRACT(MONTH FROM d.date)::int*100 + 1)::int;



-- Vue "mois" dérivée de dim_date, avec clé mois alignée sur v_agg_*
CREATE OR REPLACE VIEW v_dim_mois AS
SELECT DISTINCT
  date_trunc('month', date)::date AS mois,
  (annee*10000 + mois*100 + 1)::int AS date_key_mois,
  annee,
  mois AS mois_num,
  EXTRACT(QUARTER FROM date)::int AS trimestre,
  TO_CHAR(date_trunc('month', date), 'Mon YYYY') AS libelle_mois
FROM dim_date
ORDER BY mois;
