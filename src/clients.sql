
\set drop_table_flag `echo "$DROP_TABLES"`
create or replace function drop_tables(drop_table_flag boolean default 'true')
    returns boolean as $$
    declare ans boolean;
    begin
        if drop_table_flag = 'true' then
            raise notice 'DROPPING CLIENT TABLES';
            drop table if exists clients;
            drop table if exists client_ips;
        else
            raise notice 'NOT dropping tables - only functions will be replaced';
        end if;
    return true;
    end;
$$ language plpgsql;
select drop_tables(:drop_table_flag);

create table if not exists client_ips(
    row_id uuid unique not null default gen_random_uuid(),
    address_range cidr unique not null,
    comment text,
    used_by text[],
    expiry_date timestamptz
);

create trigger client_ips_channel_trigger after insert or update or delete on client_ips
    for each row execute procedure notify_listeners();

create trigger client_ips_audit after update or insert or delete on client_ips
    for each row execute procedure update_audit_log_objects();

create table if not exists clients(
    row_id uuid unique not null default gen_random_uuid(),
    client_id text primary key,
    client_id_issued_at timestamptz default now(),
    client_secrets text[],
    client_expires_at timestamptz default now() + interval '6 years',
    redirect_uris text[],
    token_endpoint_auth_method text default 'basic',
    grant_types text[] default '{authorization_code}',
    response_types text[] default '{code}',
    client_name text unique not null,
    client_uri text,
    scopes_allowed text[],
    contacts text[],
    application_type text default 'web',
    verified int not null default 0,
    projects_applied_to text[],
    projects_granted text[],
    allowed_auth_modes text[],
    allowed_token_types text[],
    user_info_return_type text,
    acrs_allowed text[] default '{level3}',
    require_auth_time bool default 't',
    apps text[],
    managers text[], -- legacy, remove
    post_logout_redirect_uris text[],
    allowed_conditional_token_types jsonb,
    project_prompt text[] default '{user_projects}',
    allow_expired_password bool default 'f',
    providers_granted text[],
    authenticated_access_tokens bool default 'f',
    allowed_enrichable_claims text[],
    allowed_ips cidr[]
);

create trigger clients_channel_trigger after insert or update or delete on clients
    for each row execute procedure notify_listeners();

create trigger client_audit after update or insert or delete on clients
    for each row execute procedure update_audit_log_objects();

drop function if exists client_ips_used_by_management() cascade;
create or replace function client_ips_used_by_management()
    returns trigger as $$
    begin
        update client_ips set used_by = array_remove(used_by, OLD.client_id)
            where used_by && array[OLD.client_id];
    return new;
    end;
$$ language plpgsql;
create trigger client_ips_used_by_management_trigger after delete on clients
    for each row execute procedure client_ips_used_by_management();
