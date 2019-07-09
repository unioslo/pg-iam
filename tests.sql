
-- tests pg-idp
-- TODOs:
-- consistent trigger names
-- non-cyclicality enforcement
-- audit?
-- additional fields on persons, users
-- capability generation and validation
-- rpc API?
-- RLS access control

create or replace function test_persons_users_groups()
    returns boolean as $$
    declare pid uuid;
    declare num int;
    begin
        insert into persons (given_names, surname, person_expiry_date)
            values ('Sarah', 'Conner', '2020-10-01');
        select person_id from persons where surname = 'Conner' into pid;
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-sconne', '2020-03-28');
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p66-sconne', '2019-12-01');
        -- creation
        select count(*) from persons into num;
        assert num = 1, 'person creation issue';
        select count(*) from users where person_id = pid into num;
        assert num = 2, 'user creation issue';
        select count(*) from groups into num;
        assert num = 3, 'group creation issue';
        -- person attribute immutability
        begin
            update persons set person_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            return false;
        exception when others then
            raise notice 'person_id immutable';
        end;
        begin
            update persons set person_group = 'e14c538a-4b8b-4393-9fb2-056e363899e1-group';
            return false;
        exception when others then
            raise notice 'person_group immutable';
        end;
        -- user attribute immutability
        begin
            update users set user_id = 'a3981c7f-8e41-4222-9183-1815b6ec9c3b';
            return false;
        exception when others then
            raise notice 'user_id immutable';
        end;
        begin
            update users set user_name = 'p11-scnr';
            return false;
        exception when others then
            raise notice 'user_name immutable';
        end;
        begin
            update users set user_group = 'p11-s-group';
            return false;
        exception when others then
            raise notice 'user_group immutable';
        end;
        -- group attribute immutability
        begin
            update groups set group_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            return false;
        exception when others then
            raise notice 'group_id immutable';
        end;
        begin
            update groups set group_name = 'p22-lcd-group';
            return false;
        exception when others then
            raise notice 'group_name immutable';
        end;
        begin
            update groups set group_class = 'secondary';
            return false;
        exception when others then
            raise notice 'group_class immutable';
        end;
        begin
            update groups set group_type = 'person';
            return false;
        exception when others then
            raise notice 'group_type immutable';
        end;
        -- states; cascades, constraints
        -- expiry dates: cascades, constraints
        -- deletion; cascades, constraints
    return true;
    end;
$$ language plpgsql;

select test_persons_users_groups();


update persons set person_activated = 'f';
update persons set person_expiry_date = '2019-09-09';
select * from persons;
select * from users;
select * from groups;
update users set user_expiry_date = '2000-08-08' where user_name like 'p11-%';
select * from users;
update groups set group_expiry_date = '2000-01-01' where group_primary_member = 'p11-sconne';
delete from groups where group_type = 'person';
delete from groups where group_type = 'user';
delete from groups where group_class = 'primary';
delete from persons;
select * from users;
select * from groups;
