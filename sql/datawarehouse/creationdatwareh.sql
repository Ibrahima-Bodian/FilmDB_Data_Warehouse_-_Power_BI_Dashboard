CREATE database filmdb_dataware;
BEGIN;



-- 1) DIMENSIONS

-- DIM DATE (clé de substitution = yyyymmdd, ex: 20050630)
DROP TABLE IF EXISTS dim_date CASCADE;
CREATE TABLE dim_date (
  date_key integer PRIMARY KEY,
  date date NOT NULL,
  annee integer  NOT NULL,
  trimestre integer NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
  mois intege NOT NULL CHECK (mois BETWEEN 1 AND 12),
  jour integer NOT NULL CHECK (jour BETWEEN 1 AND 31),
  debut_mois date NOT NULL,
  debut_trimestre date NOT NULL,
  debut_annee date NOT NULL
);

COMMENT ON TABLE dim_date IS 'Dimension temps (jour) avec clé de substitution yyyymmdd.';
COMMENT ON COLUMN dim_date.date_key IS 'Clé de substitution (yyyymmdd).';
CREATE INDEX IF NOT EXISTS idx_dim_date_y_m ON dim_date (annee, mois);


-- DIM CLIENT
DROP TABLE IF EXISTS dim_client CASCADE;
CREATE TABLE dim_client (
  client_key integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_client_id  integer UNIQUE NOT NULL,
  nom_client text NOT NULL,
  email text,
  adresse text,
  ville text,
  pays text,
  date_inscription date,
  actif boolean
);

COMMENT ON TABLE dim_client IS 'Dimension client (clé de substitution + clé métier source_client_id).';
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_client_source ON dim_client (source_client_id);
CREATE INDEX IF NOT EXISTS idx_dim_client_nom ON dim_client (nom_client);
CREATE INDEX IF NOT EXISTS idx_dim_client_ville_pays ON dim_client (ville, pays);


-- DIM MAGASIN
DROP TABLE IF EXISTS dim_magasin CASCADE;
CREATE TABLE dim_magasin (
  magasin_key integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_magasin_id integer UNIQUE NOT NULL,
  manager text,
  adresse text,
  ville text,
  pays text
);

COMMENT ON TABLE dim_magasin IS 'Dimension magasin / point de vente.';
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_magasin_source ON dim_magasin (source_magasin_id);
CREATE INDEX IF NOT EXISTS idx_dim_magasin_ville_pays ON dim_magasin (ville, pays);


-- DIM CATEGORIE
DROP TABLE IF EXISTS dim_categorie CASCADE;
CREATE TABLE dim_categorie (
  categorie_key integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_categorie_id integer UNIQUE,
  nom_categorie text NOT NULL
);

COMMENT ON TABLE dim_categorie IS 'Dimension catégorie de film.';
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_categorie_source ON dim_categorie (source_categorie_id);
CREATE INDEX IF NOT EXISTS idx_dim_categorie_nom ON dim_categorie (nom_categorie);


-- DIM FILM
DROP TABLE IF EXISTS dim_film CASCADE;
CREATE TABLE dim_film(
  film_key integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_film_id integer UNIQUE NOT NULL,
  titre_film text NOT NULL,
  duree_minutes integer CHECK (duree_minutes IS NULL OR duree_minutes >= 0),
  prix_location numeric(8,2) CHECK (prix_location IS NULL OR prix_location >= 0),
  classification text,
  categorie_key integer REFERENCES dw.dim_categorie(categorie_key)
);

COMMENT ON TABLE dim_film IS 'Dimension film (catégorie principale optionnelle).';
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_film_source ON dim_film (source_film_id);
CREATE INDEX IF NOT EXISTS idx_dim_film_categorie ON dim_film (categorie_key);
CREATE INDEX IF NOT EXISTS idx_dim_film_titre ON dim_film (titre_film);


-- TABLE DE FAIT

DROP TABLE IF EXISTS fact_paiement CASCADE;
CREATE TABLE fact_paiement (
  fact_key bigserial PRIMARY KEY,
  source_paiement_id integer UNIQUE NOT NULL,

  -- Clés étrangères vers dimensions
  date_key integer NOT NULL REFERENCES dw.dim_date(date_key),
  magasin_key integer REFERENCES dim_magasin(magasin_key),
  client_key integer REFERENCES dim_client(client_key),
  film_key integer REFERENCES dim_film(film_key),
  categorie_key integer REFERENCES dim_categorie(categorie_key),

  -- Mesures
  montant numeric(12,2) NOT NULL CHECK (montant >= 0)
);

COMMENT ON TABLE fact_paiement IS 'Table de fait des paiements (grain = un paiement).';
COMMENT ON COLUMN fact_paiement.montant IS 'Montant du paiement (monétaire).';

-- Index de navigation usuels
CREATE INDEX IF NOT EXISTS idx_fact_paiement_date ON fact_paiement (date_key);
CREATE INDEX IF NOT EXISTS idx_fact_paiement_mag ON fact_paiement (magasin_key);
CREATE INDEX IF NOT EXISTS idx_fact_paiement_client ON fact_paiement (client_key);
CREATE INDEX IF NOT EXISTS idx_fact_paiement_film ON fact_paiement (film_key);
CREATE INDEX IF NOT EXISTS idx_fact_paiement_cat ON fact_paiement (categorie_key);

-- Index composites utiles pour les agrégations fréquentes
CREATE INDEX IF NOT EXISTS idx_fact_mag_date ON fact_paiement (magasin_key, date_key);
CREATE INDEX IF NOT EXISTS idx_fact_cat_date ON fact_paiement (categorie_key, date_key);

-- (Très gros volumes) : activer un BRIN sur la date pour range scans rapides
-- CREATE INDEX IF NOT EXISTS brin_fact_date ON dw.fact_paiement USING BRIN (date_key);

COMMIT;
