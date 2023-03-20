
\set drop_table_flag `echo "$DROP_TABLES"`
create or replace function drop_tables(drop_table_flag boolean default 'true')
    returns boolean as $$
    declare ans boolean;
    begin
        if drop_table_flag = 'true' then
            raise notice 'DROPPING CAPABILITIES TABLES';
            drop table if exists capabilities_http cascade;
            drop table if exists capabilities_http_instances cascade;
            drop table if exists capabilities_http_grants cascade;
        else
            raise notice 'NOT dropping tables - only functions will be replaced';
        end if;
    return true;
    end;
$$ language plpgsql;
select drop_tables(:drop_table_flag);


create or replace function assert_array_unique(arr text[], name text)
    returns void as $$
    declare err text;
    begin
        if arr is not null then
            if (select cardinality(array(select distinct unnest(arr)))) !=
               (select cardinality(arr))
            then
                raise integrity_constraint_violation
                using message = 'duplicate element: ' || name;
            end if;
        end if;
    end;
$$ language plpgsql;


create table if not exists capabilities_http(
    row_id uuid unique not null default gen_random_uuid(),
    capability_id uuid unique not null default gen_random_uuid(),
    capability_name text unique not null primary key,
    capability_hostnames text[] not null,
    capability_default_claims jsonb,
    capability_required_groups text[],
    capability_required_attributes jsonb,
    capability_group_match_method text default 'wildcard' check (capability_group_match_method in ('exact', 'wildcard')),
    capability_lifetime int not null check (capability_lifetime > 0), -- minutes
    capability_description text not null,
    capability_expiry_date date,
    capability_group_existence_check boolean default 't',
    capability_metadata jsonb
);


drop function if exists ensure_unique_capability_attributes() cascade;
create or replace function ensure_unique_capability_attributes()
    returns trigger as $$
    begin
        perform assert_array_unique(NEW.capability_required_groups, 'capability_required_groups');
        perform assert_array_unique(NEW.capability_hostnames, 'capability_hostnames');
        return new;
    end;
$$ language plpgsql;
create trigger capabilities_http_unique_groups before update or insert on capabilities_http
    for each row execute procedure ensure_unique_capability_attributes();


create trigger capabilities_http_audit after update or insert or delete on capabilities_http
    for each row execute procedure update_audit_log_objects();


drop function if exists capabilities_http_immutability() cascade;
create or replace function capabilities_http_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise integrity_constraint_violation
            using message = 'row_id is immutable';
        elsif OLD.capability_id != NEW.capability_id then
            raise integrity_constraint_violation
            using message = 'capability_id is immutable';
        elsif OLD.capability_name != NEW.capability_name then
            raise integrity_constraint_violation
            using message = 'capability_name is immutable';
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_http_immutability before update on capabilities_http
    for each row execute procedure capabilities_http_immutability();


drop function if exists capabilities_http_group_check() cascade;
create or replace function capabilities_http_group_check()
    returns trigger as $$
    declare new_grps text[];
    declare new_grp text;
    declare num int;
    begin
        if NEW.capability_group_existence_check = 'f' then
            return new;
        end if;
        for new_grp in select unnest(NEW.capability_required_groups) loop
            select count(*) from groups where group_name like '%' || new_grp || '%' into num;
            if num = 0 then
                raise integrity_constraint_violation
                using message = new_grp || ' does not exist';
            end if;
        end loop;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_http_group_check before insert or update on capabilities_http
    for each row execute procedure capabilities_http_group_check();


create trigger capabilities_http_channel_notify after update or insert or delete on capabilities_http
    for each row execute procedure notify_listeners();


create table if not exists capabilities_http_instances(
    row_id uuid unique not null default gen_random_uuid(),
    capability_name text references capabilities_http (capability_name) on delete cascade,
    instance_id uuid unique not null default gen_random_uuid() primary key,
    instance_start_date timestamptz default current_timestamp,
    instance_end_date timestamptz not null,
    instance_usages_remaining int,
    instance_metadata jsonb
);


