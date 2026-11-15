import Lean

/-!
Strict supplementary replay of the seven transparent-definition-v1 rows.
The imported generator and fixture remain byte-identical. Checked Lean kernel
insertion supplies finite reference observations; this checker does not grant
the OCaml environment declaration or theorem admission authority.
-/

open Lean

namespace DefinitionRefusals

inductive Refusal where
  | duplicate
  | unknownConstant
  | declarationMismatch
  | typeExpected
deriving BEq

def classify : Kernel.Exception → Option Refusal
  | .alreadyDeclared .. => some .duplicate
  | .unknownConstant .. => some .unknownConstant
  | .declTypeMismatch .. => some .declarationMismatch
  | .typeExpected .. => some .typeExpected
  | _ => none

def exceptionName : Kernel.Exception → String
  | .unknownConstant .. => "unknownConstant"
  | .alreadyDeclared .. => "alreadyDeclared"
  | .declTypeMismatch .. => "declTypeMismatch"
  | .declHasMVars .. => "declHasMVars"
  | .declHasFVars .. => "declHasFVars"
  | .funExpected .. => "funExpected"
  | .typeExpected .. => "typeExpected"
  | .letTypeMismatch .. => "letTypeMismatch"
  | .exprTypeMismatch .. => "exprTypeMismatch"
  | .appTypeMismatch .. => "appTypeMismatch"
  | .invalidProj .. => "invalidProj"
  | .thmTypeIsNotProp .. => "thmTypeIsNotProp"
  | .other _ => "other"
  | .deterministicTimeout => "deterministicTimeout"
  | .excessiveMemory => "excessiveMemory"
  | .deepRecursion => "deepRecursion"
  | .interrupted => "interrupted"

def simpleName (text : String) : Except String Name := do
  if text.isEmpty || !(text.toList.all fun c => c.isAlphanum || c == '_') then
    throw "invalid simple constant name"
  return Name.mkSimple text

def natural (digits : List Char) : Except String Nat := do
  if digits.isEmpty || !(digits.all Char.isDigit) then
    throw "invalid nonnegative decimal"
  let some n := (String.ofList digits).toNat?
    | throw "invalid nonnegative decimal"
  return n

