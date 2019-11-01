
drop table if exists capabilities_http cascade;
create table if not exists capabilities_http(
    row_id uuid unique not null default gen_random_uuid(),
    capability_id uuid unique not null default gen_random_uuid(),
    capability_name text unique not null,
    capability_default_claims jsonb,
    capability_required_groups text[] not null,
    capability_group_match_method text not null check (capability_group_match_method in ('exact', 'wildcard')),
    capability_lifetime int not null check (capability_lifetime > 0), -- minutes
    capability_description text not null,
    capability_expiry_date date,
    capability_group_existence_check boolean default 't'
);


create trigger capabilities_http_audit after update or insert or delete on capabilities_http
    for each row execute procedure update_audit_log_objects();


drop function if exists capabilities_http_immutability() cascade;
create or replace function capabilities_http_immutability()
    returns trigger as $$
    begin
        assert OLD.row_id = NEW.row_id, 'row_id is immutable';
        assert OLD.capability_id = NEW.capability_id, 'capability_id is immutable';
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
            assert num > 0, new_grp || ' does not exist';
        end loop;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_http_group_check before insert or update on capabilities_http
    for each row execute procedure capabilities_http_group_check();


drop table if exists capabilities_http_grants cascade;
create table capabilities_http_grants(
    row_id uuid unique not null default gen_random_uuid(),
    capability_id uuid references capabilities_http (capability_id) on delete cascade,
    capability_name text references capabilities_http (capability_name),
    -- grant_id ?
    capability_grant_rank int, -- constraint, model???
    capability_grant_hostname text,
    capability_grant_http_method text not null check (capability_grant_http_method in ('OPTIONS', 'HEAD', 'GET', 'PUT', 'POST', 'PATCH', 'DELETE')),
    capability_grant_uri_pattern text not null, -- string or regex referring to a set of resources
    capability_grant_required_groups text[],
    capability_grant_start_date timestamptz,
    capability_grant_end_date timestamptz,
    capability_grant_max_num_usages int,
    capability_grant_group_existence_check boolean default 't'
);


create trigger capabilities_http_grants_audit after update or insert or delete on capabilities_http_grants
    for each row execute procedure update_audit_log_relations();


drop function if exists capabilities_http_grants_immutability() cascade;
create or replace function capabilities_http_grants_immutability()
    returns trigger as $$
    begin
        assert OLD.row_id = NEW.row_id, 'row_id is immutable';
        assert OLD.capability_id = NEW.capability_id, 'capability_id is immutable';
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
            assert num > 0, new_grp || ' does not exist';
        end loop;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_http_grants_group_check before insert or update on capabilities_http_grants
    for each row execute procedure capabilities_http_grants_group_check();


drop function if exists capability_grants(text) cascade;
create or replace function capability_grants(capability_name text)
    returns json as $$
    declare data json;
    begin
        assert (select exists(select 1 from capabilities_http where capabilities_http.capability_name = $1)) = 't',
            'capability_name does not exist';
        select json_agg(json_build_object(
                    'http_method', capability_grant_http_method,
                    'uri_pattern', capability_grant_uri_pattern))
            from capabilities_http_grants
            where capabilities_http_grants.capability_name = $1 into data;
        return json_build_object('capability_name', capability_name, 'capability_grants', data);
    end;
$$ language plpgsql;


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
    begin
        assert (select exists(select 1 from groups where group_name = grp)) = 't', 'group does not exist';
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
            select json_agg(json_build_object(capability_name, capability_grants(capability_name)))
                from capabilities_http where capability_name in (select * from cpb) into grant_data;
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
        assert (select exists(select 1 from persons where persons.person_id = pid)) = 't', 'person does not exist';
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
        execute format('select exists(select 1 from users where users.user_name = $1)') using $1 into exst;
        assert exst = 't', 'user does not exist';
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
        assert (select exists(select 1 from persons where persons.person_id = pid)) = 't', 'person does not exist';
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
