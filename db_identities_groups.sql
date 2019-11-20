
create schema if not exists pgiam;

\set drop_table_flag `echo "$DROP_TABLES"`
create or replace function drop_tables(drop_table_flag boolean default 'true')
    returns boolean as $$
    declare ans boolean;
    begin
        if drop_table_flag = 'true' then
            raise notice 'DROPPING IDENTITIES AND GROUPS TABLES';
            drop table if exists audit_log_objects cascade;
            drop table if exists audit_log_relations cascade;
            drop table if exists persons cascade;
            drop table if exists users cascade;
            drop table if exists groups cascade;
            drop table if exists group_memberships cascade;
            drop table if exists group_moderators cascade;
        else
            raise notice 'NOT dropping tables - only functions will be replaced';
        end if;
    return true;
    end;
$$ language plpgsql;
select drop_tables(:drop_table_flag);


create table if not exists audit_log_objects(
    identity text default null,
    operation text not null,
    event_time timestamptz default now(),
    table_name text not null,
    row_id uuid not null,
    column_name text,
    old_data text,
    new_data text
) partition by list (table_name);
create table if not exists audit_log_objects_persons
    partition of audit_log_objects for values in ('persons');
create table if not exists audit_log_objects_users
    partition of audit_log_objects for values in ('users');
create table if not exists audit_log_objects_groups
    partition of audit_log_objects for values in ('groups');
create table if not exists audit_log_objects_capabilities_http
    partition of audit_log_objects for values in ('capabilities_http');


create table if not exists audit_log_relations(
    identity text default null,
    operation text not null,
    event_time timestamptz default now(),
    table_name text not null,
    parent text,
    child text
) partition by list (table_name);
create table if not exists audit_log_relations_group_memberships
    partition of audit_log_relations for values in ('group_memberships');
create table if not exists audit_log_relations_group_moderators
    partition of audit_log_relations for values in ('group_moderators');
create table if not exists audit_log_relations_capabilities_http_grants
    partition of audit_log_relations for values in ('capabilities_http_grants');