-- These are replay resource bounds, not restrictions asserted about Lean.
def parse : Nat → List String → Except String (Expr × List String)
  | 0, _ => throw "expression exceeds replay depth limit"
  | allowance + 1, tokens => do
    match tokens with
    | tag :: rest =>
      if tag == "a" || tag == "l" || tag == "p" then
        let (first, rest) ← parse allowance rest
        let (second, rest) ← parse allowance rest
        let term := if tag == "a" then Expr.app first second
          else if tag == "l" then Expr.lam `x first second .default
          else Expr.forallE `x first second .default
        return (term, rest)
      else if tag == "t" then
        let (type, rest) ← parse allowance rest
        let (value, rest) ← parse allowance rest
        let (body, rest) ← parse allowance rest
        return (Expr.letE `x type value body false, rest)
      else
        match tag.toList with
        | 'v' :: digits => return (.bvar (← natural digits), rest)
        | 's' :: digits =>
          let level ← natural digits
          if level > 128 then throw "universe exceeds replay resource bound"
          return (.sort (Level.ofNat level), rest)
        | 'c' :: name => return (.const (← simpleName (String.ofList name)) [], rest)
        | _ => throw "invalid expression token"
    | [] => throw "missing expression token"

def decode (label text : String) : IO Expr := do
  match parse 128 (text.splitOn " ") with
  | .ok (term, []) =>
    if term.hasLooseBVars then throw (IO.userError s!"{label}: expression is not closed")
    return term
  | .ok (_, _ :: _) => throw (IO.userError s!"{label}: trailing expression tokens")
  | .error message => throw (IO.userError s!"{label}: {message}")

structure DefinitionCase where
  name : String
  typeText : String
  valueText : String
  refusal : Option Refusal

-- Order is significant: the third row deliberately repeats the first name.
def cases : List DefinitionCase := [
  ⟨"ocamlRefAlias", "s1", "s0", none⟩,
  ⟨"ocamlRefId", "p cocamlRefAlias cocamlRefAlias", "l cocamlRefAlias v0", none⟩,
  ⟨"ocamlRefAlias", "s1", "s0", some .duplicate⟩,
  ⟨"ocamlRefMissing", "s1", "cocamlRefMissing", some .unknownConstant⟩,
  ⟨"ocamlRefMismatch", "s1", "s1", some .declarationMismatch⟩,
  ⟨"ocamlRefNonType", "l s1 v0", "s0", some .typeExpected⟩
]

def corpusNames : List String :=
  ["ocamlRefAlias", "ocamlRefId", "ocamlRefMissing", "ocamlRefMismatch", "ocamlRefNonType"]

def checkInference (env : Environment) (label : String) (term expected : Expr) : IO Unit := do
  let actual ← match Kernel.check env {} term with
    | .ok actual => pure actual
    | .error error => throw (IO.userError s!"{label}: inference failed with {exceptionName error}")
  match Kernel.check env {} expected with
  | .error error => throw (IO.userError s!"{label}: expected type failed with {exceptionName error}")
  | .ok kind =>
    match Kernel.whnf env {} kind with
    | .ok (.sort _) => pure ()
    | .ok _ => throw (IO.userError s!"{label}: expected expression is not a type")
    | .error error => throw (IO.userError s!"{label}: expected sort failed with {exceptionName error}")
  match Kernel.isDefEq env {} actual expected with
  | .ok true => pure ()
  | .ok false => throw (IO.userError s!"{label}: inferred type disagrees")
  | .error error => throw (IO.userError s!"{label}: type comparison failed with {exceptionName error}")

def requireAbsent (env : Environment) (names : List String) : IO Unit := do
  for name in names do
    if env.contains (Name.mkSimple name) then
      throw (IO.userError s!"unexpected environment binding: {name}")

def checkAcceptedBindings (env : Environment) (accepted : Nat) : IO Unit := do
  for fixture in cases.take accepted do
    let type ← decode (fixture.name ++ " retained type") fixture.typeText
    let value ← decode (fixture.name ++ " retained value") fixture.valueText
    let name := Name.mkSimple fixture.name
    match env.find? name with
    | some (.defnInfo entry) =>
      unless entry.type == type && entry.value == value && entry.levelParams.isEmpty do
        throw (IO.userError s!"accepted binding changed: {fixture.name}")
    | _ => throw (IO.userError s!"accepted definition missing: {fixture.name}")
    -- Usability, as well as stored syntax, must survive each refused insertion.
    checkInference env (fixture.name ++ " retained inference") (.const name []) type
  requireAbsent env ["ocamlRefMissing", "ocamlRefMismatch", "ocamlRefNonType"]

def classifierControls : IO Nat := do
  let controls : List Kernel.Exception := [
    .deterministicTimeout, .excessiveMemory, .deepRecursion, .interrupted,
    .other "injected internal failure"
  ]
  for error in controls do
    unless classify error == none do
      throw (IO.userError s!"classifier accepted {exceptionName error}")
  return controls.length

def replay (path : System.FilePath) : IO Unit := do
  let contents ← IO.FS.readFile path
  unless contents.endsWith "\n" do
    throw (IO.userError "definition-v1 corpus must end with LF")
  let rows := (contents.splitOn "\n").dropLast
  unless rows.length == 7 do
    throw (IO.userError "definition-v1 corpus must contain exactly seven rows")
  initSearchPath (← findSysroot)
  let initial ← importModules #[{module := `Init}] {}
  requireAbsent initial corpusNames
  let mut env := initial
  let mut accepted := 0
  let mut refused := 0
  for (row, fixture) in rows.take 6 |>.zip cases do
    let verdict := if fixture.refusal.isSome then "false" else "true"
    unless row.splitOn "\t" == ["def", fixture.name, fixture.typeText, fixture.valueText, verdict] do
      throw (IO.userError s!"definition-v1 row order, identity, payload or verdict mismatch: {fixture.name}")
    let type ← decode (fixture.name ++ " type") fixture.typeText
    let value ← decode (fixture.name ++ " value") fixture.valueText
    let declaration := Declaration.defnDecl {
      name := Name.mkSimple fixture.name, levelParams := [], type, value,
      hints := .abbrev, safety := .safe
    }
    -- This is checked insertion. The heartbeat/recursion limits match the
    -- imported generator; any resource error fails rather than counting false.
    match env.addDeclCore 100000 1000 declaration none, fixture.refusal with
    | .ok next, none =>
      env := next
      accepted := accepted + 1
    | .error error, some required =>
      unless classify error == some required do
        throw (IO.userError s!"{fixture.name}: unexpected Lean error {exceptionName error}")
      refused := refused + 1
    | .ok _, some _ => throw (IO.userError s!"{fixture.name}: unexpected Lean definition success")
    | .error error, none =>
      throw (IO.userError s!"{fixture.name}: unexpected Lean definition failure {exceptionName error}")
    checkAcceptedBindings env accepted
    requireAbsent initial corpusNames
  let [last] := rows.drop 6 | throw (IO.userError "missing final inference row")
  unless last.splitOn "\t" == ["infer", "cocamlRefId", "p s0 s0"] do
    throw (IO.userError "definition-v1 final inference row mismatch")
  checkInference env "final inference" (← decode "final term" "cocamlRefId")
    (← decode "final expected type" "p s0 s0")
  unless accepted == 2 && refused == 4 do
    throw (IO.userError "unexpected definition-v1 result inventory")
  let controls ← classifierControls
  IO.println s!"Strict Lean definition replay passed: 7 rows ({accepted} definitions accepted, {refused} exact semantic refusals, 1 inference), {refused} environment-retention checks, initial corpus bindings absent, {controls} classifier controls"

end DefinitionRefusals

def main (args : List String) : IO Unit := do
  let [path] := args
    | throw (IO.userError "usage: lean --run oracles/ValidateDefinitionRefusals.lean conformance/generated.tsv.defs")
  DefinitionRefusals.replay path
