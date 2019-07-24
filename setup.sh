#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Missing arguments, exiting"
    echo "For help do: ./setup.sh --guide"
    exit 1
fi

_guide="\

    ntk - need to know
    ------------------

    To set up the DB schema do the following:

    export SUPERUSER=db-super-user-name
    export DBOWNER=db-owner-user-name
    export DBNAME=db-name
    export DBHOST=db-host-name
    export KEEP_TEST_DATA=true

    Create a .pgpass file so you can connect to the DB.

    ./setup.sh OPTIONS

    Options
    -------
    --setup     Create the DB schema.
    --test      Run SQL tests to ensure the DB schema works.
    --guide     Print this guide

"

setup() {
    psql -h $DBHOST -U $SUPERUSER -d $DBNAME -c "create extension pgcrypto"
    psql -h $DBHOST -U $DBOWNER -d $DBNAME -f ./src/db.sql
    echo 'setup complete'
}

sqltest() {
    psql -h $DBHOST -U $DBOWNER -d $DBNAME -1 -f ./tests.sql
}

while (( "$#" )); do
    case $1 in
        --setup)           shift; setup; exit 0 ;;
        --test)            shift; sqltest; exit 0 ;;
        --guide)           printf "%s\n" "$_guide"; exit 0 ;;
        *) break ;;
    esac
done
