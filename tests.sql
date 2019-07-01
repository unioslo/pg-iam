
-- test pg-idp

create or replace function test()
    returns boolean as $$
    begin
        insert into persons ()
            values ();
    end;
$$ language plpgsql;

select test();