create trigger capabilities_http_instances_audit after update or insert or delete on capabilities_http_instances
    for each row execute procedure update_audit_log_objects();


drop function if exists capabilities_http_instances_immutability() cascade;
create or replace function capabilities_http_instances_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise integrity_constraint_violation
            using message = 'row_id is immutable';
        elsif OLD.capability_name != NEW.capability_name then
            raise integrity_constraint_violation
            using message = 'capability_name is immutable';
        elsif OLD.instance_id != NEW.instance_id then
            raise integrity_constraint_violation
            using message = 'instance_id is immutable';
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_http_instances_immutability before update on capabilities_http_instances
    for each row execute procedure capabilities_http_instances_immutability();


drop function if exists capability_instance_get(text);
create or replace function capability_instance_get(id text)
    returns json as $$
    declare iid uuid;
    declare cname text;
    declare start_date timestamptz;
    declare end_date timestamptz;
    declare max int;
    declare meta json;
    declare msg text;
    declare new_max int;
    begin
        iid := id::uuid;
        if iid not in (select instance_id from capabilities_http_instances) then
            raise invalid_parameter_value
            using message = 'instance ' || id || ' not found';
        end if;
        select capability_name, instance_start_date, instance_end_date,
               instance_usages_remaining, instance_metadata
        from capabilities_http_instances where instance_id = iid
            into cname, start_date, end_date, max, meta;
        if current_timestamp < start_date then
            raise restrict_violation
            using message = 'instance not active yet - start time: ' || start_date::text;
        elsif current_timestamp > end_date then
            delete from capabilities_http_instances where instance_id = iid;
            raise restrict_violation
            using message = 'instance expired - end time: ' || end_date::text;
        end if;
        new_max := null;
        if max is not null then
            new_max := max - 1;
            if new_max < 1 then
                delete from capabilities_http_instances where instance_id = iid;
            else
                update capabilities_http_instances set instance_usages_remaining = new_max
                    where instance_id = iid;
            end if;
        end if;
        return json_build_object('capability_name', cname,
                                 'instance_id', id,
                                 'instance_start_date', start_date,
                                 'instance_end_date', end_date,
                                 'instance_usages_remaining', new_max,
                                 'instance_metadata', meta);
    end;
$$ language plpgsql;


create trigger capabilities_http_instances_channel_notify after update or insert or delete on capabilities_http_instances
    for each row execute procedure notify_listeners();


create table if not exists capabilities_http_grants(
    row_id uuid unique not null default gen_random_uuid(),
    capability_names_allowed text[] not null,
    capability_grant_id uuid not null default gen_random_uuid() primary key,
    capability_grant_name text unique,
    capability_grant_hostnames text[] not null,
    capability_grant_namespace text not null,
    capability_grant_http_method text not null check (capability_grant_http_method in
                                 ('OPTIONS', 'HEAD', 'GET', 'PUT', 'POST', 'PATCH', 'DELETE')),
    capability_grant_rank int check (capability_grant_rank > 0),
    capability_grant_uri_pattern text not null, -- string or regex referring to a set of resources
    capability_grant_required_groups text[],
    capability_grant_required_attributes jsonb,
    capability_grant_quick boolean default 't',
    capability_grant_start_date timestamptz,
    capability_grant_end_date timestamptz,
    capability_grant_max_num_usages int check (capability_grant_max_num_usages >= 0),
    capability_grant_group_existence_check boolean default 't',
    capability_grant_metadata jsonb,
    unique (capability_grant_namespace,
            capability_grant_http_method,
            capability_grant_rank)
);


