
# pg-idp

A generic database backend for use in IdPs.

# Features

- create persons, users, and groups with optional expiry dates
- add users and/or groups to groups
- add persons without users to groups, for external account access control management
- allow groups to moderate memberships of other groups
- create capabilities, specify criteria for obtaining them
- specify the scope of the capabilities
- use SQL RPCs to get group related information for application development
- data integrity and consistency, immutable columns wherever possible
- audit log on all updates

# Learn more

See `./docs`.

# LICENSE

BSD.
