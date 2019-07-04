
-- A generic DB backend for IDPs
-- with support for capability based authorization management

-- a possible public SQL API
-- /rpc/person_create
-- /rpc/person_describe
-- /rpc/person_get
-- /rpc/person_set
-- /rpc/person_groups

-- /rpc/user_create
-- /rpc/user_describe
-- /rpc/user_get
-- /rpc/user_set
-- /rpc/user_groups

-- /rpc/group_create
-- /rpc/group_describe
-- /rpc/group_member_add
-- /rpc/group_member_remove
-- /rpc/group_list
-- /rpc/group_list_all
-- /rpc/group_moderator_add
-- /rpc/group_moderatr_remove


--create extension pgcrypto;

-- TODO: record created date?

drop table if exists persons cascade;
create table if not exists persons(
    person_id uuid unique not null default gen_random_uuid(),
    person_activated boolean not null default 't',
    person_expiry_date date,
    person_group text,
    given_names text not null,
    surname text not null,
    national_id_number text,
    passport_number text,
    password text,
    otp_secret text
);

create or replace function person_immutability()
    returns trigger as $$
    begin
        if OLD.person_id != NEW.person_id then
            raise exception using message = 'person_id is immutable';
        elsif OLD.person_group != NEW.person_group then
            raise exception using message = 'person_group is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_person_immutability before update on persons
    for each row execute procedure person_immutability();

create or replace function person_management()
    returns trigger as $$
    declare new_pid text;
    declare new_pgrp text;
    begin
        if (TG_OP = 'INSERT') then
            if OLD.person_group is null then
                new_pgrp := NEW.person_id || '-group';
                update persons set person_group = new_pgrp where person_id = NEW.person_id;
                insert into groups (group_name, group_class, group_type, group_primary_member, group_desciption)
                    values (new_pgrp, 'primary', 'person', NEW.person_id, 'personal group');
            end if;
        elsif (TG_OP = 'DELETE') then
            delete from groups where group_name = OLD.person_group;
        elsif (TG_OP = 'UPDATE') then
            if OLD.person_activated != NEW.person_activated then
                update users set user_activated = NEW.person_activated where person_id = OLD.person_id;
                update groups set group_activated = NEW.person_activated where group_name = OLD.person_group;
            end if;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger person_group_trigger after insert or delete or update on persons
    for each row execute procedure person_management();
-- ensure end_dates consistent across person, users, groups



drop table if exists users cascade;
create table if not exists users(
    person_id uuid not null references persons (person_id) on delete cascade,
    user_id uuid unique not null default gen_random_uuid(),
    user_activated boolean not null default 't',
    user_expiry_date date,
    user_name text unique not null,
    user_group text
    -- other info
);
-- make fields immutable: user_id, user_name, user_group
-- before update if field not null and new != old exception

create or replace function user_management()
    returns trigger as $$
    declare new_unam text;
    declare new_ugrp text;
    begin
        if (TG_OP = 'INSERT') then
            if OLD.user_group is null then
                new_ugrp := NEW.user_name || '-group';
                update users set user_group = new_ugrp where user_name = NEW.user_name;
                insert into groups (group_name, group_class, group_type, group_primary_member, group_desciption)
                    values (new_ugrp, 'primary', 'user', NEW.user_name, 'user group');
            end if;
        elsif (TG_OP = 'DELETE') then
            delete from groups where group_name = OLD.user_group;
        elsif (TG_OP = 'UPDATE') then
            if OLD.user_activated != NEW.user_activated then
                update groups set group_activated = NEW.user_activated where group_name = OLD.user_group;
            end if;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger user_group_trigger after insert or delete or update on users
    for each row execute procedure user_management();

drop table if exists groups cascade;
create table if not exists groups(
    group_id uuid unique not null default gen_random_uuid(),
    group_activated boolean not null default 't',
    group_expiry_date date,
    group_name text unique not null,
    group_class text check (group_class in ('primary', 'secondary')),
    group_type text check (group_type in ('person', 'user', 'generic')),
    group_primary_member text,
    group_desciption text,
    group_metadata json
);
-- immutable: group_id, group_name, group_class, group_type, group_primary_member
-- before update if field not null and new != old exception

create or replace function group_state_management()
    returns trigger as $$
    declare primary_member_state boolean;
    begin
        if OLD.group_activated != NEW.group_activated then
            if OLD.group_type = 'person' then
                select person_activated from persons where person_group = OLD.group_name into primary_member_state;
                if NEW.group_activated != primary_member_state then
                    raise exception using message = 'person groups can only be deactived by deactivating persons';
                end if;
            elsif OLD.group_type = 'user' then
                select user_activated from users where user_group = OLD.group_name into primary_member_state;
                if NEW.group_activated != primary_member_state then
                    raise exception using message = 'user groups can only be deactived by deactivating users';
                end if;
            end if;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger group_activated_trigger before update on groups
    for each row execute procedure group_state_management();

drop table if exists group_memberships cascade;
create table if not exists group_memberships(
    group_name text not null references groups (group_name) on delete cascade,
    group_member_name text not null references groups (group_name) on delete cascade,
    group_membership_expiry_date date,
    unique (group_name, group_member_name) -- cannot be member of itself
);
-- assert group_class == secondary
-- TODO: add constraint to prevent cyclical graphs
-- group_new_parent_is_child_of_new_child
-- group_get_children

drop table if exists group_moderators cascade;
create table if not exists group_moderators(
    group_name text not null references groups (group_name) on delete cascade,
    group_moderator_name text not null references groups (group_name) on delete cascade,
    group_moderator_description text,
    group_moderator_metadata json,
    group_moderator_expiry_date date
);
-- TODO: add constraint to prevent cyclical graphs
-- group_new_parent_is_child_of_new_child
-- group_get_children
-- group_get_parents

-- for generating capabilities
-- specify required groups to obtain a capability, set params
-- e.g. id, import, {role:import_user}, [import-group, member-group], wildcard, 60, data import, 2030-12-12
-- BUT: some groups are regex match, others must be exact
drop table if exists capabilities cascade;
create table if not exists capabilities(
    capability_id uuid unique not null default gen_random_uuid(),
    capability_type text unique not null,
    capability_default_claims json,
    capability_required_groups text[] not null,
    capability_group_match_method text not null check (capability_group_match_method in ('exact', 'wildcard')),
    capability_lifetime int not null check (capability_lifetime > 0), -- minutes
    capability_description text not null,
    capability_expiry_date date
);
-- ensure set-like uniqueness on required groups
-- via unique index and function: https://stackoverflow.com/questions/8443716/postgres-unique-constraint-for-array
-- before trigger to check that groups exists, depending on match type

-- specify capabilities authorization: sets of operations on sets of resources
-- example entries
-- id, import, PUT, /(.*)/files/stream
-- id, import, PUT, /(.*)/files/upload
-- id, import, GET, /(.*)/files/resumables
-- id, export, DELETE, /(.*)/files/export/(.*)
drop table if exists capability_grants;
create table capability_grants(
    capability_id uuid references capabilities (capability_id) on delete cascade,
    capability_type text references capabilities (capability_type),
    capability_http_method text not null check (capability_http_method in ('OPTIONS', 'HEAD', 'GET', 'PUT', 'POST', 'PATCH', 'DELETE')),
    capability_uri_pattern text not null -- string or regex referring to a set of resources
);

