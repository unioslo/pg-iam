#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Missing arguments, exiting"
    echo "For help do: ./setup.sh --guide"
    exit 1
fi

_guide="\

    pg-idp
    ------

    By default, running tests will not work if any of the pg-idp tables
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
    --del-existing-data     Delete any data found in the pg-idp tables before running tests.
    --keep-test-data        Do not delete test data.
    --setup                 Create the DB schema.
    --test                  Run SQL tests to ensure the DB schema works.
    --guide                 Print this guide

    Example
    -------

    ./setup.sh --setup
    ./setup.sh --keep-test-data --test
    # do some interactive work in the DB, and then remove the data
    ./setup.sh --del-existing-data --test

"

setup() {
    psql -h $DBHOST -U $SUPERUSER -d $DBNAME -c "create extension pgcrypto"
    psql -h $DBHOST -U $DBOWNER -d $DBNAME -f ./db.sql
    echo 'setup complete'
}

sqltest() {
    psql -h $DBHOST -U $DBOWNER -d $DBNAME -1 -f ./tests.sql
}

DELETE_EXISTING_DATA=false
KEEP_TEST_DATA=false

while (( "$#" )); do
    case $1 in
        --del-existing-data)    shift; DELETE_EXISTING_DATA=true ;;
        --keep-test-data)       shift; KEEP_TEST_DATA=true ;;
        --setup)                shift; setup; exit 0 ;;
        --test)                 shift; sqltest; exit 0 ;;
        --guide)                printf "%s\n" "$_guide"; exit 0 ;;
        *) break ;;
    esac
done
