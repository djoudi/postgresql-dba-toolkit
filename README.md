# PostgreSQL DBA Toolkit — Premium Edition
Version 1.0.0 | Bash | Administration locale Ubuntu/Debian

## Installation
Sur une machine de test avec PostgreSQL installé via postgresql-common, sudo, util-linux et coreutils :

```bash
bash -n pg-dba-toolkit.sh
sudo install -o root -g root -m 0755 pg-dba-toolkit.sh /usr/local/sbin/pg-dba-toolkit
sudo pg-dba-toolkit
```

Le script détecte les clusters via pg_lsclusters et utilise les binaires de leur version. Ubuntu 22.04, 24.04 et 26.04 sont des cibles, pas des plateformes certifiées. Socket local standard /var/run/postgresql et compte postgres avec authentification locale autorisée requis. Les noms simples ASCII sont imposés pour les bases et rôles. Aucun mot de passe enregistré.

## Sauvegarde non interactive
```bash
sudo install -d -m 0700 -o root -g root /var/backups/pg-toolkit
sudo pg-dba-toolkit backup 18 main ma_base /var/backups/pg-toolkit
```

Adapter version, cluster et base. Voir docs/GUIDE_FR.md pour les procédures et limites. Ne pas exécuter une copie modifiable par un utilisateur non fiable sous root.
