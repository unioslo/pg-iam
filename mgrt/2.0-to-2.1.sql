/*
Migration:
- date -> timestamp in functions
- project_name -> mutable, non-unique

export SUPERUSER=
export DBOWNER=
export DBNAME=
export DBHOST=

./install.sh --only-replace-functions --setup
# saying yes to all

psql -U $DBOWNER -h $BHOST -d $DBNAME -f mgrt/1.5-to-2.1.sql

*/

alter table projects drop constraint projects_project_name_key;
