
-- test pg-idp

create or replace function test()
    returns boolean as $$
    declare pid uuid;
    begin
        insert into persons (given_names, surname) values ('Sarah', 'Conner');
        select person_id from persons where surname = 'Conner' into pid;
        insert into users (person_id, user_name)
            values (pid, 'p11-sconne');
    return true;
    end;
$$ language plpgsql;

select test();
select * from persons;
select * from users;
select * from groups;
delete from persons;
select * from groups;
select * from users; -- test cascasde
