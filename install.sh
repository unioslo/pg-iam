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
    export PGHOST=db-host-name

    Create a .pgpass file so you can connect to the DB.

    Options
    -------
    --force                     Force reinstallation regardless of existing DB state.
    --only-replace-functions    Ensure tables are not dropped when installing new function definitions.
    --del-existing-data         Delete any data found in the pg-iam tables before running tests.
    --keep-test-data            Do not delete test data.
    --setup                     Create the DB schema.
    --test                      Run SQL tests to ensure the DB schema works.
    --backup                    create a backup of current data in named schema.
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

    ./install.sh --backup mybackupschema

"

prompt_tables() {
    read -p "Do you want to (re)install the $1 tables and functions (thereby dropping data)? (y/n) > " ANS
    if [[ $ANS == "y" ]]; then
        exec_sql_file $2
    fi
}

prompt_functions() {
    read -p "Do you want to (re)install the $1 functions (no table data will be lost)? (y/n) > " ANS
    if [[ $ANS == "y" ]]; then
        exec_sql_file $2
    fi
}

prompt() {
    if [[ $DROP_TABLES == "true" ]]; then
        prompt_tables $1 $2
    else
        prompt_functions $1 $2
    fi
}

exec_sql_file() {
    psql -U $DBOWNER -d $DBNAME -1 -f $1
}

count_rows_in_table() {
    psql -U $DBOWNER -d $DBNAME -c "select count(*) from $1" -At
}

fresh_install() {
    exec_sql_file ./src/notifications.sql
    exec_sql_file ./src/audit.sql
    exec_sql_file ./src/identities.sql
    exec_sql_file ./src/capabilities.sql
    exec_sql_file ./src/organisations.sql
    exit 0
}

show_count() {
    echo "$1: " $(count_rows_in_table $1)
}

setup() {
    psql -U $SUPERUSER -d $DBNAME -c "create extension pgcrypto"

    if [[ $FORCE == "true" ]]; then fresh_install; fi

    exec_sql_file ./src/notifications.sql

    show_count "audit_log_objects"
    show_count "audit_log_relations"
    prompt "audit" ./src/audit.sql

    show_count "persons"
    show_count "users"
    show_count "groups"
    prompt "identities" ./src/identities.sql

    show_count "capabilities_http"
    show_count "capabilities_http_grants"
    prompt "capabilities" ./src/capabilities.sql

    show_count "institutions"
    show_count "projects"
    prompt "organisations" ./src/organisations.sql
}

sqltest() {
    exec_sql_file ./tests.sql
}

make_backup() {
    echo "backing up data to schema: $BU_SCHEMA"
    exec_sql_file ./src/backup.sql
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
        --backup)                   shift; export BU_SCHEMA=$1; make_backup; exit 0 ;;
        --setup)                    shift; setup; exit 0 ;;
        --test)                     shift; sqltest; exit 0 ;;
        --guide)                    printf "%s\n" "$_guide"; exit 0 ;;
        *) break ;;
    esac
done
