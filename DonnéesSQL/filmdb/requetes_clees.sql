-- KPI de base par période et magasin
-- CA, nb locations, panier moyen.
WITH borne AS (
  SELECT MIN(payment_date)::date AS d_debut,
         MAX(payment_date)::date AS d_fin
  FROM payment
)
SELECT s.store_id,
       DATE_TRUNC('month', p.payment_date) AS mois,
       COUNT(DISTINCT r.rental_id) AS nb_locations,
       SUM(p.amount)::numeric(10,2) AS ca,
       (SUM(p.amount)/NULLIF(COUNT(DISTINCT r.rental_id),0))::numeric(10,2) AS panier_moyen
FROM payment p
LEFT JOIN rental r ON r.rental_id=p.rental_id
JOIN staff st ON st.staff_id=p.staff_id
JOIN store s ON s.store_id=st.store_id
JOIN borne b ON p.payment_date::date BETWEEN b.d_debut AND b.d_fin
GROUP BY s.store_id, DATE_TRUNC('month', p.payment_date)
ORDER BY s.store_id, mois;




-- Top catégories par CA (période)
WITH borne AS (
  SELECT MIN(payment_date)::date AS d_debut,
         MAX(payment_date)::date AS d_fin
  FROM payment
)
SELECT c.name AS categorie,
       SUM(p.amount)::numeric(10,2) AS ca,
       COUNT(DISTINCT r.rental_id) AS nb_locations
FROM payment p
LEFT JOIN rental r ON r.rental_id=p.rental_id
LEFT JOIN inventory i ON i.inventory_id=r.inventory_id
LEFT JOIN film f ON f.film_id=i.film_id
LEFT JOIN film_category fc ON fc.film_id=f.film_id
LEFT JOIN category c ON c.category_id=fc.category_id
JOIN borne b ON p.payment_date::date BETWEEN b.d_debut AND b.d_fin
GROUP BY c.name
HAVING SUM(p.amount) IS NOT NULL   --pour élimner les catégories totalement nulles
ORDER BY ca DESC
LIMIT 10;


-- Top 10 films par revenu (période)
WITH borne AS (
  SELECT MIN(payment_date)::date AS d_debut,
         MAX(payment_date)::date AS d_fin
  FROM payment
)
SELECT f.film_id, f.title,
       SUM(p.amount)::numeric(10,2) AS ca,
       COUNT(*) AS nb_paiements
FROM payment p
LEFT JOIN rental r ON r.rental_id=p.rental_id
LEFT JOIN inventory i ON i.inventory_id=r.inventory_id
LEFT JOIN film f ON f.film_id=i.film_id
JOIN borne b ON p.payment_date::date BETWEEN b.d_debut AND b.d_fin
GROUP BY f.film_id, f.title
HAVING SUM(p.amount) IS NOT NULL
ORDER BY ca DESC
LIMIT 10;

-- Retards (jours de retard moyens) par magasin
SELECT s.store_id,
       AVG(GREATEST(EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration, 0))::numeric(10,2) AS retard_moy_jours
FROM rental r
JOIN inventory i ON i.inventory_id=r.inventory_id
JOIN film f ON f.film_id=i.film_id
JOIN store s ON s.store_id=i.store_id
WHERE r.return_date IS NOT NULL
GROUP BY s.store_id
ORDER BY s.store_id;



-- Clients fidèles (fréquence et valeur)
--Top clients par nb de locations et CA dans la période.
WITH borne AS (
  SELECT MIN(payment_date)::date AS d_debut,
         MAX(payment_date)::date AS d_fin
  FROM payment
)
SELECT c.customer_id,
       c.first_name || ' ' || c.last_name AS client,
       COUNT(DISTINCT r.rental_id) AS nb_locations,
       SUM(p.amount)::numeric(10,2) AS ca
