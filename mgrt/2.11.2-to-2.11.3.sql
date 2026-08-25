/*
Migration: 2.11.2 -> 2.11.3

This schema version adds advisory locks to POSIX ID assignments, and a
set_posix_uid trigger before inserts to the users table similar to the
set_posix_gid trigger that the groups table already had.
*/

-- Remove legacy default, UID assignment is handled by the set_posix_uid trigger
alter table users alter column user_posix_uid drop default;

-- Register new check constraint without validating existing rows first
alter table users add constraint users_user_posix_uid_check
    check (user_posix_uid > 999) not valid;

-- Validate existing rows match uid constraint
alter table users validate constraint users_user_posix_uid_check;
