
-- for async listeners to respond to table operations
-- https://www.postgresql.org/docs/current/sql-notify.html

drop function if exists maybe_null(text);
create or replace function maybe_null(val text)
    returns text as $$
    declare out text;
    begin
        if val is not null then
            out = val;
        else
            out = quote_nullable(val);
        end if;
        return out;
    end;
$$ language plpgsql;


drop function if exists create_grants_message(text, record);
create or replace function create_grants_message(operation text, data record)
    returns text as $$
    declare out text;
    begin
        out = operation || ':' ||
           'capability_names_allowed::' || data.capability_names_allowed::text || ':::' ||
           'capability_grant_id::' || data.capability_grant_id || ':::' ||
           'capability_grant_hostnames::' || data.capability_grant_hostnames::text || ':::' ||
           'capability_grant_namespace::' || data.capability_grant_namespace || ':::' ||
           'capability_grant_http_method::' || data.capability_grant_http_method || ':::' ||
           'capability_grant_rank::' || maybe_null(data.capability_grant_rank::text) || ':::' ||
           'capability_grant_uri_pattern::' || data.capability_grant_uri_pattern || ':::' ||
           'capability_grant_required_groups::' || maybe_null(data.capability_grant_required_groups::text) || ':::' ||
           'capability_grant_required_attributes::' || maybe_null(data.capability_grant_required_attributes::text) || ':::' ||
           'capability_grant_quick::' || data.capability_grant_quick || ':::' ||
           'capability_grant_start_date::' || maybe_null(data.capability_grant_start_date::text) || ':::' ||
           'capability_grant_end_date::' || maybe_null(data.capability_grant_end_date::text) || ':::' ||
           'capability_grant_max_num_usages::' || maybe_null(data.capability_grant_max_num_usages::text) || ':::' ||
           'capability_grant_group_existence_check::' || data.capability_grant_group_existence_check || ':::' ||
           'capability_grant_metadata::' || maybe_null(data.capability_grant_metadata::text);
        return out;
    end;
$$ language plpgsql;


drop function if exists notify_listeners() cascade;
create or replace function notify_listeners()
    returns trigger as $$
    declare table_name text;
    declare channel_name text;
    declare operation text;
    declare subject text;
    begin
        table_name := TG_TABLE_NAME::text;
        channel_name := 'channel_' || table_name;
        operation := TG_OP::text;
        if operation in ('INSERT', 'UPDATE') then
            if table_name = 'capabilities_http_grants' then
                subject = create_grants_message(operation, NEW);
            else
                subject = operation || ':' || NEW.*;
            end if;
        elsif operation = 'DELETE' then
            if table_name = 'capabilities_http_grants' then
                subject = create_grants_message(operation, OLD);
            else
                subject = operation || ':' || OLD.*;
            end if;
        end if;
        perform pg_notify(channel_name, subject);
        return new;
    end;
$$ language plpgsql;