FROM customer c
JOIN rental r ON r.customer_id = c.customer_id
JOIN payment p ON p.rental_id = r.rental_id
JOIN borne b ON p.payment_date::date BETWEEN b.d_debut AND b.d_fin
GROUP BY c.customer_id, client
HAVING COUNT(DISTINCT r.rental_id) >= 5 -- j'ai choisi 5
ORDER BY nb_locations DESC, ca DESC
LIMIT 20;



-- Taux de rotation du stock (par film)
WITH loc AS (
  SELECT i.film_id, COUNT(*) AS nb_loc
  FROM rental r
  JOIN inventory i ON i.inventory_id=r.inventory_id
  GROUP BY i.film_id
),
ex AS (
  SELECT film_id, COUNT(*) AS nb_ex
  FROM inventory
  GROUP BY film_id
)
SELECT f.film_id, f.title,
       COALESCE(loc.nb_loc,0) AS nb_locations,
       ex.nb_ex,
       (COALESCE(loc.nb_loc,0)::numeric / NULLIF(ex.nb_ex,0))::numeric(10,2) AS rotation_par_exemplaire
FROM film f
LEFT JOIN loc ON loc.film_id=f.film_id
LEFT JOIN ex  ON ex.film_id=f.film_id
ORDER BY rotation_par_exemplaire DESC NULLS LAST
LIMIT 20;



-- Disponibilité / stock “theorique” en magasin
--Inventaire total par magasin et nb en cours de location.
WITH out_now AS (
  SELECT i.store_id, COUNT(*) AS nb_sortis
  FROM inventory i
  JOIN rental r ON r.inventory_id=i.inventory_id
  WHERE r.return_date IS NULL
  GROUP BY i.store_id
),
tot AS (
  SELECT store_id, COUNT(*) AS nb_total
  FROM inventory
  GROUP BY store_id
)
SELECT s.store_id,
       tot.nb_total,
       COALESCE(out_now.nb_sortis,0) AS nb_en_cours,
       (tot.nb_total - COALESCE(out_now.nb_sortis,0)) AS nb_disponibles
FROM store s
JOIN tot ON tot.store_id=s.store_id
LEFT JOIN out_now ON out_now.store_id=s.store_id
ORDER BY s.store_id;



-- Films jamais loués
SELECT f.film_id, f.title
FROM film f
LEFT JOIN inventory i ON i.film_id=f.film_id
LEFT JOIN rental r ON r.inventory_id=i.inventory_id
GROUP BY f.film_id, f.title
HAVING COUNT(r.rental_id)=0
ORDER BY f.title;



-- Revenu par catégorie et magasin (heatmap potentiel)
SELECT s.store_id, c.name AS categorie,
       SUM(p.amount)::numeric(10,2) AS ca
FROM payment p
JOIN rental r ON r.rental_id=p.rental_id
JOIN inventory i ON i.inventory_id=r.inventory_id
JOIN store s ON s.store_id=i.store_id
JOIN film f ON f.film_id=i.film_id
JOIN film_category fc ON fc.film_id=f.film_id
JOIN category c ON c.category_id=fc.category_id
GROUP BY s.store_id, c.name
ORDER BY s.store_id, ca DESC;





-- Clients “à risque” (retours souvent en retard)
SELECT c.customer_id,
       c.first_name || ' ' || c.last_name AS client,
       AVG(GREATEST(EXTRACT(DAY FROM (r.return_date - r.rental_date)) - f.rental_duration, 0))::numeric(10,2) AS retard_moy,
       COUNT(*) AS nb_locations
FROM customer c
JOIN rental r ON r.customer_id=c.customer_id
JOIN inventory i ON i.inventory_id=r.inventory_id
JOIN film f ON f.film_id=i.film_id
WHERE r.return_date IS NOT NULL
GROUP BY c.customer_id, client
HAVING COUNT(*)>=5
ORDER BY retard_moy DESC, nb_locations DESC
LIMIT 20;
