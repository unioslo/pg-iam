# pg-iam advisory lock registry

## Namespaces

* **1000**: POSIX ID allocation

## Locks

| Namespace | Resource | Purpose                                 |
| --------- | -------- | --------------------------------------- |
| 1000      | 1        | UID allocation (generate_new_posix_uid) |
| 1000      | 2        | GID allocation (generate_new_posix_gid) |
