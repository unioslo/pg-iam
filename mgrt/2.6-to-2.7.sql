/*
Migration:

export SUPERUSER=
export DBOWNER=
export DBNAME=
export DBHOST=

./install.sh --only-replace-functions --setup
# saying yes to all

psql -U $DBOWNER -h $DBHOST -d $DBNAME -f mgrt/2.6-to-2.7.sql

*/

alter table persons add column email_verified boolean default 'f';
alter table persons add column birth_date date;
alter table persons add column password_expiry timestamptz;
