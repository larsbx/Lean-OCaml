import Lean

open Lean

def ty : Expr := .sort (.succ .zero)
def bind (body : Expr) : Expr := .lam `x ty body .default

def wrap : Nat → Expr → Expr
  | 0, term => term
  | n + 1, term =>
    let inner := wrap n term
    if n % 2 == 0 then .app (bind (.bvar 0)) inner
    else .letE `x ty inner (.bvar 0) false

def levelNumber : Level → Except String Nat
  | .zero => pure 0
  | .succ level => return (← levelNumber level) + 1
  | _ => throw "non-numeral universe"

def encode : Expr → Except String String
  | .sort level => return s!"s{← levelNumber level}"
  | .bvar n => pure s!"v{n}"
  | .const name [] => pure s!"c{name}"
  | .lam _ domain body _ => return s!"l {← encode domain} {← encode body}"
  | .forallE _ domain body _ => return s!"p {← encode domain} {← encode body}"
  | .app f x => return s!"a {← encode f} {← encode x}"
  | .letE _ domain value body _ =>
    return s!"t {← encode domain} {← encode value} {← encode body}"
  | _ => throw "unsupported generator expression"

inductive DefinitionOutcome where
  | accepted
  | alreadyDeclared
  | unknownConstant
  | declTypeMismatch
  | typeExpected
deriving BEq, Repr

def DefinitionOutcome.tag : DefinitionOutcome → String
  | .accepted => "accepted"
  | .alreadyDeclared => "alreadyDeclared"
  | .unknownConstant => "unknownConstant"
  | .declTypeMismatch => "declTypeMismatch"
  | .typeExpected => "typeExpected"

def definitionOutcome : Except Kernel.Exception Environment → Option DefinitionOutcome
  | .ok _ => some .accepted
  | .error (.alreadyDeclared ..) => some .alreadyDeclared
  | .error (.unknownConstant ..) => some .unknownConstant
  | .error (.declTypeMismatch ..) => some .declTypeMismatch
  | .error (.typeExpected ..) => some .typeExpected
  | .error _ => none

def checkedDefinition (env : Environment) (name : Name) (type value : Expr)
    (maxRecDepth : USize := 1000) : Except Kernel.Exception Environment :=
  env.addDeclCore 100000 maxRecDepth (.defnDecl {
    name, levelParams := [], type, value, hints := .abbrev, safety := .safe
  }) none (doCheck := true)

def checkDefinitionControls (env : Environment)
    (refusals : Array (DefinitionOutcome × Kernel.Exception)) : IO Unit := do
  let prop := Expr.sort .zero
  let unrelated := checkedDefinition env `ocamlRefNonFunction ty (.app prop prop)
  let .error (.funExpected ..) := unrelated
    | throw (IO.userError "definition control did not produce funExpected")
  let exhausted := checkedDefinition env `ocamlRefLowRecursion ty (wrap 64 prop) 4
  let .error .deepRecursion := exhausted
    | throw (IO.userError "definition control did not exhaust kernel recursion")
  let failures := [
    unrelated, exhausted,
    .error .deterministicTimeout, .error .excessiveMemory, .error .interrupted
  ]
  let mut checks := 0
  for (required, _) in refusals do
    let alternatives := refusals.toList.filterMap fun (other, error) =>
      if other == required then none else some (.error error)
    let injected := Except.error (.other required.tag)
    for result in .ok env :: injected :: failures ++ alternatives do
      if definitionOutcome result == some required then
        throw (IO.userError s!"unrelated outcome satisfied {required.tag}")
      checks := checks + 1
  IO.println s!"Strict Lean definition replay passed: 2 insertions, {refusals.size} exact semantic refusals, 1 inference, {checks} refusal controls"

