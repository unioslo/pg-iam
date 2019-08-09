
-- how to get the group membership history for a person and/or user
select * from audit_log_relations where child =
    (select group_name from groups
    where group_primary_member =
        (select user_name from users where
        person_id = '79c74ba8-8cf4-43a2-b307-d0c2b7381897'));
