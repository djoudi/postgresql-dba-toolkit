#!/usr/bin/env bash
# Gestion locale PostgreSQL sur Ubuntu / Debian. Aucun mot de passe stocké.
set -Eeuo pipefail
umask 077
export LC_ALL=C
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE PGCLUSTER PGOPTIONS PGPASSWORD PGSSLMODE
VERSION=1.0.0
fail(){ printf 'Erreur : %s\n' "$*" >&2; return 1; }
confirm(){ local r; read -rp "$1 [oui/N] : " r; [[ $r == oui ]]; }
need(){ command -v "$1" >/dev/null || fail "Commande absente : $1"; }
ident(){ [[ $1 =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]] || fail 'Identifiant simple requis (63 caractères maximum).'; }
admin(){ if [[ $(id -un) == postgres ]]; then "$@"; else sudo -u postgres -- "$@"; fi; }
rootcmd(){ if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi; }
run(){ printf 'Commande :'; printf ' %q' "$@"; printf '\n'; "$@"; }
select_cluster(){
  need pg_lsclusters; pg_lsclusters
  read -rp 'Version : ' V; read -rp 'Cluster : ' C
  bind_cluster "$V" "$C"
}
bind_cluster(){
  V=$1 C=$2
  [[ $V =~ ^[0-9]+(\.[0-9]+)?$ && $C =~ ^[a-zA-Z0-9_-]+$ ]] || fail 'Cluster invalide' || return
  local row; row=$(pg_lsclusters -h | awk -v v="$V" -v c="$C" '$1==v && $2==c {print $3, $4}')
  read -r P STATUS <<< "$row"
  [[ ${P:-} =~ ^[0-9]+$ ]] || fail 'Cluster introuvable' || return
  BIN=/usr/lib/postgresql/$V/bin
  [[ -x $BIN/psql ]] || fail 'Client correspondant absent' || return
}
pg(){ admin "$BIN/psql" -X -w -h /var/run/postgresql -p "$P" -U postgres -v ON_ERROR_STOP=1 "$@"; }
sql(){ pg -d "$DB" -c "$1"; }
choose_db(){ read -rp 'Base de données : ' DB; ident "$DB"; }
check(){ pg -d postgres -Atc 'SELECT version()'; }
info(){ cat /etc/os-release; uname -r; free -h; df -h; pg_lsclusters; }
cluster_menu(){
  local a n
  read -rp 'Action (start/stop/restart/reload/status/create) : ' a
  if [[ $a == create ]]; then
    read -rp 'Version installée : ' V; read -rp 'Nom du nouveau cluster : ' C; ident "$C" || return
    [[ $V =~ ^[0-9]+$ && -x /usr/lib/postgresql/$V/bin/initdb ]] || return 1
    confirm "Créer $V/$C avec un port libre choisi par Ubuntu" && run rootcmd pg_createcluster "$V" "$C" --start
  else
    case $a in start|stop|restart|reload|status) ;; *) return 1;; esac
    select_cluster || return
    if [[ $a == status ]] || confirm "$a $V/$C"; then run rootcmd pg_ctlcluster "$V" "$C" "$a"; fi
  fi
}
roles(){ local r s a; read -rp 'Rôle : ' r; ident "$r" || return
  read -rp 'Action (create/password/reader) : ' a
  case $a in
    create) confirm "Créer LOGIN $r sans mot de passe" && sql "CREATE ROLE \"$r\" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE";;
    password) pg -d "$DB" -c "\\password $r";;
    reader) read -rp 'Schéma : ' s; ident "$s" || return
      confirm "Accorder lecture sur les tables existantes de $s à $r" && sql "BEGIN; GRANT CONNECT ON DATABASE \"$DB\" TO \"$r\"; GRANT USAGE ON SCHEMA \"$s\" TO \"$r\"; GRANT SELECT ON ALL TABLES IN SCHEMA \"$s\" TO \"$r\"; COMMIT;";;
    *) return 1;;
  esac
}
config_audit(){ sql "SELECT name,setting,unit,context,source,pending_restart FROM pg_settings WHERE name IN ('listen_addresses','port','ssl','password_encryption','shared_buffers','work_mem','max_connections','log_min_duration_statement','autovacuum','fsync','synchronous_commit','full_page_writes','wal_level');"; sql 'SELECT sourcefile,sourceline,name,error FROM pg_file_settings WHERE error IS NOT NULL;'; sql 'SELECT line_number,type,database,user_name,address,auth_method,error FROM pg_hba_file_rules;'; }
security(){ sql 'SELECT rolname,rolsuper,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication FROM pg_roles ORDER BY rolname;'; sql 'SELECT datname,datacl FROM pg_database;'; sql 'SELECT nspname,nspacl FROM pg_namespace WHERE nspname NOT LIKE '\''pg_%'\'';'; config_audit; }
performance(){ sql 'SELECT datname,numbackends,xact_commit,xact_rollback,blks_read,blks_hit,deadlocks,temp_bytes FROM pg_stat_database;'; sql 'SELECT schemaname,relname,n_live_tup,n_dead_tup,last_autovacuum,last_autoanalyze FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 30;'; sql 'SELECT schemaname,relname,indexrelname,idx_scan,pg_size_pretty(pg_relation_size(indexrelid)) AS taille FROM pg_stat_user_indexes ORDER BY idx_scan LIMIT 30;'; sql 'SELECT pid,usename,state,wait_event_type,wait_event,now()-xact_start AS duree,pg_blocking_pids(pid) AS bloqueurs FROM pg_stat_activity WHERE datname=current_database();'; }
maintenance(){ local s t; read -rp 'Schéma : ' s; read -rp 'Table : ' t; ident "$s" && ident "$t" || return; confirm "VACUUM ANALYZE $s.$t" && sql "VACUUM (ANALYZE) \"$s\".\"$t\""; }
# Sauvegarde logique atomique, verrou local, contrôle du catalogue et empreinte.
backup(){
  local dest=$1 tmp out
  [[ -d $dest && -w $dest ]] || fail 'Répertoire de sauvegarde absent ou non accessible' || return
  [[ $(stat -c %u "$dest") == "$EUID" && $(stat -c %a "$dest") == 700 ]] || fail 'Répertoire privé (700), appartenant à l’opérateur requis' || return
  (
    flock -n 9 || exit 1
    tmp=$(mktemp "$dest/.dump.XXXXXXXX") || exit 1
    trap 'rm -f -- "$tmp"' EXIT
    out="$dest/${V}_${C}_${DB}_$(date -u +%Y%m%dT%H%M%SZ)_${tmp##*.}.dump"
    admin "$BIN/pg_dump" -w -h /var/run/postgresql -p "$P" -U postgres -Fc --dbname="$DB" > "$tmp" || exit 1
    "$BIN/pg_restore" -l "$tmp" >/dev/null || exit 1
    mv -- "$tmp" "$out" || exit 1
    (cd "$dest" && sha256sum "${out##*/}" > "${out##*/}.sha256") || exit 1
    printf 'Archive : %s\n' "$out"
  ) 9>"$dest/.backup.lock"
}
restore(){ local f target dir base expected actual
  read -rp 'Archive locale (.dump) : ' f; [[ -f $f && -f $f.sha256 ]] || return 1
  dir=$(dirname -- "$f"); base=$(basename -- "$f")
  read -r expected _ < "$f.sha256"; actual=$(sha256sum < "$f"); actual=${actual%% *}
  [[ $expected == "$actual" ]] || fail 'Empreinte incorrecte' || return
  "$BIN/pg_restore" -l "$f" || return
  read -rp 'Nouvelle base de restauration : ' target; ident "$target" || return
  confirm "Restaurer une archive de confiance dans $target (nouvelle base uniquement)" || return 0
  admin "$BIN/createdb" -w -h /var/run/postgresql -p "$P" -U postgres -T template0 -- "$target" || return
  if admin "$BIN/pg_restore" -w -h /var/run/postgresql -p "$P" -U postgres --exit-on-error --single-transaction --no-owner --no-privileges -d "$target" < "$f"; then
    pg -d "$target" -c 'SELECT schemaname,count(*) FROM pg_tables GROUP BY schemaname;'
  else fail "Restauration échouée : base $target conservée pour diagnostic"; fi
}
# Planification persistante : chemin fixe installé, exécution sous root, sans secret.
schedule(){ local dest script unit
  [[ $EUID == 0 ]] || fail 'Exécuter cette option avec sudo' || return
  script=$(realpath "$0"); [[ $script == /usr/local/sbin/pg-dba-toolkit ]] || fail 'Installer le script dans /usr/local/sbin/pg-dba-toolkit' || return
  read -rp 'Répertoire privé absolu (sans espaces) : ' dest
  [[ $dest =~ ^/[a-zA-Z0-9_./-]+$ && -d $dest && $(stat -c %u "$dest") == 0 && $(stat -c %a "$dest") == 700 ]] || return 1
  unit="pg-dba-backup-${V}-${C}-${DB}"
  confirm "Installer le timer quotidien $unit à 02:00" || return 0
  cat > "/etc/systemd/system/$unit.service" <<UNIT
[Unit]
Description=Sauvegarde PostgreSQL $V/$C $DB
[Service]
Type=oneshot
UMask=0077
ExecStart=$script backup $V $C $DB $dest
UNIT
  cat > "/etc/systemd/system/$unit.timer" <<UNIT
[Unit]
Description=Planification de $unit
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
[Install]
WantedBy=timers.target
UNIT
  systemctl daemon-reload && systemctl enable --now "$unit.timer"
}
menu(){ local a dest n
  while true; do
    printf '\nPOSTGRESQL DBA TOOLKIT PREMIUM %s\n1 Diagnostic système\n2 Gestion des clusters\n3 Créer une base\n4 Rôles et privilèges\n5 Audit configuration/HBA\n6 Audit sécurité\n7 Performance et verrous\n8 Maintenance ciblée\n9 Sauvegarde\n10 Restauration\n11 Planification quotidienne\n12 Journaux\n0 Quitter\n' "$VERSION"
    read -rp 'Choix : ' a || return 0
    case $a in 0) return;; 1) info; continue;; 2) cluster_menu || echo 'Action annulée ou échouée.'; continue;; esac
    [[ $a =~ ^([3-9]|1[012])$ ]] || continue
    select_cluster || continue
    if [[ $a == 12 ]]; then rootcmd journalctl -u "postgresql@$V-$C.service" -n 80 --no-pager; continue; fi
    check || continue
    if [[ $a == 3 ]]; then read -rp 'Nouvelle base : ' n; ident "$n" && confirm "Créer $n" && admin "$BIN/createdb" -w -h /var/run/postgresql -p "$P" -U postgres -- "$n"; continue; fi
    choose_db || continue
    case $a in 4) roles;; 5) config_audit;; 6) security;; 7) performance;; 8) maintenance;; 9) read -rp 'Répertoire privé existant : ' dest; backup "$dest";; 10) restore;; 11) schedule;; esac || echo 'Action annulée ou échouée.'
  done
}
case ${1:-interactive} in
  --help|-h) echo 'Usage : pg-dba-toolkit [interactive|backup VERSION CLUSTER BASE REPERTOIRE|--version]';;
  --version) echo "$VERSION";;
  backup) [[ $# == 5 ]] || exit 2; bind_cluster "$2" "$3"; DB=$4; ident "$DB"; backup "$5";;
  interactive) menu;;
  *) exit 2;;
esac