drop function if exists ensure_capability_name_references_consistent() cascade;
create or replace function ensure_capability_name_references_consistent()
    returns trigger as $$
    declare name_references text[];
    declare grant_id uuid;
    declare new text[];
    begin
        for name_references, grant_id in
            select capability_names_allowed, capability_grant_id from capabilities_http_grants
            where array[OLD.capability_name] <@ capability_names_allowed loop
            select array_remove(name_references, OLD.capability_name) into new;
            if cardinality(new) = 0 then
                raise restrict_violation using message =
                'deleting the capability would leave one or more grants ' ||
                'without a reference to any capability which is not allowed ' ||
                'delete the grant before deleting the capability, or change the reference';
            end if;
            update capabilities_http_grants set capability_names_allowed = new
                where capability_grant_id = grant_id;
        end loop;
        return old;
    end;
$$ language plpgsql;
create trigger capabilities_http_consistent_name_references after delete on capabilities_http
    for each row execute procedure ensure_capability_name_references_consistent();


drop function if exists ensure_correct_capability_names_allowed() cascade;
create or replace function ensure_correct_capability_names_allowed()
    returns trigger as $$
    begin
        perform assert_array_unique(NEW.capability_names_allowed, 'capability_names_allowed');
        if (
            (NEW.capability_names_allowed <@ (
                select array_append(array_agg(capability_name), 'all') from capabilities_http
            ) = 'f')
        ) then
            raise integrity_constraint_violation
            using message = 'capability does not exists: ' || NEW.capability_names_allowed::text;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger capabilities_http_grants_correct_names_allowed before insert or update on capabilities_http_grants
    for each row execute procedure ensure_correct_capability_names_allowed();


drop function if exists ensure_unique_grant_arrays() cascade;
create or replace function ensure_unique_grant_arrays()
    returns trigger as $$
    begin
        perform assert_array_unique(NEW.capability_grant_required_groups, 'capability_grant_required_groups');
        perform assert_array_unique(NEW.capability_grant_hostnames, 'capability_grant_hostnames');
        return new;
    end;
$$ language plpgsql;
create trigger capabilities_http_grants_unique_arrays before update or insert on capabilities_http_grants
    for each row execute procedure ensure_unique_grant_arrays();


drop function if exists ensure_sensible_rank_update() cascade;
create or replace function ensure_sensible_rank_update()
    returns trigger as $$
    declare num int;
    begin
        select count(*) from capabilities_http_grants
            where capability_grant_namespace = NEW.capability_grant_namespace
            and capability_grant_http_method = NEW.capability_grant_http_method
            into num;
        if (num > 0 and NEW.capability_grant_rank > num) then
            raise restrict_violation
            using message = 'Rank cannot be updated to a value higher than the number of entries per hostname, namespace, method';
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger capabilities_http_grants_rank_update before update on capabilities_http_grants
    for each row execute procedure ensure_sensible_rank_update();


drop function if exists generate_grant_rank() cascade;
create or replace function generate_grant_rank()
    returns trigger as $$
    declare num int;
    begin
        -- check if first grant for (host, namespace, method) combination
        select count(*) from capabilities_http_grants
            where capability_grant_namespace = NEW.capability_grant_namespace
            and capability_grant_http_method = NEW.capability_grant_http_method
            into num;
        if NEW.capability_grant_rank is not null then
            if NEW.capability_grant_rank != num then
                raise restrict_violation
                using message = 'grant rank values must be monotonically increasing';
            end if;
            return new;
        end if;
        update capabilities_http_grants set capability_grant_rank = num
            where capability_grant_id = NEW.capability_grant_id;
        return new;
    end;
$$ language plpgsql;
create trigger capabilities_http_grants_grant_generation after insert on capabilities_http_grants
    for each row execute procedure generate_grant_rank();


create trigger capabilities_http_grants_audit after update or insert or delete on capabilities_http_grants
    for each row execute procedure update_audit_log_objects();