def main (args : List String) : IO Unit := do
  let [out] := args | throw (IO.userError "expected output path")
  initSearchPath (← findSysroot)
  let env ← importModules #[{module := `Init}] {}
  let mut rows := #[]
  for depth in [2:10] do
    let close := fun body => Nat.rec body (fun _ term => bind term) depth
    let outer := Expr.bvar (depth - 1)
    let inner := Expr.bvar 0
    for steps in [1:7] do
      for (label, left, right, expected) in [
        ("first", wrap steps outer, outer, true),
        ("last", inner, wrap steps inner, true),
        ("distinct", wrap steps outer, wrap steps inner, false)] do
        let left := close left
        let right := close right
        let name := s!"generated-{depth}-{steps}-{label}"
        let result := do
          let lt ← Kernel.check env {} left
          let rt ← Kernel.check env {} right
          let sameType ← Kernel.isDefEq env {} lt rt
          let equal ← Kernel.isDefEq env {} left right
          pure (sameType, equal)
        let .ok (true, equal) := result
          | throw (IO.userError s!"type check failed: {name}")
        unless equal == expected do
          throw (IO.userError s!"unexpected Lean equality: {name}")
        let .ok (l, r) := Prod.mk <$> encode left <*> encode right
          | throw (IO.userError s!"encoding failed: {name}")
        rows := rows.push (String.intercalate "\t" ["eq", name, toString equal, toString expected, l, r])
  IO.FS.writeFile out (String.intercalate "\n" rows.toList ++ "\n")

  let prop := Expr.sort .zero
  let pi := fun domain body => Expr.forallE `x domain body .default
  let lam := fun domain body => Expr.lam `x domain body .default
  let v := Expr.bvar
  let cases : List (String × Expr × Option Expr) := [
    ("sort", prop, some ty),
    ("pi-max", pi ty ty, some (.sort (.succ (.succ .zero)))),
    ("pi-impredicative", pi ty (pi prop (v 0)), some prop),
    ("identity", bind (v 0), some (pi ty ty)),
    ("dependent-identity", bind (lam (v 0) (v 0)), some (pi ty (pi (v 0) (v 1)))),
    ("dependent-application", .app (bind (lam (v 0) (v 0))) prop,
      some (pi prop prop)),
    ("zeta-dependent-type", .letE `x ty prop (lam (v 0) (v 0)) false, some (pi prop prop)),
    ("conversion-in-argument", .app (bind (v 0)) (.letE `x ty prop (v 0) false), some ty),
    ("nonfunction", .app prop prop, none),
    ("argument-mismatch", .app (bind (v 0)) ty, none),
    ("let-mismatch", .letE `x ty ty prop false, none),
    ("binder-not-type", lam (bind (v 0)) (v 0), none),
    ("pi-body-not-type", pi ty (bind (v 0)), none)
  ]
  let mut generatedTypes := #[]
  for depth in [0:9] do
    -- A and B are independent type variables. The argument has type A in
    -- the positive case and type B in the negative case.
    let domain := v (depth + 2)
    let argument := v depth
    let identity := lam domain (v 0)
    let direct := Expr.app identity argument
    let wrapped := Expr.letE `y domain direct (v 0) false
    let pads := fun binder body => Nat.rec body (fun _ inner => binder ty inner) depth
    let close := fun domain body => bind (bind (lam domain (pads lam body)))
    let expected := pi ty (pi ty (pi (v 1) (pads pi domain)))
    generatedTypes := generatedTypes.push (s!"depth-{depth}-beta", close (v 1) direct, some expected)
    generatedTypes := generatedTypes.push (s!"depth-{depth}-zeta", close (v 1) wrapped, some expected)
    generatedTypes := generatedTypes.push (s!"depth-{depth}-wrong-binder", close (v 0) direct, none)
  let mut typeRows := #[]
  for (name, expr, expected) in cases ++ generatedTypes.toList do
    let .ok input := encode expr | throw (IO.userError s!"input encoding failed: {name}")
    match Kernel.check env {} expr, expected with
    | .ok actual, some expected =>
      let .ok true := Kernel.isDefEq env {} actual expected
        | throw (IO.userError s!"unexpected Lean type: {name}")
      let .ok output := encode expected | throw (IO.userError s!"type encoding failed: {name}")
      typeRows := typeRows.push s!"type\t{name}\t{input}\t{output}"
    | .error _, none => typeRows := typeRows.push s!"type\t{name}\t{input}\trefused"
    | _, _ => throw (IO.userError s!"unexpected Lean check result: {name}")
  IO.FS.writeFile (out ++ ".types") (String.intercalate "\n" typeRows.toList ++ "\n")
  let alias := Name.mkSimple "ocamlRefAlias"
  let id := Name.mkSimple "ocamlRefId"
  let missing := Name.mkSimple "ocamlRefMissing"
  let definitions : List (Name × Expr × Expr × DefinitionOutcome) := [
    (alias, ty, prop, .accepted),
    (id, pi (.const alias []) (.const alias []), lam (.const alias []) (v 0), .accepted),
    (alias, ty, prop, .alreadyDeclared),
    (missing, ty, .const missing [], .unknownConstant),
    (Name.mkSimple "ocamlRefMismatch", ty, ty, .declTypeMismatch),
    (Name.mkSimple "ocamlRefNonType", lam ty (v 0), prop, .typeExpected)
  ]
  let initialEnv := env
  let mut env := env
  let mut definitionRows := #[]
  let mut inserted := #[]
  let mut refusals := #[]
  for (name, type, value, expected) in definitions do
    let result := checkedDefinition env name type value
    let observed := definitionOutcome result
    unless observed == some expected do
      throw (IO.userError s!"{name}: expected {expected.tag}, got {repr observed}")
    match result with
    | .ok next =>
      env := next
      inserted := inserted.push (name, type, value)
    | .error error =>
      if expected != .alreadyDeclared && env.contains name then
        throw (IO.userError s!"refused definition entered the environment: {name}")
      refusals := refusals.push (expected, error)
    if initialEnv.contains name then
      throw (IO.userError s!"definition name present in initial snapshot: {name}")
    for (acceptedName, acceptedType, acceptedValue) in inserted do
      let some (.defnInfo entry) := env.find? acceptedName
        | throw (IO.userError s!"accepted definition missing: {acceptedName}")
      unless entry.type == acceptedType && entry.value == acceptedValue && entry.levelParams.isEmpty do
        throw (IO.userError s!"accepted definition changed: {acceptedName}")
    let .ok (t, v) := Prod.mk <$> encode type <*> encode value
      | throw (IO.userError "definition encoding failed")
    definitionRows := definitionRows.push s!"def\t{name}\t{t}\t{v}\t{expected.tag}"
  let term := Expr.const id []
  let expected := pi prop prop
  let .ok kind := Kernel.check env {} expected | throw (IO.userError "expected type failed to check")
  let .ok (.sort _) := Kernel.whnf env {} kind | throw (IO.userError "expected expression is not a type")
  let .ok actual := Kernel.check env {} term | throw (IO.userError "lookup failed")
  let .ok true := Kernel.isDefEq env {} actual expected
    | throw (IO.userError "lookup type disagrees")
  let .ok (term, expected) := Prod.mk <$> encode term <*> encode expected
    | throw (IO.userError "lookup encoding failed")
  definitionRows := definitionRows.push s!"infer\t{term}\t{expected}"
  checkDefinitionControls env refusals
  IO.FS.writeFile (out ++ ".defs") (String.intercalate "\n" definitionRows.toList ++ "\n")
