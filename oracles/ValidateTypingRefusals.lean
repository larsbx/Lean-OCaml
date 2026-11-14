import Lean

/-!
Supplementary replay of the exact closed-term typing-v1 inventory. This keeps
the imported generator and TSV bytes unchanged while distinguishing semantic
rejections from kernel resource/internal errors. These are finite observations,
not a proof of OCaml typing or full Lean kernel correspondence.
-/

open Lean

namespace TypingRefusals

inductive Refusal where
  | functionExpected
  | typeExpected
  | applicationMismatch
  | letMismatch
deriving BEq

def classify : Kernel.Exception → Option Refusal
  | .funExpected .. => some .functionExpected
  | .typeExpected .. => some .typeExpected
  | .appTypeMismatch .. => some .applicationMismatch
  | .letTypeMismatch .. => some .letMismatch
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

def wrongBinderIds : List String :=
  (List.range 9).map fun depth => s!"depth-{depth}-wrong-binder"

def positiveIds : List String :=
  ["sort", "pi-max", "pi-impredicative", "identity", "dependent-identity",
   "dependent-application", "zeta-dependent-type", "conversion-in-argument"] ++
  (List.range 9).flatMap fun depth => [s!"depth-{depth}-beta", s!"depth-{depth}-zeta"]

def refusalIds : List (String × Refusal) :=
  [("nonfunction", .functionExpected),
   ("argument-mismatch", .applicationMismatch),
   ("let-mismatch", .letMismatch),
   ("binder-not-type", .typeExpected),
   ("pi-body-not-type", .typeExpected)] ++
  wrongBinderIds.map fun id => (id, .applicationMismatch)

def natural (digits : List Char) : Except String Nat := do
  if digits.isEmpty || !(digits.all Char.isDigit) then
    throw "invalid nonnegative decimal"
  let some n := (String.ofList digits).toNat?
    | throw "invalid nonnegative decimal"
  return n

-- A decreasing depth allowance bounds parsing independently of kernel checks.
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
          -- Universe numerals expand to successor chains in Lean. This is a
          -- replay resource bound, not a restriction asserted about Lean.
          if level > 128 then throw "universe exceeds replay resource bound"
          return (.sort (Level.ofNat level), rest)
        | _ => throw "invalid expression token"
    | [] => throw "missing expression token"

def decode (label text : String) : IO Expr := do
  match parse 128 (text.splitOn " ") with
  | .ok (term, []) =>
    if term.hasLooseBVars then throw (IO.userError s!"{label}: expression is not closed")
    return term
  | .ok (_, _ :: _) => throw (IO.userError s!"{label}: trailing expression tokens")
  | .error message => throw (IO.userError s!"{label}: {message}")

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
    throw (IO.userError "typing-v1 corpus must end with LF")
  let rows := (contents.splitOn "\n").dropLast
  unless rows.length == 40 do
    throw (IO.userError "typing-v1 corpus must contain exactly 40 rows")
  initSearchPath (← findSysroot)
  let env ← importModules #[{module := `Init}] {}
  let knownIds := positiveIds ++ refusalIds.map Prod.fst
  let mut seen : List String := []
  let mut accepted := 0
  let mut refused := 0
  let mut wrongBinders := 0
  for row in rows do
    let ["type", id, input, expected] := row.splitOn "\t"
      | throw (IO.userError "invalid typing-v1 row")
    unless knownIds.contains id do
      throw (IO.userError s!"unknown typing-v1 ID: {id}")
    if seen.contains id then throw (IO.userError s!"duplicate typing-v1 ID: {id}")
    seen := id :: seen
    let term ← decode id input
    match refusalIds.find? (fun entry => entry.1 == id) with
    | some (_, required) =>
      unless expected == "refused" do
        throw (IO.userError s!"{id}: expected an explicit refusal")
      match Kernel.check env {} term with
      | .ok _ => throw (IO.userError s!"{id}: unexpected Lean typing success")
      | .error error =>
        unless classify error == some required do
          throw (IO.userError s!"{id}: unexpected Lean error {exceptionName error}")
      refused := refused + 1
      if wrongBinderIds.contains id then wrongBinders := wrongBinders + 1
    | none =>
      if expected == "refused" then
        throw (IO.userError s!"{id}: positive row cannot expect refusal")
      let expectedType ← decode (id ++ " expected type") expected
      let actual ← match Kernel.check env {} term with
        | .ok actual => pure actual
        | .error error =>
          throw (IO.userError s!"{id}: Lean typing failed with {exceptionName error}")
      -- Check the supplied expected type independently before comparison.
      match Kernel.check env {} expectedType with
      | .error error =>
        throw (IO.userError s!"{id}: expected type failed with {exceptionName error}")
      | .ok kind =>
        match Kernel.whnf env {} kind with
        | .ok (.sort _) => pure ()
        | .ok _ => throw (IO.userError s!"{id}: expected expression is not a type")
        | .error error =>
          throw (IO.userError s!"{id}: expected sort failed with {exceptionName error}")
      match Kernel.isDefEq env {} actual expectedType with
      | .ok true => pure ()
      | .ok false => throw (IO.userError s!"{id}: inferred type disagrees")
      | .error error =>
        throw (IO.userError s!"{id}: type comparison failed with {exceptionName error}")
      accepted := accepted + 1
  for id in knownIds do
    unless seen.contains id do throw (IO.userError s!"missing typing-v1 ID: {id}")
  unless accepted == 26 && refused == 14 && wrongBinders == 9 do
    throw (IO.userError "unexpected typing-v1 result inventory")
  let controls ← classifierControls
  IO.println s!"Strict Lean typing replay passed: 40 rows ({accepted} accepted, {refused} semantic refusals; {wrongBinders} appTypeMismatch wrong-binder cases), {controls} classifier controls"

end TypingRefusals

def main (args : List String) : IO Unit := do
  let [path] := args
    | throw (IO.userError "usage: lean --run oracles/ValidateTypingRefusals.lean conformance/generated.tsv.types")
  TypingRefusals.replay path
