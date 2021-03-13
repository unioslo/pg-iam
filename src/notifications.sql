
-- for async listeners to respond to table operations
-- https://www.postgresql.org/docs/current/sql-notify.html

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
        operation := TG_OP;
        if operation in ('INSERT', 'UPDATE') then
            if table_name in ('group_memberships', 'group_moderators') then
                subject = 'group_name:' || NEW.group_name;
            else
                subject = 'row_id:' || NEW.row_id::text;
            end if;
        elsif operation = 'DELETE' then
            if table_name in ('group_memberships', 'group_moderators') then
                subject = 'group_name:' || OLD.group_name;
            else
                subject = 'row_id:' || OLD.row_id::text;
            end if;
        end if;
        perform pg_notify(channel_name, operation || ':' || subject);
        return new;
    end;
$$ language plpgsql;