drop function if exists capabilities_http_grants_immutability() cascade;
create or replace function capabilities_http_grants_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise integrity_constraint_violation
            using message = 'row_id is immutable';
        elsif OLD.capability_grant_id != NEW.capability_grant_id then
            raise integrity_constraint_violation
            using message = 'capability_grant_id is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_http_grants_immutability before update on capabilities_http_grants
    for each row execute procedure capabilities_http_grants_immutability();


drop function if exists capabilities_http_grants_group_check() cascade;
create or replace function capabilities_http_grants_group_check()
    returns trigger as $$
    declare new_grps text[];
    declare new_grp text;
    declare num int;
    begin
        if NEW.capability_grant_group_existence_check = 'f' then
            return new;
        end if;
        for new_grp in select unnest(NEW.capability_grant_required_groups) loop
            select count(*) from groups where group_name like '%' || new_grp || '%' into num;
            if new_grp not in ('self', 'moderator', 'client') then
                if num = 0 then
                    raise integrity_constraint_violation
                    using message = new_grp || ' does not exist';
                end if;
            end if;
        end loop;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_http_grants_group_check before insert or update on capabilities_http_grants
    for each row execute procedure capabilities_http_grants_group_check();


drop function if exists capability_grant_rank_set(text, int) cascade;
create or replace function capability_grant_rank_set(grant_id text, new_grant_rank int)
    returns boolean as $$
    declare target_id uuid;
    declare target_curr_rank int;
    declare target_namespace text;
    declare target_http_method text;
    declare curr_rank int;
    declare curr_id uuid;
    declare new_val int;
    declare current_max int;
    declare current_max_id uuid;
    begin
        target_id := grant_id::uuid;
        if target_id not in (select capability_grant_id from capabilities_http_grants) then
            raise invalid_parameter_value
            using message = 'grant_id not found: ' || target_id;
        end if;
        select capability_grant_rank from capabilities_http_grants
            where capability_grant_id = target_id into target_curr_rank;
        if new_grant_rank = target_curr_rank then
            return true;
        end if;
        select capability_grant_namespace, capability_grant_http_method
            from capabilities_http_grants where capability_grant_id = target_id
            into target_namespace, target_http_method;
        select max(capability_grant_rank) from capabilities_http_grants
            where capability_grant_namespace = target_namespace
            and capability_grant_http_method = target_http_method
            into current_max;
        if (new_grant_rank - current_max) > 1 then
            raise restrict_violation
            using message = 'grant rank values must be monotonically increasing';
        end if;
        if current_max = 1 then
            select capability_grant_id from capabilities_http_grants
                where capability_grant_namespace = target_namespace
                and capability_grant_http_method = target_http_method
                and capability_grant_rank = current_max
                into current_max_id;
            if current_max_id = target_id then
                if new_grant_rank != 1 then
                    raise restrict_violation
                    using message = 'first entry must start at 1';
                end if;
            end if;
        end if;
        update capabilities_http_grants set capability_grant_rank = null
            where capability_grant_id = target_id;
        if new_grant_rank < target_curr_rank then
            for curr_id, curr_rank in
                select capability_grant_id, capability_grant_rank from capabilities_http_grants
                where capability_grant_rank >= new_grant_rank
                and capability_grant_rank < target_curr_rank
                and capability_grant_namespace = target_namespace
                and capability_grant_http_method = target_http_method
                order by capability_grant_rank desc
            loop
                new_val := curr_rank + 1;
                update capabilities_http_grants set capability_grant_rank = new_val
                    where capability_grant_id = curr_id;
            end loop;
        elsif new_grant_rank > target_curr_rank then
            for curr_id, curr_rank in
                select capability_grant_id, capability_grant_rank from capabilities_http_grants
                where capability_grant_rank <= new_grant_rank
                and capability_grant_rank > target_curr_rank
                and capability_grant_namespace = target_namespace
                and capability_grant_http_method = target_http_method
                order by capability_grant_rank asc
            loop
                new_val := curr_rank - 1;
                update capabilities_http_grants set capability_grant_rank = new_val
                    where capability_grant_id = curr_id;
            end loop;
        end if;
        update capabilities_http_grants set capability_grant_rank = new_grant_rank
            where capability_grant_id = target_id;
        return true;
    end;
