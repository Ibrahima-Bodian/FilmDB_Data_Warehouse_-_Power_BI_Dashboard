-- Infos acteurs
CREATE OR REPLACE VIEW v_infos_acteurs AS
SELECT 
    a.actor_id AS acteur_id,
    a.first_name AS prenom,
    a.last_name AS nom,
    STRING_AGG(DISTINCT (c.name || ': ' || 
        (SELECT STRING_AGG(f.title, ', ')
         FROM film f
         JOIN film_category fc_1 ON f.film_id=fc_1.film_id
         JOIN film_actor fa_1 ON f.film_id=fa_1.film_id
         WHERE fc_1.category_id=c.category_id AND fa_1.actor_id=a.actor_id
         GROUP BY fa_1.actor_id)), ' | ') AS films_par_categorie
FROM actor a
LEFT JOIN film_actor fa ON a.actor_id=fa.actor_id
LEFT JOIN film_category fc ON fa.film_id=fc.film_id
LEFT JOIN category c ON fc.category_id=c.category_id
GROUP BY a.actor_id, a.first_name, a.last_name;


-- Liste des films
CREATE OR REPLACE VIEW v_liste_films AS
SELECT 
    f.film_id AS film_id,
    f.title AS titre,
    f.description AS description,
    c.name AS categorie,
    f.rental_rate AS prix_location,
    f.length AS duree_minutes,
    f.rating AS classification,
    STRING_AGG(a.first_name || ' ' || a.last_name, ', ') AS acteurs
FROM category c
LEFT JOIN film_category fc ON c.category_id=fc.category_id
LEFT JOIN film f ON fc.film_id=f.film_id
JOIN film_actor fa ON f.film_id=fa.film_id
JOIN actor a ON fa.actor_id=a.actor_id
GROUP BY f.film_id, f.title, f.description, c.name, f.rental_rate, f.length, f.rating;


-- Liste films (noms, acteurs)
CREATE OR REPLACE VIEW v_liste_films_noms_formates AS
SELECT 
    f.film_id AS film_id,
    f.title AS titre,
    f.description AS description,
    c.name AS categorie,
    f.rental_rate AS prix_location,
    f.length AS duree_minutes,
    f.rating AS classification,
    STRING_AGG(
        INITCAP(a.first_name) || ' ' || INITCAP(a.last_name), ', '
    ) AS acteurs
FROM category c
LEFT JOIN film_category fc ON c.category_id=fc.category_id
LEFT JOIN film f ON fc.film_id=f.film_id
JOIN film_actor fa ON f.film_id=fa.film_id
JOIN actor a ON fa.actor_id=a.actor_id
GROUP BY f.film_id, f.title, f.description, c.name, f.rental_rate, f.length, f.rating;


-- Les ventes par catégorie
CREATE OR REPLACE VIEW v_ventes_par_categorie AS
SELECT 
    c.name AS categorie,
    SUM(p.amount) AS total_ventes
FROM payment p
JOIN rental r ON p.rental_id=r.rental_id
JOIN inventory i ON r.inventory_id=i.inventory_id
JOIN film f ON i.film_id=f.film_id
JOIN film_category fc ON f.film_id=fc.film_id
JOIN category c ON fc.category_id=c.category_id
GROUP BY c.name
ORDER BY total_ventes DESC;


-- Les ventes par magasin
CREATE OR REPLACE VIEW v_ventes_par_magasin AS
SELECT 
    (ci.city || ', ' || co.country) AS magasin,
    (m.first_name || ' ' || m.last_name) AS manager,
    SUM(p.amount) AS total_ventes
FROM payment p
JOIN rental r ON p.rental_id=r.rental_id
JOIN inventory i ON r.inventory_id=i.inventory_id
JOIN store s ON i.store_id=s.store_id
JOIN address a ON s.address_id=a.address_id
JOIN city ci ON a.city_id=ci.city_id
JOIN country co ON ci.country_id=co.country_id
JOIN staff m ON s.manager_staff_id=m.staff_id
GROUP BY co.country, ci.city, s.store_id, m.first_name, m.last_name
ORDER BY co.country, ci.city;


-- Liste du personnel
CREATE OR REPLACE VIEW v_liste_personnel AS
SELECT 
    s.staff_id AS id_personnel,
    (s.first_name || ' ' || s.last_name) AS nom_complet,
    a.address AS adresse,
    a.postal_code AS code_postal,
    a.phone AS telephone,
    ci.city AS ville,
    co.country AS pays,
    s.store_id AS magasin_id
