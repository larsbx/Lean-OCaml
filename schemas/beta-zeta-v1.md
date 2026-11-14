# β/ζ vectors v1

Each line is ASCII, has LF termination, and contains six tab-separated fields.

```text
eq  case-id  lean-equality  fragment-equality  left-expression  right-expression
```

Booleans are `true` and `false`. Expressions use prefix notation with one space
between tokens. `vN` is de Bruijn index N and `sN` is Sort N for nonnegative
decimal N. `a` takes a function and argument. `l` and `p` take a domain and body.
`t` takes a type, value, and body. Only bodies extend scope. Inputs are closed.
Unexpected vector content, computation errors, or verdict mismatches fail replay.
The Lean and fragment columns agree for every row in the generated corpus.
