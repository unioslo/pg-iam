
# DB Structure

## Table overview

Applications can interact with the following tables to build their core IdP, Authentication and Authorization functionality.

```sql
persons
users
groups
group_memberships
group_moderators
capabilities_http
capabilities_http_grants
audit_log
```

To investigate the tables more, it is best to install `pg-idp` and inspect the DB descriptions via `\d`.

## Function overview

To ease routine tasks for getting information, `pg-idp` provides a set of helper functions which combine information from various tables.

```sql
person_groups(person_id text) -- group memberships graph via person group
person_capabilities(person_id text, grants boolean) -- person capabilities via groups
person_access(person_id text) -- all access via person and all user accounts
user_groups(user_name text) -- group memberships graph via user group
user_capabilities(user_name text, grants boolean) -- user capabilities via groups
group_members(group_name text) -- graph of members
group_moderators(group_name text) -- list of moderators
group_member_add(group_name text, member text) -- add a new member, via person_id, user_name, or group_name
group_member_remove(group_name text, member text) -- remove a member, via person_id, user_name, or group_name
group_capabilities(group_name text) -- capabilities accessible by a group
capability_grants(capabilities_type text) -- grants associated with a capability
```