FROM staff s
JOIN address a ON s.address_id=a.address_id
JOIN city ci ON a.city_id=ci.city_id
JOIN country co ON ci.country_id=co.country_id;




-- Calendrier (dimension date)
CREATE OR REPLACE VIEW v_calendrier AS
WITH b AS (
  SELECT MIN(payment_date)::date AS d_min,
         MAX(payment_date)::date AS d_max
  FROM payment
)
SELECT gs::date AS date,
       EXTRACT(YEAR FROM gs)::int AS annee,
       EXTRACT(QUARTER FROM gs)::int AS trimestre,
       EXTRACT(MONTH FROM gs)::int AS mois,
       EXTRACT(DAY FROM gs)::int AS jour,
       DATE_TRUNC('month', gs)::date AS debut_mois,
       DATE_TRUNC('quarter', gs)::date AS debut_trimestre,
       DATE_TRUNC('year', gs)::date AS debut_annee
FROM b, generate_series(b.d_min, b.d_max, interval '1 day') AS gs;

-- Fait Paiement enrichi
CREATE OR REPLACE VIEW v_fait_paiement AS
SELECT 
  p.payment_id AS paiement_id,
  p.amount AS montant,
  p.payment_date AS date_paiement,
  r.rental_id AS location_id,
  s.store_id AS magasin_id,
  st.staff_id AS employe_id,
  c.customer_id AS client_id,
  (c.first_name || ' ' || c.last_name) AS nom_client,
  i.inventory_id AS inventaire_id,
  f.film_id AS film_id,
  f.title AS titre_film,
  cat.category_id AS categorie_id,
  cat.name AS nom_categorie
FROM payment p
LEFT JOIN rental r ON r.rental_id = p.rental_id
LEFT JOIN staff st ON st.staff_id = p.staff_id
LEFT JOIN store  s ON s.store_id  = st.store_id
LEFT JOIN customer c ON c.customer_id = p.customer_id
LEFT JOIN inventory i ON i.inventory_id = r.inventory_id
LEFT JOIN film f ON f.film_id = i.film_id
LEFT JOIN film_category fc ON fc.film_id = f.film_id
LEFT JOIN category cat ON cat.category_id = fc.category_id;

-- KPI par magasin et par mois
CREATE OR REPLACE VIEW v_kpi_magasin_mois AS
SELECT
  magasin_id,
  DATE_TRUNC('month', date_paiement)::date AS mois,
  COUNT(DISTINCT location_id) AS nb_locations,
  SUM(montant)::numeric(12,2) AS ca,
  (SUM(montant) / NULLIF(COUNT(DISTINCT location_id),0))::numeric(12,2) AS panier_moyen
FROM v_fait_paiement
GROUP BY magasin_id, DATE_TRUNC('month', date_paiement)
ORDER BY magasin_id, mois;

-- KPI Catégorie par mois
CREATE OR REPLACE VIEW v_kpi_categorie_mois AS
SELECT
  categorie_id,
  nom_categorie,
  DATE_TRUNC('month', date_paiement)::date AS mois,
  SUM(montant)::numeric(12,2) AS ca,
  COUNT(DISTINCT location_id) AS nb_locations
FROM v_fait_paiement
GROUP BY categorie_id, nom_categorie, DATE_TRUNC('month', date_paiement)
ORDER BY mois, ca DESC;

-- Revenu par film (par mois & total)
CREATE OR REPLACE VIEW v_revenu_film_mois AS
SELECT
  film_id,
  titre_film,
  DATE_TRUNC('month', date_paiement)::date AS mois,
  SUM(montant)::numeric(12,2) AS ca,
  COUNT(*) AS nb_paiements
FROM v_fait_paiement
GROUP BY film_id, titre_film, DATE_TRUNC('month', date_paiement);

CREATE OR REPLACE VIEW v_revenu_film_total AS
SELECT
  film_id,
  titre_film,
  SUM(montant)::numeric(12,2) AS ca_total,
  COUNT(*) AS nb_paiements
FROM v_fait_paiement
GROUP BY film_id, titre_film
ORDER BY ca_total DESC;

