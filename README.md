# FilmDB Data Warehouse & Power BI Dashboard

## Description
Ce projet est un **data warehouse construit avec PostgreSQL** basé sur la base de données filmdb, et enrichi avec un **dashboard interactif Power BI**.  
L’objectif est d’illustrer un processus complet de **Business Intelligence** :  
- Extraction et modélisation des données (ETL simplifié)  
- Création d’un schéma en étoile (faits & dimensions)  
- Écriture de requêtes SQL analytiques  
- Développement de mesures DAX et hiérarchies dans Power BI  
- Visualisation des indicateurs clés (KPI) et tendances  

---
````bash
## Structure du projet

Projet_filmdb/
├─ sql/
│  ├─ source_filmdb/
│  │  ├─ filmdb.sql  # Script de création du data warehouse
│  │  ├─ requetes_clees.sql Requêtes analytiques de la bdd initial
│  │  └─ schema-diagram.png
│  ├─ datawarehouse/
│  │  ├─ creation_datawarehouse.sql # Script de création du data warehouse
│  │  ├─ insertion_datawarehouse.sql # Scripts d'insertion de données
│  │  └─ requetes_clees.sql # Requêtes analytiques de la bdd data warehouse
│  └─ vues.sql
├─ powerbi/
│  ├─ filmdb_pwbi.pbix # Rapport Power BI interactif
│  └─ film_powerbi.pdf # Rapport pdf du projet
└─ README.md



---

## Installation & Utilisation
### 1️ Prérequis
- [PostgreSQL 15+](https://www.postgresql.org/)  
- [Power BI Desktop](https://powerbi.microsoft.com/)  
- Git installé (`git --version`)

### 2️ Cloner le dépôt
```bash
git clone https://github.com/Ibrahima-Bodian/FilmDB_Data_Warehouse_-_Power_BI_Dashboard.git
cd filmdb


---

## Contenu analytique

###  KPI clés
-  **Nombre** de magasins, clients, pays, villes  
-  **Chiffre d’affaires total**, **panier moyen**  
-  **Film, catégorie, client et magasin** les plus rentables  
-  **Année record** et **mois record** de chiffre d’affaires  

###  Graphiques principaux
- Tendance mensuelle du CA  
- Top catégories & films  
- Pareto 80/20  
- Nouveaux vs récurrents  
- Répartition géographique des clients  
- Comparaison entre magasins  

---

##  Rapport

Un rapport complet est fourni dans **`docs/rapport_projet.pdf`**.  
Il décrit :
- La **méthodologie** employée  
- Les **scripts SQL** et transformations  
- Les **choix de modélisation**  
- Les **indicateurs retenus**  
- Les **visualisations Power BI**  

---

##  Auteur

 Projet réalisé par **Ibrahima Bodian**  
 Étudiant en **Science des Données – IUT d’Aurillac**  


## Exemples de requêtes métiers

Quelques requêtes SQL utilisées dans l’analyse :

### Top 10 des films par chiffre d’affaires
```sql
SELECT f.titre, SUM(p.montant) AS total_ca
FROM paiement p
JOIN location l ON p.location_id = l.location_id
JOIN inventaire i ON l.inventaire_id = i.inventaire_id
JOIN film f ON i.film_id = f.film_id
GROUP BY f.titre
ORDER BY total_ca DESC
LIMIT 10;


### Catégorie la plus rentable 
SELECT c.nom AS categorie, SUM(p.montant) AS total_ca
FROM paiement p
JOIN location l ON p.location_id = l.location_id
JOIN inventaire i ON l.inventaire_id = i.inventaire_id
JOIN film f ON i.film_id = f.film_id
JOIN film_categorie fc ON f.film_id = fc.film_id
JOIN categorie c ON fc.categorie_id = c.categorie_id
GROUP BY c.nom
ORDER BY total_ca DESC
LIMIT 1;


### Meilleur client (CA généré)
SELECT c.nom, c.prenom, SUM(p.montant) AS total_ca
FROM paiement p
JOIN location l ON p.location_id = l.location_id
JOIN client c ON l.client_id = c.client_id
GROUP BY c.nom, c.prenom
ORDER BY total_ca DESC
LIMIT 1;



### Chiffre d’affaires mensuel
SELECT DATE_TRUNC('month', p.date_paiement) AS mois, 
       SUM(p.montant) AS total_ca
FROM paiement p
GROUP BY mois
ORDER BY mois;

