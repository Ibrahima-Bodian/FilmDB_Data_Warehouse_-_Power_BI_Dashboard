BEGIN;

-- Extension & connexion vers la base source "filmdb"
CREATE EXTENSION IF NOT EXISTS dblink;

-- connexion
SELECT dblink_connect(
  'src',
  'host=127.0.0.1 port=5432 dbname=filmdb user=postgres password=postgres'
);

-- Index d’unicité
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_client_source ON public.dim_client (source_client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_magasin_source ON public.dim_magasin (source_magasin_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_categorie_source ON public.dim_categorie (source_categorie_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_film_source ON public.dim_film (source_film_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_fact_paiement_source ON public.fact_paiement (source_paiement_id);

-- Pour DIM DATE (basée sur payment.payment_date)
WITH bornes AS (
  SELECT d_min, d_max
  FROM dblink('src',
     'SELECT MIN(payment_date)::date AS d_min, MAX(payment_date)::date AS d_max FROM public.payment'
  ) AS t(d_min date, d_max date)
)
INSERT INTO public.dim_date (date_key, date, annee, trimestre, mois, jour, debut_mois, debut_trimestre, debut_annee)
SELECT (EXTRACT(YEAR FROM d)*10000 + EXTRACT(MONTH FROM d)*100 + EXTRACT(DAY FROM d))::int AS date_key,
       d::date,
       EXTRACT(YEAR FROM d)::int,
       EXTRACT(QUARTER FROM d)::int,
       EXTRACT(MONTH FROM d)::int,
       EXTRACT(DAY FROM d)::int,
       DATE_TRUNC('month', d)::date,
       DATE_TRUNC('quarter', d)::date,
       DATE_TRUNC('year', d)::date
FROM bornes b, GENERATE_SERIES(b.d_min, b.d_max, INTERVAL '1 day') AS d
ON CONFLICT (date_key) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_dim_date_y_m ON public.dim_date (annee, mois);

-- 2) DIM CATEGORIE
INSERT INTO public.dim_categorie (source_categorie_id, nom_categorie)
SELECT *
FROM dblink('src',
  'SELECT category_id, name FROM public.category'
) AS t(source_categorie_id int, nom_categorie text)
ON CONFLICT (source_categorie_id) DO UPDATE
SET nom_categorie=EXCLUDED.nom_categorie;

CREATE INDEX IF NOT EXISTS idx_dim_categorie_nom ON public.dim_categorie (nom_categorie);

-- DIM CLIENT
INSERT INTO public.dim_client (source_client_id, nom_client, email, adresse, ville, pays, date_inscription, actif)
SELECT *
FROM dblink('src', $SQL$
  SELECT DISTINCT
         c.customer_id AS source_client_id,
         (c.first_name || ' ' || c.last_name) AS nom_client,
         c.email,
         a.address AS adresse,
         ci.city AS ville,
         co.country AS pays,
         c.create_date AS date_inscription,
         c.activebool AS actif
  FROM public.customer c
  JOIN public.address a ON a.address_id=c.address_id
  JOIN public.city ci ON ci.city_id=a.city_id
  JOIN public.country co ON co.country_id=ci.country_id
$SQL$) AS t(
  source_client_id int, nom_client text, email text, adresse text,
  ville text, pays text, date_inscription date, actif boolean
)
ON CONFLICT (source_client_id) DO UPDATE
SET nom_client=EXCLUDED.nom_client,
    email = EXCLUDED.email,
    adresse= EXCLUDED.adresse,
    ville= EXCLUDED.ville,
    pays = EXCLUDED.pays,
    date_inscription=EXCLUDED.date_inscription,
    actif= EXCLUDED.actif;

CREATE INDEX IF NOT EXISTS idx_dim_client_nom ON public.dim_client (nom_client);
CREATE INDEX IF NOT EXISTS idx_dim_client_ville_pays ON public.dim_client (ville, pays);

-- DIM MAGASIN
INSERT INTO public.dim_magasin (source_magasin_id, manager, adresse, ville, pays)
SELECT *
FROM dblink('src', $SQL$
  SELECT s.store_id AS source_magasin_id,
         (m.first_name || ' ' || m.last_name) AS manager,
         a.address AS adresse,
         ci.city AS ville,
         co.country AS pays
  FROM public.store s
  JOIN public.staff m ON m.staff_id=s.manager_staff_id
  JOIN public.address a ON a.address_id=s.address_id
  JOIN public.city ci ON ci.city_id=a.city_id
  JOIN public.country co ON co.country_id=ci.country_id
$SQL$) AS t(source_magasin_id int, manager text, adresse text, ville text, pays text)
ON CONFLICT (source_magasin_id) DO UPDATE
SET manager=EXCLUDED.manager,
    adresse=EXCLUDED.adresse,
    ville=EXCLUDED.ville,
    pays=EXCLUDED.pays;

-- DIM FILM (catégorie principale = MIN(nom) par film)
WITH cat_principale AS (
  SELECT *
  FROM dblink('src', $SQL$
    SELECT f.film_id,
           MIN(c.name) AS categorie_principale
    FROM public.film f
    JOIN public.film_category fc ON fc.film_id=f.film_id
    JOIN public.category c ON c.category_id=fc.category_id
    GROUP BY f.film_id
  $SQL$) AS t(film_id int, categorie_principale text)
)
INSERT INTO public.dim_film (source_film_id, titre_film, duree_minutes, prix_location, classification, categorie_key)
SELECT f.source_film_id,
       f.titre_film,
       f.duree_minutes,
       f.prix_location,
       f.classification,
       dcat.categorie_key
FROM (
  SELECT *
  FROM dblink('src', $SQL$
    SELECT f.film_id AS source_film_id,
           f.title AS titre_film,
           f.length AS duree_minutes,
           f.rental_rate AS prix_location,
           f.rating::text AS classification
    FROM public.film f
  $SQL$) AS t(source_film_id int, titre_film text, duree_minutes int, prix_location numeric(6,2), classification text)
) f
LEFT JOIN cat_principale cp ON cp.film_id=f.source_film_id
LEFT JOIN public.dim_categorie dcat ON dcat.nom_categorie=cp.categorie_principale
ON CONFLICT (source_film_id) DO UPDATE
SET titre_film=EXCLUDED.titre_film,
    duree_minutes=EXCLUDED.duree_minutes,
    prix_location=EXCLUDED.prix_location,
    classification=EXCLUDED.classification,
    categorie_key=EXCLUDED.categorie_key;

CREATE INDEX IF NOT EXISTS idx_dim_film_titre ON public.dim_film (titre_film);
CREATE INDEX IF NOT EXISTS idx_dim_film_categorie ON public.dim_film (categorie_key);

-- FACT PAIEMENT (grain = un paiement)
WITH base AS (
  SELECT *
  FROM dblink('src', $SQL$
    SELECT 
      p.payment_id AS source_paiement_id,
      p.payment_date::date AS d,
      p.amount AS montant,
      s.store_id AS source_magasin_id,
      p.customer_id AS source_client_id,
      f.film_id AS source_film_id
    FROM public.payment p
    JOIN public.rental r ON r.rental_id=p.rental_id
    JOIN public.inventory i ON i.inventory_id=r.inventory_id
    JOIN public.film f ON f.film_id=i.film_id
    JOIN public.staff st ON st.staff_id=p.staff_id
    JOIN public.store s ON s.store_id=st.store_id
  $SQL$) AS t(
    source_paiement_id int, d date, montant numeric(12,2),
    source_magasin_id int, source_client_id int, source_film_id int
  )
)
INSERT INTO public.fact_paiement (
  source_paiement_id, date_key, magasin_key, client_key, film_key, categorie_key, montant
)
SELECT 
  b.source_paiement_id,
  (EXTRACT(YEAR FROM b.d)*10000 + EXTRACT(MONTH FROM b.d)*100 + EXTRACT(DAY FROM b.d))::int AS date_key,
  dm.magasin_key,
  dc.client_key,
  df.film_key,
  df.categorie_key,
  b.montant
FROM base b
JOIN public.dim_date dd ON dd.date_key=(EXTRACT(YEAR FROM b.d)*10000 + EXTRACT(MONTH FROM b.d)*100 + EXTRACT(DAY FROM b.d))::int
LEFT JOIN public.dim_magasin dm ON dm.source_magasin_id=b.source_magasin_id
LEFT JOIN public.dim_client dc ON dc.source_client_id=b.source_client_id
LEFT JOIN public.dim_film df ON df.source_film_id=b.source_film_id
ON CONFLICT (source_paiement_id) DO UPDATE
SET date_key=EXCLUDED.date_key,
    magasin_key=EXCLUDED.magasin_key,
    client_key=EXCLUDED.client_key,
    film_key=EXCLUDED.film_key,
    categorie_key=EXCLUDED.categorie_key,
    montant=EXCLUDED.montant;

-- Déconnexion dblink
SELECT dblink_disconnect('src');

COMMIT;