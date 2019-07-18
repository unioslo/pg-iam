
# pg-idp

A generic database backend for use in IdPs.

# Features

- create persons, with optional expiry dates
- give them user accounts, with optional expiry dates
- create groups, with optional expiry dates
- add the users to groups, and/or groups to groups
- add persons without users to groups (for external account access control management)
- allow groups to moderate memberships of other groups
- create capabilities, specifying necessary group memberships to obtain them, with optional expiry dates
- specify the scope of the capabilities
- use helpful SQL RPCs to get group related information for application development
- rest assured data integrity and consistency is maintained, with immutable columns wherever possible
- access full audit log on all updates

# Learn more

See `./docs`.

# LICENSE

BSD.
