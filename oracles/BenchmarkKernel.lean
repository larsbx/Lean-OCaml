import Lean

/-!
Direct, synchronous Lean kernel baseline for the reference-definition benchmark.

Input is the same DAG-expression TSV consumed by the OCaml driver. Node IDs
preserve the same expression sharing in both implementations. Parsing,
declaration construction, environment setup, the refusal control, and result
validation are outside timing. Each interval includes the complete ordered fold
of checked declaration insertions into a fresh copy of the empty environment.
No elaboration, tactic execution, module import, or source compilation is timed.
-/

open Lean

namespace KernelBenchmark

def failure (message : String) : IO α :=
  throw (IO.userError s!"kernel benchmark: {message}")

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

def readNatural (text : String) : IO Nat := do
  match natural text.toList with
  | .ok value => return value
  | .error message => failure message

def readName (text : String) : IO Name := do
  match simpleName text with
  | .ok name => return name
  | .error message => failure message

def node (nodes : Array Expr) (text : String) : IO Expr := do
  let index ← readNatural text
  match nodes[index]? with
  | some expression => return expression
  | none => failure "node reference must point to an earlier node"

def decodeNode (nodes : Array Expr) (fields : List String) : IO Expr := do
  match fields with
  | ["s", universeText] =>
    let level ← readNatural universeText
    if level > 128 then failure "universe exceeds parser resource bound"
    return .sort (.ofNat level)
  | ["v", index] => return .bvar (← readNatural index)
  | ["c", name] => return .const (← readName name) []
  | ["a", left, right] => return .app (← node nodes left) (← node nodes right)
  | ["l", left, right] => return .lam `x (← node nodes left) (← node nodes right) .default
  | ["p", left, right] => return .forallE `x (← node nodes left) (← node nodes right) .default
  | ["t", type, value, body] =>
    return .letE `x (← node nodes type) (← node nodes value) (← node nodes body) false
  | _ => failure "unknown node tag or invalid node arity"

def readDeclarations (path : System.FilePath) (allowDuplicateNames := false) : IO (Array Declaration) := do
  let contents ← IO.FS.readFile path
  unless contents.endsWith "\n" do failure "fixture must end with LF"
  let header :: rows := (contents.splitOn "\n").dropLast
    | failure "missing fixture header"
  unless header == "lean-ocaml-benchmark-dag-v1" do failure "incorrect fixture schema"
  let mut nodes : Array Expr := #[]
  let mut declarations := #[]
  let mut names : NameSet := {}
  for row in rows do
    match row.splitOn "\t" with
    | "n" :: indexText :: fields =>
      unless declarations.isEmpty do failure "node rows must precede definitions"
      let index ← readNatural indexText
      unless index == nodes.size do failure "node indexes must be contiguous from zero"
      if nodes.size >= 1000000 then failure "too many fixture nodes"
      nodes := nodes.push (← decodeNode nodes fields)
    | ["d", nameText, typeText, valueText] =>
      let name ← readName nameText
      if !allowDuplicateNames && names.contains name then failure s!"duplicate fixture name: {name}"
      names := names.insert name
      let type ← node nodes typeText
      let value ← node nodes valueText
      if type.hasLooseBVars || value.hasLooseBVars then
        failure s!"definition must be closed: {name}"
      declarations := declarations.push (.defnDecl {
        name, levelParams := [], type, value, hints := .abbrev, safety := .safe
      })
    | _ => failure "invalid fixture row"
  if declarations.isEmpty || declarations.size > 4096 then
    failure "fixture definition count must be in 1..4096"
  return declarations

-- Synchronous checked insertion, explicitly including doCheck=true. Resource
-- refusals are benchmark failures; they are never reported as valid results.
def checkBatch (initial : Environment) (declarations : Array Declaration) : IO Environment := do
  let mut env := initial
  for declaration in declarations do
    match env.addDeclCore 10000000 1000 declaration none true with
    | .ok next => env := next
    | .error error => failure s!"checked insertion failed: {exceptionName error}"
  return env

def validate (initial env : Environment) (declarations : Array Declaration) : IO Unit := do
  for declaration in declarations do
    let .defnDecl definition := declaration | failure "unexpected declaration kind"
    if initial.contains definition.name then failure "initial environment changed"
    match env.find? definition.name with
    | some (.defnInfo actual) =>
      unless actual.type == definition.type && actual.value == definition.value &&
          actual.levelParams.isEmpty && actual.safety == .safe do
        failure s!"stored definition changed: {definition.name}"
    | _ => failure s!"missing checked definition: {definition.name}"
    let inferred ← match Kernel.check env {} (.const definition.name []) with
      | .ok inferred => pure inferred
      | .error error => failure s!"post-check inference: {exceptionName error}"
    match Kernel.isDefEq env {} inferred definition.type with
    | .ok true => pure ()
    | .ok false => failure s!"post-check type mismatch: {definition.name}"
    | .error error => failure s!"post-check conversion: {exceptionName error}"

def refusalControl (initial : Environment) : IO Unit := do
  let declaration := Declaration.defnDecl {
    name := `benchmarkInvalidSort,
    levelParams := [], type := .sort (.ofNat 1), value := .sort (.ofNat 1),
    hints := .abbrev, safety := .safe
  }
  match initial.addDeclCore 10000000 1000 declaration none true with
  | .error (.declTypeMismatch ..) => pure ()
  | .error error => failure s!"invalid control returned {exceptionName error}"
  | .ok _ => failure "invalid control accepted: checking is not active"
  if initial.contains `benchmarkInvalidSort then failure "refusal changed initial environment"

-- Untimed migration differential oracle. Only designated semantic exceptions
-- are observations; resource/internal exceptions abort the check. A refused
-- insertion retains the previous environment, so subsequent rows exercise it.
def checkMigration (path : System.FilePath) : IO Unit := do
  let declarations ← readDeclarations path true
  let mut env ← mkEmptyEnvironment 0
  let mut outcomes : Array Json := #[]
  let mut accepted := 0
  for declaration in declarations do
    let .defnDecl definition := declaration | failure "unexpected declaration kind"
    let outcome ← match env.addDeclCore 10000000 1000 declaration none true with
      | .ok next => do
        validate env next #[declaration]
        env := next
        accepted := accepted + 1
        pure "accepted"
      | .error error => do
        let name := exceptionName error
        unless ["unknownConstant", "alreadyDeclared", "declTypeMismatch", "funExpected",
                "typeExpected", "letTypeMismatch", "exprTypeMismatch", "appTypeMismatch"].contains name do
          failure s!"migration oracle inconclusive: {name}"
        pure name
    outcomes := outcomes.push (Json.mkObj [
      ("name", toJson definition.name.toString), ("outcome", toJson outcome)])
  IO.println (Json.mkObj [
    ("engine", toJson "lean-kernel"), ("status", toJson "checked"),
    ("outcomes", toJson outcomes), ("accepted", toJson accepted),
    ("acceptance_authority", toJson false), ("trust_level", toJson (0 : Nat)),
    ("checked_insertion", toJson true)]).compress

def run (path : System.FilePath) (iterations : Nat) : IO Unit := do
  let declarations ← readDeclarations path
  let initial ← mkEmptyEnvironment 0
  refusalControl initial
  -- One untimed warm-up exercises the exact complete workload and validates it.
  let warmup ← checkBatch initial declarations
  validate initial warmup declarations
  let mut elapsed := 0
  for _ in [:iterations] do
    let start ← IO.monoNanosNow
    let result ← checkBatch initial declarations
    let stop ← IO.monoNanosNow
    if stop <= start then failure "non-positive monotonic interval"
    elapsed := elapsed + (stop - start)
    validate initial result declarations
  let output := Json.mkObj [
    ("engine", toJson "lean-kernel"),
    ("status", toJson "passed"),
    ("iterations", toJson iterations),
    ("definitions", toJson declarations.size),
    ("elapsed_ns", toJson elapsed),
    ("per_batch_ns", toJson (elapsed / iterations)),
    ("validated_batches", toJson iterations),
    ("refusal_controls", toJson (1 : Nat)),
    ("trust_level", toJson (0 : Nat)),
    ("checked_insertion", toJson true)
  ]
  IO.println output.compress

end KernelBenchmark

def main (args : List String) : IO Unit := do
  if let ["--check", path] := args then
    KernelBenchmark.checkMigration path
    return
  let [path, iterationsText] := args
    | KernelBenchmark.failure "usage: benchmark-kernel fixture.tsv iterations"
  let some iterations := iterationsText.toNat?
    | KernelBenchmark.failure "iterations must be an integer"
  if iterations == 0 || iterations > 100000 then
    KernelBenchmark.failure "iterations must be in 1..100000"
  KernelBenchmark.run path iterations
