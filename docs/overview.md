
## data object hierarchy

```txt
P ---> U ----> G (p,u)
  -----------> G (p,p)
            -> G (s,g) -> G (members, moderators)
```

## active/inactive state relations

- person group state -> f(person state)
- user group state -> f(user state) -> f(person state)
- group state -> f(.)

## expiry date relations

- person group exp == person exp
- user group exp == user exp
- user exp <= person exp
