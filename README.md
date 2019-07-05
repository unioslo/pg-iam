
# pg-idp

A DB for IdPs.

# Features

- store information about persons, users, groups
- manage group membership, and group moderation rights
- cyclical group memberships prevention
- specify capabilities to enforce access control
- small code base, depends on postgres, and pgcrypto library
- clear data model
- immutable attributes when possible
- persons, users, and groups can be active/inactive, and have expiry dates
- extensive data consistency checks
- wide test coverage
- generic
- maybe: audit, rpc api, rls policies
