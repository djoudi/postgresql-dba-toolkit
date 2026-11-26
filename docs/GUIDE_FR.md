# Guide d'exploitation — PostgreSQL DBA Toolkit
## 1. Périmètre
Administration locale des clusters Debian/Ubuntu. Le menu permet le diagnostic système, la création et le pilotage des clusters, la création de bases, la gestion élémentaire des rôles, l'audit de configuration et HBA, l'analyse des statistiques et blocages, VACUUM ciblé, sauvegarde logique, restauration et planification. Les commandes administratives utilisent le compte système postgres. Réserver l'accès aux DBA autorisés.

## 2. Préparation
Installer PostgreSQL et postgresql-common selon la procédure officielle adaptée à la distribution. Vérifier `pg_lsclusters`, `sudo -u postgres psql -d postgres` et l'espace disque. Faire un instantané de la VM de test. Installer le script selon README. Le menu affiche les clusters avant sélection. Vérifier systématiquement la version, le nom et le port.

## 3. Administration
Option 1 : inventaire OS, noyau, RAM, disques et clusters. Option 2 : créer un cluster avec port libre choisi par pg_createcluster, ou gérer son service. Stop et restart interrompent les connexions ; prévoir une fenêtre de maintenance. Option 3 : créer une base. Aucun effacement de cluster ou base n'est proposé.

## 4. Sécurité
Option 4 : créer un rôle LOGIN sans privilèges administratifs, définir son mot de passe via la commande interactive psql ou accorder la lecture des tables existantes d'un schéma. Ce dernier octroi ne garantit pas une identité exclusivement en lecture : contrôler les appartenances, PUBLIC, les droits préexistants et les futures tables. Option 5 : examiner les paramètres, erreurs de configuration et règles HBA. Option 6 : inventaire des rôles et ACL. Le script ne modifie pas HBA, TLS ni les paramètres de production automatiquement. Les audits peuvent contenir des informations sensibles.

## 5. Performance
Option 7 : statistiques cumulatives, tuples morts estimés, utilisation des index, sessions et bloqueurs. Une faible utilisation d'index ne justifie pas sa suppression. Les compteurs peuvent avoir été réinitialisés. Option 8 : VACUUM ANALYZE sur une table choisie ; vérifier la charge et les transactions longues. Autovacuum reste le mécanisme principal. Pour un plan, utiliser EXPLAIN (ANALYZE, BUFFERS) sur une requête SELECT contrôlée ; ANALYZE exécute réellement la requête.

## 6. Sauvegarde et restauration
Créer un répertoire privé 0700 appartenant à l'opérateur. Option 9 ou commande backup du README : dump logique custom, verrou local, fichier temporaire, vérification du catalogue, publication de l'archive et empreinte SHA-256. Le checksum n'est pas une signature ni une preuve de restauration. Une archive sans empreinte doit être examinée. Conserver une copie hors serveur et contrôler l'espace disponible. Les rôles globaux, tablespaces et PITR ne sont pas couverts ; prévoir une stratégie distincte. Option 10 : sélectionner une archive de confiance et son empreinte, créer une nouvelle base, restaurer sans propriétaires ni ACL d'origine. En cas d'échec, la base cible est conservée pour diagnostic. Comparer ensuite les volumes, contraintes, données métier et droits nécessaires. Ne jamais restaurer une archive non fiable avec un superutilisateur.

## 7. Automatisation
Installer le script sous /usr/local/sbin/pg-dba-toolkit, propriété root. Créer le répertoire de sauvegarde privé root. Lancer le menu avec sudo, option 11, sélectionner le cluster et la base. Le timer quotidien à 02:00 heure locale est persistant. Consulter `systemctl list-timers --all` et `journalctl -u pg-dba-backup-18-main-ma_base.service`. Pour désactiver : `sudo systemctl disable --now pg-dba-backup-18-main-ma_base.timer`. Adapter les noms. La rétention et la copie hors site sont manuelles ; surveiller la capacité. Définir RPO/RTO et tester les restaurations régulièrement.

## 8. Dépannage et validation
Connexion refusée : vérifier cluster, port, socket et HBA. Permission refusée : vérifier sudo, propriétaire et mode du répertoire. Archive invalide : ne pas restaurer ; contrôler l'empreinte et les journaux. Option 12 : journaux systemd du cluster. Tester sur chaque OS cible : création d'un cluster de test, rôle et base, sauvegarde, restauration dans une nouvelle base, comparaison des données, exécution du timer, arrêt du timer. Vérifier les cas négatifs (nom invalide, base inexistante, archive corrompue, répertoire non privé). Aucun test d'intégration sur serveur réel n'a été réalisé pour cette livraison.

## 9. Références
https://www.postgresql.org/docs/18/admin.html
https://www.postgresql.org/docs/18/backup.html
https://www.postgresql.org/docs/18/monitoring.html
https://manpages.debian.org/pg_lsclusters