drop function if exists update_audit_log_objects() cascade;
create or replace function update_audit_log_objects()
    returns trigger as $$
    declare old_data text;
    declare new_data text;
    declare colname text;
    declare table_name text;
    declare session_identity text;
    begin
        table_name := TG_TABLE_NAME::text;
        session_identity := current_setting('session.identity', 't');
        for colname in execute
            format('select c.column_name::text
                    from pg_catalog.pg_statio_all_tables as st
                    inner join information_schema.columns c
                    on c.table_schema = st.schemaname and c.table_name = st.relname
                    left join pg_catalog.pg_description pgd
                    on pgd.objoid = st.relid
                    and pgd.objsubid = c.ordinal_position
                    where st.relname = $1') using table_name
        loop
            execute format('select ($1).%s::text', colname) using OLD into old_data;
            execute format('select ($1).%s::text', colname) using NEW into new_data;
            if old_data != new_data or (old_data is null and new_data is not null) then
                insert into audit_log_objects (identity, operation, table_name, row_id, column_name, old_data, new_data)
                    values (session_identity, TG_OP, table_name, NEW.row_id, colname, old_data, new_data);
            end if;
        end loop;
        if TG_OP = 'DELETE' then
            insert into audit_log_objects (identity, operation, table_name, row_id, column_name, old_data, new_data)
                values (session_identity, TG_OP, table_name, OLD.row_id, null, null, null);
        end if;
        return new;
    end;
$$ language plpgsql;


drop function if exists update_audit_log_relations() cascade;
create or replace function update_audit_log_relations()
    returns trigger as $$
    declare table_name text;
    declare parent text;
    declare child text;
    declare session_identity text;
    begin
        session_identity := current_setting('session.identity', 't');
        table_name := TG_TABLE_NAME::text;
        if TG_OP in ('INSERT', 'UPDATE') then
            if table_name = 'group_memberships' then
                parent := NEW.group_name;
                child := NEW.group_member_name;
            elsif table_name = 'group_moderators' then
                parent := NEW.group_name;
                child := NEW.group_moderator_name;
            elsif table_name = 'capabilities_http_grants' then
                parent := NEW.capability_name;
                child := NEW.capability_grant_hostname || ','
                      || NEW.capability_grant_namespace || ','
                      || NEW.capability_grant_http_method || ','
                      || NEW.capability_grant_uri_pattern || ','
                      || quote_nullable(NEW.capability_grant_rank) || ','
                      || quote_nullable(NEW.capability_grant_required_groups);
            end if;
        elsif TG_OP = 'DELETE' then
            if table_name = 'group_memberships' then
                parent := OLD.group_name;
                child := OLD.group_member_name;
            elsif table_name = 'group_moderators' then
                parent := OLD.group_name;
                child := OLD.group_moderator_name;
            elsif table_name = 'capabilities_http_grants' then
                parent := OLD.capability_name;
                child := OLD.capability_grant_http_method || ',' || OLD.capability_grant_uri_pattern;
            end if;
        end if;
        insert into audit_log_relations(identity, operation, table_name, parent, child)
            values (session_identity, TG_OP, table_name, parent, child);
        return new;
    end;
$$ language plpgsql;


create table if not exists persons(
    row_id uuid unique not null default gen_random_uuid(),
    person_id uuid unique not null primary key default gen_random_uuid(),
    person_activated boolean not null default 't',
    person_expiry_date timestamptz,
    person_group text,
    full_name text not null,
    identifiers jsonb, -- e.g. [{k1: v1, k2: v2}, {...}]
    password text,
    otp_secret text,
    email text,
    person_metadata jsonb
);


create trigger persons_audit after update or insert or delete on persons
    for each row execute procedure update_audit_log_objects();


drop function if exists person_immutability() cascade;
create or replace function person_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise exception using message = 'row_id is immutable';
        elsif OLD.person_id != NEW.person_id then
            raise exception using message = 'person_id is immutable';
        elsif OLD.person_group != NEW.person_group then
            raise exception using message = 'person_group is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_person_immutability before update on persons
    for each row execute procedure person_immutability();


drop function if exists person_uniqueness() cascade;
create or replace function person_uniqueness()
    returns trigger as $$
    declare element jsonb;
    begin
        begin
            for element in select jsonb_array_elements(NEW.identifiers) loop
                if 't' in (select element <@ jsonb_array_elements(identifiers) from persons) then
                    raise integrity_constraint_violation
                        using message = 'value already contained in identifiers';
                end if;
            end loop;
        exception when invalid_parameter_value then
            raise exception
                using message = 'identifiers should be a json array, like [{k,v}, {...}]';
        end;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_person_uniqueness before insert on persons
    for each row execute procedure person_uniqueness();


drop function if exists person_management() cascade;
create or replace function person_management()
    returns trigger as $$
    declare new_pid text;
    declare new_pgrp text;
    declare exp date;
    declare unam text;
    begin
        if (TG_OP = 'INSERT') then
            if OLD.person_group is null then
                new_pgrp := NEW.person_id || '-group';
                update persons set person_group = new_pgrp where person_id = NEW.person_id;
                insert into groups (group_name, group_class, group_type, group_primary_member, group_description, group_expiry_date)
                    values (new_pgrp, 'primary', 'person', NEW.person_id, 'personal group', NEW.person_expiry_date);
            end if;
        elsif (TG_OP = 'DELETE') then
            delete from groups where group_name = OLD.person_group;
        elsif (TG_OP = 'UPDATE') then
            if OLD.person_activated != NEW.person_activated then
                update users set user_activated = NEW.person_activated where person_id = OLD.person_id;
                update groups set group_activated = NEW.person_activated where group_name = OLD.person_group;
            end if;
            if OLD.person_expiry_date != NEW.person_expiry_date then
                new_pgrp := NEW.person_id || '-group';
                update groups set group_expiry_date = NEW.person_expiry_date where group_name = new_pgrp;
                for exp, unam in select user_expiry_date, user_name from users where person_id = NEW.person_id loop
                    if NEW.person_expiry_date < exp then
                        update users set user_expiry_date = NEW.person_expiry_date where person_id = NEW.person_id;
                        update groups set group_expiry_date = NEW.person_expiry_date where group_primary_member = unam;
                    end if;
                end loop;
            end if;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger person_group_trigger after insert or delete or update on persons
    for each row execute procedure person_management();


-- cannot drop this since default value of column depends on it
-- so we always only replace it, unless all tables are dropped
-- in which case we will recreate the default value anyways
create or replace function generate_new_posix_id(table_name text, colum_name text)
    returns int as $$
    declare current_max_id int;
    declare new_id int;
    begin
        execute format('select max(%I) from %I',
            quote_ident(colum_name), quote_ident(table_name))
            into current_max_id;
        if current_max_id is null then
            new_id := 1000;
        elsif current_max_id >= 0 and current_max_id <= 999 then
            new_id := 1000;
        elsif current_max_id >= 200000 and current_max_id <= 220000 then
            new_id := 220001;
        else
            new_id := current_max_id + 1;
        end if;
        return new_id;
    end;
$$ language plpgsql;


-- cannot drop this since default value of column depends on it
-- so we always only replace it, unless all tables are dropped
-- in which case we will recreate the default value anyways
create or replace function generate_new_posix_uid()
    returns int as $$
    declare new_uid int;
    begin
        select generate_new_posix_id('users', 'user_posix_uid') into new_uid;
        return new_uid;
    end;
$$ language plpgsql;


create table if not exists users(
    row_id uuid unique not null default gen_random_uuid(),
    person_id uuid not null references persons (person_id) on delete cascade,
    user_id uuid unique not null default gen_random_uuid(),
    user_activated boolean not null default 't',
    user_expiry_date timestamptz,
    user_name text unique not null primary key,
    user_group text,
    user_posix_uid int unique
        check ((user_posix_uid > 999 and user_posix_uid < 200000) or user_posix_uid > 220000)
        default generate_new_posix_uid(), -- note: can still create holes
    user_group_posix_gid int
        check ((user_group_posix_gid > 999 and user_group_posix_gid < 200000) or user_group_posix_gid > 220000),
    user_metadata jsonb
);


create trigger users_audit after update or insert or delete on users
    for each row execute procedure update_audit_log_objects();


drop function if exists user_immutability() cascade;
create or replace function user_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise exception using message = 'row_id is immutable';
        elsif OLD.user_id != NEW.user_id then
            raise exception using message = 'user_id is immutable';
        elsif OLD.user_name != NEW.user_name then
            raise exception using message = 'user_name is immutable';
        elsif OLD.user_group != NEW.user_group then
            raise exception using message = 'user_group is immutable';
        elsif OLD.user_posix_uid != NEW.user_posix_uid then
            raise exception using message = 'user_posix_uid is immutable';
        elsif NEW.user_posix_uid is null and NEW.user_posix_uid is not null then
            raise exception using message = 'user_posix_uid cannot be set to null once set';
        elsif NEW.user_group_posix_gid is null and OLD.user_group_posix_gid is not null then
            raise exception using message = 'user_group_posix_gid cannot be set to null once set';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_user_immutability before update on users
    for each row execute procedure user_immutability();


drop function if exists user_management() cascade;
create or replace function user_management()
    returns trigger as $$
    declare new_unam text;
    declare new_ugrp text;
    declare person_exp date;
    declare user_exp date;
    declare ugroup_posix_gid int;
    begin
        if (TG_OP = 'INSERT') then
            if OLD.user_group is null then
                new_ugrp := NEW.user_name || '-group';
                update users set user_group = new_ugrp where user_name = NEW.user_name;
                -- if caller provides user_group_posix_gid then set it, otherwise don't
                if NEW.user_group_posix_gid is not null then
                    ugroup_posix_gid := NEW.user_group_posix_gid;
                else
                    ugroup_posix_gid := null;
                end if;
                insert into groups (group_name, group_class, group_type, group_primary_member, group_description, group_posix_gid)
                    values (new_ugrp, 'primary', 'user', NEW.user_name, 'user group', ugroup_posix_gid);
                select person_expiry_date from persons where person_id = NEW.person_id into person_exp;
                if NEW.user_expiry_date is not null then
                    if NEW.user_expiry_date > person_exp then
                        raise exception using message = 'a user cannot expire _after_ the person';
                    end if;
                    user_exp := NEW.user_expiry_date;
                else
                    user_exp := person_exp;
                end if;
                update users set user_expiry_date = user_exp where user_name = NEW.user_name;
                update groups set group_expiry_date = user_exp where group_name = new_ugrp;
            end if;
        elsif (TG_OP = 'DELETE') then
            delete from groups where group_name = OLD.user_group;
        elsif (TG_OP = 'UPDATE') then
            if OLD.user_activated != NEW.user_activated then
                update groups set group_activated = NEW.user_activated where group_name = OLD.user_group;
            end if;
            if OLD.user_expiry_date != NEW.user_expiry_date then
                select person_expiry_date from persons where person_id = NEW.person_id into person_exp;
                if NEW.user_expiry_date > person_exp then
                    raise exception using message = 'a user cannot expire _after_ the person';
                else
                    update groups set group_expiry_date = NEW.user_expiry_date where group_primary_member = NEW.user_name;
                end if;
            end if;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger user_group_trigger after insert or delete or update on users
    for each row execute procedure user_management();

-- cannot drop this since default value of column depends on it
-- so we always only replace it, unless all tables are dropped
-- in which case we will recreate the default value anyways
create or replace function generate_new_posix_gid()
    returns int as $$
    declare new_gid int;
    begin
        select generate_new_posix_id('groups', 'group_posix_gid') into new_gid;
        return new_gid;
    end;
$$ language plpgsql;


create table if not exists groups(
    row_id uuid unique not null default gen_random_uuid(),
    group_id uuid unique not null default gen_random_uuid(),
    group_activated boolean not null default 't',
    group_expiry_date timestamptz,
    group_name text unique not null primary key,
    group_class text check (group_class in ('primary', 'secondary')),
    group_type text check (group_type in ('person', 'user', 'generic', 'web')),
    group_primary_member text,
    group_description text,
    group_posix_gid int unique -- person groups do not have gids
        check ((group_posix_gid > 999 and group_posix_gid < 200000) or group_posix_gid > 220000),
    group_metadata jsonb
);


drop function if exists posix_gid() cascade;
create or replace function posix_gid()
    returns trigger as $$
    begin
        if NEW.group_type not in ('person', 'web') then
            if NEW.group_posix_gid is null then
                -- only auto select if nothing is provided
                -- to enable the transition historical data
                -- risk: possibility to generate holes
                select generate_new_posix_gid() into NEW.group_posix_gid;
            end if;
        else
            NEW.group_posix_gid := null;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger set_posix_gid before insert on groups
    for each row execute procedure posix_gid();


drop function if exists sync_posix_gid_to_users() cascade;
create or replace function sync_posix_gid_to_users()
    returns trigger as $$
    begin
        if NEW.group_type = 'user' then
            update users set user_group_posix_gid = NEW.group_posix_gid
                where user_group = NEW.group_name;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger sync_user_group_posix_gid after insert on groups
    for each row execute procedure sync_posix_gid_to_users();


create trigger groups_audit after update or insert or delete on groups
    for each row execute procedure update_audit_log_objects();


drop function if exists group_deletion() cascade;
create or replace function group_deletion()
    returns trigger as $$
    declare amount int;
    begin
        if OLD.group_type = 'person' then
            select count(*) from persons where person_group = OLD.group_name into amount;
            if amount = 1 then
                raise exception using
                message = 'person groups are automatically created and deleted based on person objects';
            end if;
        elsif OLD.group_type = 'user' then
            select count(*) from users where user_group = OLD.group_name into amount;
            if amount = 1 then
                raise exception using
                message = 'user groups are automatically created and deleted based on user objects';
            end if;
        end if;
    return old;
    end;
$$ language plpgsql;
create trigger ensure_group_deletion_policy before delete on groups
    for each row execute procedure group_deletion();


drop function if exists group_immutability() cascade;
create or replace function group_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise exception using message = 'row_id is immutable';
        elsif OLD.group_id != NEW.group_id then
            raise exception using message = 'group_id is immutable';
        elsif OLD.group_name != NEW.group_name then
            raise exception using message = 'group_name is immutable';
        elsif OLD.group_class != NEW.group_class then
            raise exception using message = 'group_class is immutable';
        elsif OLD.group_type != NEW.group_type then
            raise exception using message = 'group_type is immutable';
        elsif OLD.group_primary_member != NEW.group_primary_member then
            raise exception using message = 'group_primary_member is immutable';
        elsif OLD.group_posix_gid != NEW.group_posix_gid then
            raise exception using message = 'group_posix_gid is immutable';
        elsif NEW.group_posix_gid is null and OLD.group_posix_gid is not null then
            raise exception using message = 'group_posix_gid cannot be set to null once set';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_group_immutability before update on groups
    for each row execute procedure group_immutability();


drop function if exists group_management() cascade;
create or replace function group_management()
    returns trigger as $$
    declare primary_member_state boolean;
    declare curr_user_exp date;
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
        elsif OLD.group_expiry_date != NEW.group_expiry_date then
            select user_expiry_date from users where user_name = NEW.group_primary_member into curr_user_exp;
            if NEW.group_expiry_date != curr_user_exp then
                raise exception using message = 'primary group dates are modified via modifications on persons/users';
            end if;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger group_management_trigger before update on groups
    for each row execute procedure group_management();


create table if not exists group_memberships(
    group_name text not null references groups (group_name) on delete cascade,
    group_member_name text not null references groups (group_name) on delete cascade,
    unique (group_name, group_member_name)
);


create trigger group_memberships_audit after update or insert or delete on group_memberships
    for each row execute procedure update_audit_log_relations();


drop function if exists group_memberships_immutability() cascade;
create or replace function group_memberships_immutability()
    returns trigger as $$
    begin
        if OLD.group_name != NEW.group_name then
            raise exception using message = 'group_name is immutable';
        elsif OLD.group_member_name != NEW.group_member_name then
            raise exception using message = 'group_member_name is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_group_memberships_immutability before update on group_memberships
    for each row execute procedure group_memberships_immutability();


create or replace view pgiam.first_order_members as
    select gm.group_name, gm.group_member_name, g.group_class, g.group_type, g.group_primary_member
    from group_memberships gm, groups g
    where gm.group_member_name = g.group_name;


drop table if exists pgiam.members cascade; -- accounting table for temp data
create table if not exists pgiam.members(group_name text, group_member_name text, group_class text, group_primary_member text);
drop function if exists group_get_children(text) cascade;
create or replace function group_get_children(parent_group text)
    returns setof pgiam.members as $$
    declare num int;
    declare gn text;
    declare gmn text;
    declare gpm text;
    declare gc text;
    declare row record;
    declare current_member text;
    declare new_current_member text;
    declare recursive_current_member text;
    begin
        create temporary table if not exists sec(group_name text, group_member_name text, group_class text, group_primary_member text) on commit drop;
        create temporary table if not exists mem(group_name text, group_member_name text, group_class text, group_primary_member text) on commit drop;
        delete from sec;
        delete from mem;
        select count(*) from pgiam.first_order_members where group_name = parent_group
            and group_class = 'secondary' into num;
        if num = 0 then
            return query execute format ('select group_name, group_member_name, group_class, group_primary_member
                from pgiam.first_order_members where group_name = $1 order by group_primary_member') using parent_group;
        else
            for gn, gmn, gc, gpm in select group_name, group_member_name, group_class, group_primary_member
                from pgiam.first_order_members where group_name = parent_group
                and group_class = 'primary' loop
                insert into mem values (gn, gmn, gc, gpm);
            end loop;
            for gn, gmn, gc, gpm in select group_name, group_member_name, group_class, group_primary_member
                from pgiam.first_order_members where group_name = parent_group
                and group_class = 'secondary' loop
                insert into sec values (gn, gmn, gc, gpm);
            end loop;
            select count(*) from sec into num;
            while num > 0 loop
                select group_member_name from sec limit 1 into current_member;
                select group_name, group_member_name, group_class, group_primary_member
                    from sec where group_member_name = current_member
                    into gn, gmn, gc, gpm;
                if gc = 'primary' then
                    insert into mem values (gn, gmn, gc, gpm);
                elsif gc = 'secondary' then
                    insert into mem values (gn, gmn, gc, gpm);
                    new_current_member := gmn;
                    -- first add primary groups to members, and remove them from sec
                    for gn, gmn, gc, gpm in select group_name, group_member_name, group_class, group_primary_member
                        from pgiam.first_order_members where group_name = new_current_member loop
                        if gc = 'primary' then
                            insert into mem values (gn, gmn, gc, gpm);
                            delete from sec where group_member_name = gmn;
                        else
                            recursive_current_member := gmn;
                            insert into mem values (gn, gmn, gc, gpm);
                            -- this new secondary member can have both primary and seconday
                            -- members itself, but just add all its members to sec, and we will handle them
                            for gn, gmn, gc, gpm in select group_name, group_member_name, group_class, group_primary_member
                                from pgiam.first_order_members where group_name = recursive_current_member loop
                                insert into sec values (gn, gmn, gc, gpm);
                            end loop;
                        end if;
                    end loop;
                end if;
                delete from sec where group_member_name = current_member;
                select count(*) from sec into num;
            end loop;
            return query select * from mem order by group_primary_member;
        end if;
    end;
$$ language plpgsql;


drop table if exists pgiam.memberships cascade; -- accounting table for temp data
create table if not exists pgiam.memberships(member_name text, member_group_name text);
drop function if exists group_get_parents(text) cascade;
create or replace function group_get_parents(child_group text)
    returns setof pgiam.memberships as $$
    declare num int;
    declare mgn text;
    declare mn text;
    declare gn text;
    begin
        create temporary table if not exists candidates(member_name text, member_group_name text) on commit drop;
        create temporary table if not exists parents(member_name text, member_group_name text) on commit drop;
        delete from candidates;
        delete from parents;
        for gn in select group_name from pgiam.first_order_members where group_member_name = child_group loop
            insert into candidates values (child_group, gn);
        end loop;
        select count(*) from candidates into num;
        while num > 0 loop
            select member_name, member_group_name from candidates limit 1 into mn, mgn;
            insert into parents values (mn, mgn);
            delete from candidates where member_name = mn and member_group_name = mgn;
            -- now check if the current candidate has parents
            -- so we find all recursive memberships
            for gn in select group_name from pgiam.first_order_members where group_member_name = mgn loop
                insert into candidates values (mgn, gn);
            end loop;
            select count(*) from candidates into num;
        end loop;
        return query select * from parents;
    end;
$$ language plpgsql;


drop function if exists group_memberships_check_dag_requirements() cascade;
create or replace function group_memberships_check_dag_requirements()
    returns trigger as $$
    declare response text;
    begin
        -- Ensure we have only Directed Acylic Graphs, where primary groups are only allowed in leaves
        -- if a any of the groups are currently inactive or expired, the membership cannot be created
        -- also disallow any self-referential entries
        assert NEW.group_name != NEW.group_member_name, 'groups cannot be members of themselves';
        response := NEW.group_name || ' is a primary group - which cannot have members other than its primary member';
        assert (select NEW.group_name in
            (select group_name from groups where group_class = 'primary')) = 'f', response;
        assert (select group_activated from groups where group_name = NEW.group_name) = 't',
            NEW.group_name || ' is deactived - to use it in new group memberships it must be active';
        assert (select group_activated from groups where group_name = NEW.group_member_name) = 't',
            NEW.group_member_name || ' is deactived - to use it in new group memberships it must be active';
        assert (select case when group_expiry_date is not null then group_expiry_date else current_date end
                from groups where group_name = NEW.group_name) >= current_date,
            NEW.group_name || ' has expired - to use it in new group memberships its expiry date must be later than the current date';
        assert (select case when group_expiry_date is not null then group_expiry_date else current_date end
                from groups where group_name = NEW.group_member_name) >= current_date,
            NEW.group_member_name || ' has expired - to use it in new group memberships its expiry date must be later than the current date';
        response := 'Making ' || NEW.group_member_name || ' a member of ' || NEW.group_name
                    || ' would create a cyclical graph which is not allowed';
        assert (select NEW.group_member_name in
            (select member_group_name from group_get_parents(NEW.group_name))) = 'f', response;
        response := NEW.group_member_name || ' is already a member of ' || NEW.group_name;
        assert (select NEW.group_member_name in
            (select group_member_name from group_get_children(NEW.group_name))) = 'f', response;
        return new;
    end;
$$ language plpgsql;
create trigger group_memberships_dag_requirements_trigger before insert on group_memberships
    for each row execute procedure group_memberships_check_dag_requirements();


create table if not exists group_moderators(
    group_name text not null references groups (group_name) on delete cascade,
    group_moderator_name text not null references groups (group_name) on delete cascade,
    unique (group_name, group_moderator_name)
);


create trigger group_moderators_audit after update or insert or delete on group_moderators
    for each row execute procedure update_audit_log_relations();


drop function if exists group_moderators_immutability() cascade;
create or replace function group_moderators_immutability()
    returns trigger as $$
    begin
        if OLD.group_name != NEW.group_name then
            raise exception using message = 'group_name is immutable';
        elsif OLD.group_member_name != NEW.group_member_name then
            raise exception using message = 'group_member_name is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_group_moderators_immutability before update on group_moderators
    for each row execute procedure group_moderators_immutability();


drop function if exists group_moderators_check_dag_requirements() cascade;
create or replace function group_moderators_check_dag_requirements()
    returns trigger as $$
    declare response text;
    declare new_grp text;
    declare new_mod text;
    begin
        assert NEW.group_name != NEW.group_moderator_name, 'groups cannot be moderators of themselves';
        response := NEW.group_name || ' is deactived - to use it in new group moderators it must be active';
        assert (select group_activated from groups where group_name = NEW.group_name) = 't', response;
        response := NEW.group_moderator_name || ' is deactived - to use it in new group moderators it must be active';
        assert (select group_activated from groups where group_name = NEW.group_moderator_name) = 't', response;
        response := NEW.group_name || ' has expired - to use it in new group moderators its expiry date must be later than the current date';
        assert (select case when group_expiry_date is not null then group_expiry_date else current_date end
                from groups where group_name = NEW.group_name) >= current_date, response;
        response := NEW.group_moderator_name || ' has expired - to use it in new group moderators its expiry date must be later than the current date';
        assert (select case when group_expiry_date is not null then group_expiry_date else current_date end
                from groups where group_name = NEW.group_moderator_name) >= current_date, response;
        response := NEW.group_name || ' is a primary group, and cannot be moderated';
        assert (select group_class from groups where group_name = NEW.group_name) = 'secondary', response;
        response := 'Making ' || NEW.group_name || ' a moderator of '
                   || NEW.group_moderator_name || ' will create a cyclical graph - which is not allowed.';
        assert (select count(*) from group_moderators
                where group_name = NEW.group_moderator_name
                and group_moderator_name = NEW.group_name) = 0, response;
        return new;
    end;
$$ language plpgsql;
create trigger group_memberships_dag_requirements_trigger after insert on group_moderators
    for each row execute procedure group_moderators_check_dag_requirements();


drop function if exists get_memberships(text) cascade;
create or replace function get_memberships(member text, grp text)
    returns json as $$
    declare data json;
    begin
        execute format(
            'select json_agg(json_build_object(
                $1, member_name,
                $2, member_group_name,
                $3, group_activated,
                $4, group_expiry_date))
            from (select member_name, member_group_name from group_get_parents($5)
                  union select %s, %s)a
            join (select group_name, group_activated, group_expiry_date from groups)b
            on a.member_group_name = b.group_name', quote_literal(member), quote_literal(grp))
            using 'member_name', 'member_group', 'group_activated', 'group_expiry_date', grp
            into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists person_groups(text) cascade;
create or replace function person_groups(person_id text)
    returns json as $$
    declare pid uuid;
    declare pgrp text;
    declare res json;
    declare pgroups json;
    declare data json;
    begin
        pid := $1::uuid;
        assert (select exists(select 1 from persons where persons.person_id = pid)) = 't', 'person does not exist';
        select person_group from persons where persons.person_id = pid into pgrp;
        select get_memberships(person_id, pgrp) into pgroups;
        select json_build_object('person_id', person_id, 'person_groups', pgroups) into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists user_groups(text) cascade;
create or replace function user_groups(user_name text)
    returns json as $$
    declare ugrp text;
    declare ugroups json;
    declare exst boolean;
    declare data json;
    begin
        execute format('select exists(select 1 from users where users.user_name = $1)') using $1 into exst;
        assert exst = 't', 'user does not exist';
        select user_group from users where users.user_name = $1 into ugrp;
        select get_memberships(user_name, ugrp) into ugroups;
        select json_build_object('user_name', user_name, 'user_groups', ugroups) into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists user_moderators(text);
create or replace function user_moderators(user_name text)
    returns json as $$
    declare exst boolean;
    declare ugrps json;
    declare mods json;
    declare data json;
    begin
        execute format('select exists(select 1 from users where users.user_name = $1)') using $1 into exst;
        assert exst = 't', 'user does not exist';
        select user_groups->>'user_groups' from user_groups(user_name) into ugrps;
        if ugrps is null then
            mods := '[]'::json;
        else
            select json_agg(group_name) from group_moderators
                where group_moderator_name in
                (select json_array_elements(user_groups->'user_groups')->>'member_group'
                from user_groups(user_name)) into mods;
        end if;
        select json_build_object('user_name', user_name, 'user_moderators', mods) into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists group_member_add(text, text) cascade;
create or replace function group_member_add(group_name text, member text)
    returns json as $$
    declare gnam text;
    declare unam text;
    declare mem text;
    begin
        gnam := $1;
        assert (select exists(select 1 from groups where groups.group_name = gnam)) = 't', 'group does not exist';
        if member in (select groups.group_name from groups) then
            mem := member;
        else
            begin
                assert (select exists(select 1 from persons where persons.person_id = member::uuid)) = 't';
                select person_group from persons where persons.person_id = member::uuid into mem;
            exception when others or assert_failure then
                begin
                    assert (select exists(select 1 from users where users.user_name = member)) = 't';
                    select user_group from users where users.user_name = member into mem;
                exception when others or assert_failure then
                    return json_build_object('message', 'could not add member');
                end;
            end;
        end if;
        execute format('insert into group_memberships values ($1, $2)')
            using gnam, mem;
        return json_build_object('message', 'member added');
    end;
$$ language plpgsql;


drop function if exists group_member_remove(text, text) cascade;
create or replace function group_member_remove(group_name text, member text)
    returns json as $$
    declare gnam text;
    declare unam text;
    declare mem text;
    begin
        gnam := $1;
        assert (select exists(select 1 from groups where groups.group_name = gnam)) = 't', 'group does not exist';
        if member in (select groups.group_name from groups) then
            mem := member;
        else
            begin
                assert (select exists(select 1 from persons where persons.person_id = member::uuid)) = 't';
                select person_group from persons where persons.person_id = member::uuid into mem;
            exception when others or assert_failure then
                begin
                    assert (select exists(select 1 from users where users.user_name = member)) = 't';
                    select user_group from users where users.user_name = member into mem;
                exception when others or assert_failure then
                    return json_build_object('message', 'could not remove member');
                end;
            end;
        end if;
        execute format('delete from group_memberships where group_name = $1 and group_member_name = $2')
            using gnam, mem;
        return json_build_object('message', 'member removed');
    end;
$$ language plpgsql;


drop function if exists grp_mems(text) cascade;
create or replace function grp_mems(gn text)
    returns table(group_name text,
                  group_member_name text,
                  group_primary_member text,
                  group_activated boolean,
                  group_expiry_date timestamptz) as $$
    select a.group_name,
           a.group_member_name,
           a.group_primary_member,
           b.group_activated,
           b.group_expiry_date
    from (select group_name, group_member_name, group_primary_member from group_get_children(gn))a
    join (select group_name, group_activated, group_expiry_date from groups)b
    on a.group_name = b.group_name
$$ language sql;


drop function if exists group_members(text) cascade;
create or replace function group_members(group_name text)
    returns json as $$
    declare direct_data json;
    declare transitive_data json;
    declare primary_data json;
    declare data json;
    begin
        assert (select exists(select 1 from groups where groups.group_name = $1)) = 't', 'group does not exist';
        select json_agg(distinct group_primary_member) from group_get_children($1)
            where group_primary_member is not null into primary_data;
        select json_agg(json_build_object(
            'group', gm.group_name,
            'group_member', gm.group_member_name,
            'primary_member', gm.group_primary_member,
            'activated', gm.group_activated,
            'expiry_date', gm.group_expiry_date))
            from grp_mems($1) gm where gm.group_name = $1 into direct_data;
        select json_agg(json_build_object(
            'group', gm.group_name,
            'group_member', gm.group_member_name,
            'primary_member', gm.group_primary_member,
            'activated', gm.group_activated,
            'expiry_date', gm.group_expiry_date))
            from grp_mems($1) gm where gm.group_name != $1 into transitive_data;
        select json_build_object('group_name', group_name,
                                 'direct_members', direct_data,
                                 'transitive_members', transitive_data,
                                 'ultimate_members', primary_data) into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists group_moderators(text) cascade;
create or replace function group_moderators(group_name text)
    returns json as $$
    declare data json;
    begin
        assert (select exists(select 1 from groups where groups.group_name = $1)) = 't', 'group does not exist';
        select json_agg(json_build_object(
            'moderator', a.group_moderator_name,
            'activated', b.group_activated,
            'expiry_date', b.group_expiry_date)) from
        (select gm.group_name, gm.group_moderator_name
            from group_moderators gm where gm.group_name = $1)a join
        (select g.group_name, g.group_activated, g.group_expiry_date
            from groups g)b on a.group_name = b.group_name into data;
        return json_build_object('group_name', group_name, 'group_moderators', data);
    end;
$$ language plpgsql;
