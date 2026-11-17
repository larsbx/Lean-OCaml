(* Observational benchmark of the non-authoritative definition batch API.
   Timings include planning, checking, domain startup/join, and merging.
   Fixture construction, full major collection and comparison are outside the
   timed interval. No speedup threshold is an acceptance condition. *)
open Conversion

let scale = ref 1
let repetitions = ref 3
let fuel = 10_000_000

let fail message =
  prerr_endline ("benchmark: " ^ message);
  exit 1

let error_name = function
  | Invalid_scope -> "Invalid_scope"
  | Invalid_universe -> "Invalid_universe"
  | Limit_exceeded -> "Limit_exceeded"
  | Height_limit -> "Height_limit"
  | Index_overflow -> "Index_overflow"
  | Expected_sort -> "Expected_sort"
  | Expected_function -> "Expected_function"
  | Type_mismatch -> "Type_mismatch"
  | Unknown_constant -> "Unknown_constant"
  | Duplicate_definition -> "Duplicate_definition"
  | Invalid_name -> "Invalid_name"

let batch_error = function
  | Definition_batch.Invalid_workers -> "Invalid_workers"
  | Definition_batch.Too_many_definitions -> "Too_many_definitions"
  | Definition_batch.Invalid_name index -> "Invalid_name " ^ string_of_int index
  | Definition_batch.Duplicate_name name -> "Duplicate_name " ^ name
  | Definition_batch.Dependency_scan_failed (name, error) ->
      "Dependency_scan_failed " ^ name ^ ": " ^ error_name error
  | Definition_batch.Dependency_cycle names ->
      "Dependency_cycle " ^ String.concat "," names
  | Definition_batch.Check_failed failures ->
      "Check_failed " ^ String.concat "; "
        (List.map (fun (name, error) -> name ^ ": " ^ error_name error) failures)
  | Definition_batch.Worker_failed _ -> "Worker_failed"
  | Definition_batch.Merge_failed _ -> "Merge_failed"

let unwrap = function
  | Ok report -> report
  | Error error -> fail (batch_error error)

(* A beta identity at the specified type. Repeated applications remain well
   typed; numeric universe sorts are used exactly as in the reference API. *)
let rec beta_chain count domain expression =
  if count = 0 then expression
  else beta_chain (count - 1) domain
      (App (Lam (domain, Var 0), expression))

let rec type_tree depth leaf =
  if depth = 0 then leaf
  else
    let child = type_tree (depth - 1) leaf in
    Pi (child, child)

let name prefix index = Printf.sprintf "%s_%04d" prefix index

let workload ~chain count =
  let prefix = if chain then "chain" else "wide" in
  (* Expanded value: 9,215 nodes, height 15. Annotation: 65 nodes,
     height 18. Shared public syntax is traversed by the checked importer. *)
  let value = type_tree 9 (beta_chain 4 (Sort 1) (Sort 0)) in
  let ty = beta_chain 16 (Sort 2) (Sort 1) in
  List.init count (fun index ->
    let value =
      if chain && index > 0 then Const (name prefix (index - 1)) else value
    in
    Definition_batch.{ name = name prefix index; ty; value; fuel })

let check workers definitions =
  Definition_batch.run ~workers ~scan_fuel:1_000_000 ~merge_fuel:1_000_000
    empty_environment definitions |> unwrap

let verify_reference definitions expected_waves report =
  if report.Definition_batch.waves <> expected_waves then
    fail "unexpected dependency waves in sequential reference";
  List.iter (fun (definition : Definition_batch.definition) ->
    match infer_in ~fuel report.environment (Const definition.name) with
    | Ok (Sort 1) -> ()
    | Ok _ -> fail ("unexpected inferred type for " ^ definition.name)
    | Error error -> fail (definition.name ^ ": " ^ error_name error)) definitions

let verify_same reference report =
  if report.Definition_batch.waves <> reference.Definition_batch.waves then
    fail "dependency waves differ from one-worker reference";
  (* These abstract environments contain immutable checked data. Structural
     equality here compares all bindings, including their checked values,
     rather than checking only the inferred types of the final names. *)
  if report.environment <> reference.environment then
    fail "environment differs from one-worker reference"

let process_cpu () =
  let times = Unix.times () in
  times.Unix.tms_utime +. times.Unix.tms_stime

let measure ~workers definitions reference =
  let wall_total = ref 0.0 in
  let cpu_total = ref 0.0 in
  for _ = 1 to !repetitions do
    Gc.full_major ();
    let cpu_start = process_cpu () in
    let wall_start = Unix.gettimeofday () in
    let report = check workers definitions in
    let wall_elapsed = Unix.gettimeofday () -. wall_start in
    let cpu_elapsed = process_cpu () -. cpu_start in
    if wall_elapsed <= 0.0 || cpu_elapsed < 0.0 then
      fail "non-positive wall interval or backwards process CPU clock";
    verify_same reference report;
    wall_total := !wall_total +. wall_elapsed;
    cpu_total := !cpu_total +. cpu_elapsed
  done;
  (!wall_total /. float_of_int !repetitions,
   !cpu_total /. float_of_int !repetitions)

let run_workload ~chain count =
  let label = if chain then "chain" else "wide" in
  let definitions = workload ~chain count in
  let names = List.map (fun (d : Definition_batch.definition) -> d.name) definitions in
  let expected_waves = if chain then List.map (fun n -> [n]) names else [names] in
  (* One untimed run supplies the complete comparison environment and warms
     this workload. Every timed result, including workers=1, is checked. *)
  let reference = check 1 definitions in
  verify_reference definitions expected_waves reference;
  let sequential_wall = ref 0.0 in
  List.iter (fun workers ->
    let wall, cpu = measure ~workers definitions reference in
    if workers = 1 then sequential_wall := wall;
    Printf.printf "%s\t%d\t%d\t%d\t%d\t%d\t%.6f\t%.6f\t%.3f\t%.3f\n%!"
      label workers count !repetitions (count * !repetitions)
      (List.length reference.waves) wall cpu (!sequential_wall /. wall)
      (cpu /. wall)) [1; 2; 4; 8]

let () =
  Arg.parse
    [ "--scale", Arg.Set_int scale,
        "N  multiply 32 definitions by N (1..4; default 1)";
      "--repetitions", Arg.Set_int repetitions,
        "N  timed repetitions per worker count (1..20; default 3)" ]
    (fun argument -> raise (Arg.Bad ("unexpected argument: " ^ argument)))
    "benchmark [--scale 1..4] [--repetitions 1..20]";
  if !scale < 1 || !scale > 4 then fail "--scale must be in 1..4";
  if !repetitions < 1 || !repetitions > 20 then
    fail "--repetitions must be in 1..20";
  Printf.printf "# OCaml %s; bytecode; runtime recommended domains=%d\n%!"
    Sys.ocaml_version (Domain.recommended_domain_count ());
  print_endline "# Means per batch; checked_jobs counts all timed repetitions.";
  print_endline "# Full major collection, fixture construction and result comparison are outside timing.";
  print_endline "# Domain startup/join and dependency planning are included. Speedup is observational.";
  print_endline "workload\tworkers\tdefinitions\trepetitions\tchecked_jobs\twaves\twall_s\tcpu_s\tspeedup\tcpu_per_wall";
  let count = 32 * !scale in
  run_workload ~chain:false count;
  run_workload ~chain:true count;
  print_endline "# Every timed environment and wave sequence matched the one-worker reference."
