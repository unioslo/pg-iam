
# DB Structure

## Table overview

Applications can interact with the following tables to build their core IdP, Authentication and Authorization functionality.

```sql
audit_log_objects
audit_log_relations
persons
users
groups
group_memberships
group_moderators
group_affiliations
capabilities_http
capabilities_http_instances
capabilities_http_grants
institutions
projects
```

To investigate the tables more, it is best to install `pg-iam` and inspect the DB descriptions via `\d`.

## Function overview

To ease routine tasks for getting information, `pg-iam` provides a set of helper functions which combine information from various tables.

```sql
person_groups(
    person_id text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
)
/*
    Returns:
    {person_id: '', person_groups: []}
*/

person_capabilities(person_id text, grants boolean)
/*
    Returns:
    {person_id: '', person_capabilities: []}
*/

person_access(
    person_id text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
)
/*
    Returns:
    {person_id: '', person_access: {person_group_access: [], users_groups_access: []}}
*/

user_groups(
    user_name text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
)
/*
    Returns:
    {user_name: '', user_groups: []}
*/

user_moderators(user_name text)
/*
    Returns:
    {user_name: '', user_moderators:: []}
*/

user_capabilities(user_name text, grants boolean)
/*
    Returns:
    {user_name: '', user_capabilities: []}
*/

group_members(
    group_name text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
)
/*
    Returns:
    {direct_members: [], transitive_members: [], ultimate_members: []}
*/

group_moderators(group_name text)
/*
    Returns:
    {group_name: '', group_moderators: []}
*/

group_member_add(
    group_name text,
    member text,
    start_date timestamptz default null,
    end_date timestamptz default null,
    weekdays jsonb default null -- e.g. {"mon": {"start": "08:00", "end": "17:00"}}
)
/*
    Returns:
    {message: ''}
*/

group_member_remove(group_name text, member text)
/*
    Returns:
    {message: ''}
*/

group_capabilities(group_name text)
/*
    Returns:
    {group_name: '', group_capabilities: []}
*/

group_affiliations(group_name text)
/*
    Returns:
    {group_name: '', group_affiliations: []}
*/

group_affiliates(group_name text)
/*
    Returns:
    {group_name: '', group_affiliates: []}
*/

capability_grant_rank_set(grant_id text, new_grant_rank int)
/*
    Returns:
    boolean
*/

capability_grant_delete(grant_id text)
/*
    Returns:
    boolean
*/

capability_instance_get(id text)
/*
    Returns:
    {capablity_name, instance_id, instance_start_date, instance_end_date, instance_usages_remaining, instance_metadata}
*/

capability_grant_group_add(grant_reference text, group_name text)
/*
    Returns
    boolean
*/

capability_grant_group_remove(grant_reference text, group_name text)
/*
    Returns
    boolean
*/

institution_member_add(institution text, member text)
/*
    Returns
    {message: ''}
*/

institution_member_remove(institution text, member text)
/*
    Returns
    {message: ''}
*/

institution_members(institution text)
/*
    Returns
    {group_name, ', group_members: []}
*/

institution_group_add(institution text, group_name text)
/*
    Returns
    {message: ''}
*/

institution_group_remove(institution text, group_name text)
/*
    Returns
    {message: ''}
*/

institution_groups(institution text)
/*
    Returns
    {group_name: '', group_affiliates: []}
*/

project_group_add(project text, group_name text)
/*
    Returns
    {message: ''}
*/

project_group_remove(project text, group_name text)
/*
    Returns
    {message: ''}
*/

project_groups(proj)
/*
    Returns
    {group_name: '', group_affiliates: []}
*/

project_institutions(proj)
/*
    Returns
    {project: '', institutions: []}
*/
```
