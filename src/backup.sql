
\set bu_schema `echo "$BU_SCHEMA"`

create schema if not exists :bu_schema;

select * into :bu_schema.persons FROM persons;
select * into :bu_schema.users FROM users;
select * into :bu_schema.groups FROM groups;
select * into :bu_schema.group_memberships FROM group_memberships;
select * into :bu_schema.group_moderators FROM group_moderators;
select * into :bu_schema.capabilities_http FROM capabilities_http;
select * into :bu_schema.capabilities_http_instances FROM capabilities_http_instances;
select * into :bu_schema.capabilities_http_grants FROM capabilities_http_grants;
select * into :bu_schema.audit_log_objects FROM audit_log_objects;
select * into :bu_schema.audit_log_relations FROM audit_log_relations;
select * into :bu_schema.institutions FROM institutions;
select * into :bu_schema.projects FROM projects;
