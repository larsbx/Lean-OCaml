(** Transactional reference-definition checking in deterministic dependency
    waves. This does not admit Lean declarations or certify theorems. *)
type definition = {
  name : string;
  ty : Conversion.expr;
  value : Conversion.expr;
  fuel : int;
}

type error =
  | Invalid_workers
  | Too_many_definitions
  | Invalid_name of int
  | Duplicate_name of string
  | Dependency_scan_failed of string * Conversion.error
  | Dependency_cycle of string list
  | Check_failed of (string * Conversion.error) list
  | Worker_failed of Bounded_parallel.error
  | Merge_failed of Conversion.merge_error

type report = {
  environment : Conversion.environment;
  waves : string list list;
}

(** At most 4096 definitions and 1..64 workers. Dependencies are derived from
    all constant occurrences in both type and value, including erased children.
    Acyclic forward references are allowed by this batch contract. References
    outside the batch are resolved by [Conversion.define] against the base.

    Planning charges at most [scan_fuel] expanded expression nodes per definition and
    enforces [Conversion.max_height]. Cycles are refused before checking; the
    reported residual includes declarations transitively blocked by a cycle.
    Ready definitions in each wave retain input order and share one snapshot.
    Each has its own [fuel]; each wave has its own [merge_fuel].

    On any failure no resulting environment is returned and the input snapshot
    remains unchanged. [Check_failed] lists all semantic/resource refusals in
    the first failing wave, in input order. Later waves do not run. Worker
    exceptions remain execution failures, never semantic refusal evidence.

    One-worker execution uses these same waves and snapshots. Its outcomes,
    including budget refusals, are the sequential reference for this API;
    an arbitrary ordered fold of [Conversion.define] has different lookup costs.
    Identical physical type/value pairs in one wave may share successful
    checking work; every name and budget remains independently checked.
    Constant-free annotation evidence may cross joined waves inside this call.
    No checking cache survives a later [run] call. Worker groups are created
    and joined per wave, not retained between waves.
    All input data must remain immutable during execution. *)
val run :
  workers:int -> scan_fuel:int -> merge_fuel:int -> Conversion.environment ->
  definition list -> (report, error) result
