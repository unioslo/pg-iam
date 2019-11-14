#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Missing arguments, exiting"
    echo "For help do: ./install.sh --guide"
    exit 1
fi

_guide="\

    pg-iam
    ------

    By default, running tests will not work if any of the pg-iam tables
    have data in them. You can remove existing data by using the --del-existing-data
    flag. Similarly, any data created by tests will be removed by default. This too
    can be overridden, with the --keep-test-data flag.

    To set up the DB schema do the following:

    export SUPERUSER=db-super-user-name
    export DBOWNER=db-owner-user-name
    export DBNAME=db-name
    export DBHOST=db-host-name

    Create a .pgpass file so you can connect to the DB.

    Options
    -------
    --force                     Force reinstallation regardless of existing DB state.
    --only-replace-functions    Ensure tables are not dropped when installing new function definitions.
    --del-existing-data         Delete any data found in the pg-iam tables before running tests.
    --keep-test-data            Do not delete test data.
    --setup                     Create the DB schema.
    --test                      Run SQL tests to ensure the DB schema works.
    --guide                     Print this guide

    Examples
    --------

    # basic
    ./install.sh --setup # and follow interactive steps
    ./install.sh --test

    # fine tune what happens to test data
    ./install.sh --keep-test-data --test
    ./install.sh --del-existing-data --test

    # only update function definitions
    ./install.sh --only-replace-functions --setup

"

setup() {
    psql -h $DBHOST -U $SUPERUSER -d $DBNAME -c "create extension pgcrypto"
    if [[ $FORCE == "true" ]]; then
        psql -h $DBHOST -U $DBOWNER -d $DBNAME -1 -f ./db_identities_groups.sql
        psql -h $DBHOST -U $DBOWNER -d $DBNAME -1 -f ./db_capabilities.sql
        exit
    fi
    num_persons=$(psql -h $DBHOST -U $SUPERUSER -d $DBNAME -c "select count(*) from persons" -At)
    num_users=$(psql -h $DBHOST -U $SUPERUSER -d $DBNAME -c "select count(*) from users" -At)
    num_groups=$(psql -h $DBHOST -U $SUPERUSER -d $DBNAME -c "select count(*) from groups" -At)
    echo "Persons: $num_persons"
    echo "Users: $num_users"
    echo "Groups: $num_groups"
    if [[ $DROP_TABLES == "true" ]]; then
        read -p 'Do you want to (re)install the persons, users, and groups tables and functions (thereby dropping data)? (y/n) > ' ANS
    else
        read -p 'Do you want to (re)install the persons, users, and groups functions (no table data will be lost)? (y/n) > ' ANS
    fi
    if [[ $ANS == "y" ]]; then
        psql -h $DBHOST -U $DBOWNER -d $DBNAME -1 -f ./db_identities_groups.sql
    fi
    num_caps=$(psql -h $DBHOST -U $SUPERUSER -d $DBNAME -c "select count(*) from capabilities_http" -At)
    num_grants=$(psql -h $DBHOST -U $SUPERUSER -d $DBNAME -c "select count(*) from capabilities_http_grants" -At)
    echo "Capabilities: $num_caps"
    echo "Grants: $num_grants"
    read -p 'Do you want to (re)install the capabilities functionality (thereby dropping existing data)? (y/n) > ' ANS
    if [[ $ANS == "y" ]]; then
        psql -h $DBHOST -U $DBOWNER -d $DBNAME -1 -f ./db_capabilities.sql
    fi
}

sqltest() {
    psql -h $DBHOST -U $DBOWNER -d $DBNAME -1 -f ./tests.sql
}

export DELETE_EXISTING_DATA=false
export KEEP_TEST_DATA=false
export DROP_TABLES=true

FORCE=false


while (( "$#" )); do
    case $1 in
        --force)                    shift; FORCE=true ;;
        --only-replace-functions)   shift; export DROP_TABLES=false ;;
        --del-existing-data)        shift; export DELETE_EXISTING_DATA=true ;;
        --keep-test-data)           shift; export KEEP_TEST_DATA=true ;;
        --setup)                    shift; setup; exit 0 ;;
        --test)                     shift; sqltest; exit 0 ;;
        --guide)                    printf "%s\n" "$_guide"; exit 0 ;;
        *) break ;;
    esac
done