$$ language plpgsql;


drop function if exists capability_grant_delete(text) cascade;
create or replace function capability_grant_delete(grant_id text)
    returns boolean as $$
    declare target_id uuid;
    declare target_rank int;
    declare target_namespace text;
    declare target_http_method text;
    declare ans boolean;
    begin
        target_id := grant_id::uuid;
        select capability_grant_namespace, capability_grant_http_method
            from capabilities_http_grants where capability_grant_id = target_id
            into target_namespace, target_http_method;
        select max(capability_grant_rank) from capabilities_http_grants
            where capability_grant_namespace = target_namespace
            and capability_grant_http_method = target_http_method
            into target_rank;
        select capability_grant_rank_set(target_id::text, target_rank) into ans;
        delete from capabilities_http_grants where capability_grant_id = target_id;
        return true;
    end;
$$ language plpgsql;


drop function if exists capability_grant_group_add(text, text);
create or replace function capability_grant_group_add(grant_reference text, group_name text)
    returns boolean as $$
    declare current text[];
    declare new text[];
    begin
        begin
            perform grant_reference::uuid;
            select capability_grant_required_groups from capabilities_http_grants
                where capability_grant_id = grant_reference::uuid into current;
            if current is null then
                raise invalid_parameter_value
                using message = 'not found: ' || grant_reference;
            end if;
            select array_append(current, group_name) into new;
            update capabilities_http_grants set capability_grant_required_groups = new
                where capability_grant_id = grant_reference::uuid;
        exception when invalid_text_representation then
            select capability_grant_required_groups from capabilities_http_grants
                where capability_grant_name = grant_reference into current;
            if current is null then
                raise invalid_parameter_value
                using message = 'not found: ' || grant_reference;
            end if;
            select array_append(current, group_name) into new;
            update capabilities_http_grants set capability_grant_required_groups = new
                where capability_grant_name = grant_reference;
        end;
        return true;
    end;
$$ language plpgsql;


drop function if exists capability_grant_group_remove(text, text);
create or replace function capability_grant_group_remove(grant_reference text, group_name text)
    returns boolean as $$
    declare current text[];
    declare new text[];
    begin
        begin
            perform grant_reference::uuid;
            select capability_grant_required_groups from capabilities_http_grants
                where capability_grant_id = grant_reference::uuid into current;
            if current is null then
                raise invalid_parameter_value
                using message = 'not found: ' || grant_reference;
            end if;
            select array_remove(current, group_name) into new;
            if cardinality(new) = 0 then new := null; end if;
            update capabilities_http_grants set capability_grant_required_groups = new
                where capability_grant_id = grant_reference::uuid;
        exception when invalid_text_representation then
            select capability_grant_required_groups from capabilities_http_grants
                where capability_grant_name = grant_reference into current;
            if current is null then
                raise invalid_parameter_value
                using message = 'not found: ' || grant_reference;
            end if;
            select array_remove(current, group_name) into new;
            if cardinality(new) = 0 then new := null; end if;
            update capabilities_http_grants set capability_grant_required_groups = new
                where capability_grant_name = grant_reference;
        end;
        return true;
    end;
$$ language plpgsql;


create trigger capabilities_http_grants_channel_notify after update or insert or delete on capabilities_http_grants
    for each row execute procedure notify_listeners();


