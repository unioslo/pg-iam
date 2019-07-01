
-- test pg-idp

create or replace function test()
    returns boolean as $$
    declare pid uuid;
    begin
        insert into persons (given_names, surname)
            values ('Sarah', 'Conner');
        select person_id from persons where surname = 'Conner' into pid;
        insert into users (person_id, user_name, user_group)
            values (pid, 'p11-sconne', 'p11-sconne-group');
    return true;
    end;
$$ language plpgsql;

select test();
select * from persons;
select * from users;
delete from persons;
select * from users; -- test cascasde