-- Valeur client (fréquence & valeur)
CREATE OR REPLACE VIEW v_valeur_client AS
SELECT
  client_id,
  nom_client,
  COUNT(DISTINCT location_id) AS nb_locations,
  SUM(montant)::numeric(12,2) AS ca_total,
  MIN(date_paiement)::date AS premiere_achat,
  MAX(date_paiement)::date AS dernier_achat
FROM v_fait_paiement
GROUP BY client_id, nom_client
ORDER BY nb_locations DESC, ca_total DESC;


-- Retards (par location) + agrégations

CREATE OR REPLACE VIEW v_retard_location AS
SELECT
  r.rental_id AS location_id,
  r.customer_id AS client_id,
  r.staff_id AS employe_id,
  i.store_id AS magasin_id,
  r.rental_date AS date_location,
  r.return_date AS date_retour,
  f.rental_duration AS duree_location_jours,
  GREATEST(EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration, 0)::int AS retard_jours
FROM rental r
JOIN inventory i ON i.inventory_id = r.inventory_id
JOIN film f ON f.film_id = i.film_id
WHERE r.return_date IS NOT NULL;

CREATE OR REPLACE VIEW v_retard_par_magasin AS
SELECT magasin_id,
       AVG(retard_jours)::numeric(10,2) AS retard_moyen_jours,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY retard_jours) AS retard_median_jours,
       COUNT(*) AS nb_locations
FROM v_retard_location
GROUP BY magasin_id
ORDER BY magasin_id;

CREATE OR REPLACE VIEW v_retard_par_client AS
SELECT client_id,
       AVG(retard_jours)::numeric(10,2) AS retard_moyen_jours,
       COUNT(*) AS nb_locations
FROM v_retard_location
GROUP BY client_id
HAVING COUNT(*) >=5
ORDER BY retard_moyen_jours DESC;


-- Inventaire & disponibilité

CREATE OR REPLACE VIEW v_inventaire_magasin AS
SELECT s.store_id AS magasin_id, f.film_id, f.title AS titre_film, COUNT(*) AS exemplaires
FROM inventory i
JOIN store s ON s.store_id=i.store_id
JOIN film  f ON f.film_id=i.film_id
GROUP BY s.store_id, f.film_id, f.title;

CREATE OR REPLACE VIEW v_disponibilite_stock AS
WITH en_cours AS (
  SELECT i.store_id AS magasin_id, COUNT(*) AS nb_en_cours
  FROM inventory i
  JOIN rental r ON r.inventory_id=i.inventory_id
  WHERE r.return_date IS NULL
  GROUP BY i.store_id
),
tot AS (
  SELECT store_id AS magasin_id, COUNT(*) AS nb_total
  FROM inventory
  GROUP BY store_id
)
SELECT t.magasin_id,
       t.nb_total,
       COALESCE(e.nb_en_cours,0) AS nb_en_cours,
       (t.nb_total - COALESCE(e.nb_en_cours,0)) AS nb_disponibles
FROM tot t
LEFT JOIN en_cours e ON e.magasin_id=t.magasin_id
ORDER BY t.magasin_id;


-- Rotation du stock (locations / exemplaire)

CREATE OR REPLACE VIEW v_rotation_stock AS
WITH loc AS (
  SELECT i.film_id, COUNT(*) AS nb_locations
  FROM rental r
  JOIN inventory i ON i.inventory_id=r.inventory_id
  GROUP BY i.film_id
),
ex AS (
  SELECT film_id, COUNT(*) AS nb_ex
  FROM inventory
  GROUP BY film_id
)
SELECT f.film_id, f.title AS titre_film,
       COALESCE(loc.nb_locations,0) AS nb_locations,
       ex.nb_ex,
       (COALESCE(loc.nb_locations,0)::numeric / NULLIF(ex.nb_ex,0))::numeric(10,2) AS rotation_par_exemplaire
FROM film f
LEFT JOIN loc ON loc.film_id=f.film_id
LEFT JOIN ex  ON ex.film_id=f.film_id
ORDER BY rotation_par_exemplaire DESC NULLS LAST;


-- Films jamais loués

CREATE OR REPLACE VIEW v_films_jamais_loues AS
SELECT f.film_id, f.title AS titre_film
FROM film f
LEFT JOIN inventory i ON i.film_id=f.film_id
LEFT JOIN rental r ON r.inventory_id=i.inventory_id
GROUP BY f.film_id, f.title
HAVING COUNT(r.rental_id)=0
ORDER BY titre_film;