drop function if exists grp_cpbts(text, boolean) cascade;
create or replace function grp_cpbts(grp text, grants boolean default 'f')
    returns json as $$
    declare ctype text;
    declare cgrps text[];
    declare rgrp text;
    declare reg text;
    declare matches boolean;
    declare grant_data json;
    declare data json;
    declare grnt_grp text[];
    declare grnt_mthd text;
    declare grnt_ptrn text;
    begin
        if (select exists(select 1 from groups where group_name = grp)) = 'f' then
            raise invalid_parameter_value
            using message = 'group does not exist';
        end if;
        create temporary table if not exists cpb(ct text unique not null) on commit drop;
        delete from cpb;
        -- exact group matches
        for ctype in select capability_name from capabilities_http
            where capability_group_match_method = 'exact'
            and array[grp] && capability_required_groups loop
            insert into cpb values (ctype);
        end loop;
        -- wildcard group matches
        for ctype, cgrps in select capability_name, capability_required_groups from capabilities_http
            where capability_group_match_method = 'wildcard' loop
            for rgrp in select unnest(cgrps) loop
                reg := '.*' || rgrp || '.*';
                if grp ~ reg then
                    begin
                        insert into cpb values (ctype);
                    exception when unique_violation then
                        null;
                    end;
                end if;
            end loop;
        end loop;
        select json_agg(ct) from cpb into data;
        if grants = 'f' then
            return json_build_object('group_name', grp, 'group_capabilities_http', data);
        else
            create temporary table if not exists grnts(method text, pattern text,
                unique (method, pattern)) on commit drop;
            for grnt_grp, grnt_mthd, grnt_ptrn in
                select capability_grant_required_groups, capability_grant_http_method, capability_grant_uri_pattern
                from capabilities_http_grants loop
                    for rgrp in select unnest(grnt_grp) loop
                        reg := '.*' || rgrp || '.*';
                        if grp ~ reg then
                            begin
                                insert into grnts values (grnt_mthd, grnt_ptrn);
                            exception when unique_violation then
                                null;
                            end;
                        end if;
                    end loop;
            end loop;
            select json_agg(json_build_object('method', method, 'pattern', pattern)) from grnts into grant_data;
            return json_build_object('group_name', grp, 'group_capabilities_http', data, 'grants', grant_data);
        end if;
    end;
$$ language plpgsql;

drop function if exists person_capabilities(text, boolean);
create or replace function person_capabilities(person_id text, grants boolean default 'f')
    returns json as $$
    declare pid uuid;
    declare pgrp text;
    declare data json;
    begin
        pid := $1::uuid;
        select person_group from persons where persons.person_id = pid into pgrp;
        select json_agg(grp_cpbts(member_group_name, grants)) from group_get_parents(pgrp) into data;
        return json_build_object('person_id', person_id, 'person_capabilities', data);
    end;
$$ language plpgsql;


drop function if exists user_capabilities(text, boolean) cascade;
create or replace function user_capabilities(user_name text, grants boolean default 'f')
    returns json as $$
    declare ugrp text;
    declare exst boolean;
    declare data json;
    begin
        select user_group from users where users.user_name = $1 into ugrp;
        select json_agg(grp_cpbts(member_group_name, grants)) from group_get_parents(ugrp) into data;
        return json_build_object('user_name', user_name, 'user_capabilities', data);
    end;
$$ language plpgsql;


drop function if exists person_access(text) cascade;
create or replace function person_access(person_id text)
    returns json as $$
    declare pid uuid;
    declare p_data json;
    declare u_data json;
    declare data json;
    begin
        pid := $1::uuid;
        select person_capabilities($1, 't') into p_data;
        select json_agg(user_capabilities(user_name, 't')) from users, persons
            where users.person_id = persons.person_id and users.person_id = pid into u_data;
        select json_build_object('person_id', person_id,
                                 'person_group_access', p_data,
                                 'users_groups_access', u_data) into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists group_capabilities(text, boolean) cascade;
create or replace function group_capabilities(group_name text, grants boolean default 'f')
    returns json as $$
    declare data json;
    begin
        select grp_cpbts(group_name, grants) into data;
        return data;
    end;
$$ language plpgsql;
