(* Executable observations for the reference batch API. These controls do not
   prove Lean kernel compatibility or confer declaration-admission authority. *)
module C = Conversion
module P = Bounded_parallel
module B = Definition_batch

let fuel = 1_000_000
let controls = ref 0
let assertions = ref 0
let generated_cases = ref 0

let check label condition =
  incr assertions;
  if not condition then failwith label

let expect_error label expected result =
  check label (match result with Error actual -> actual = expected | Ok _ -> false)

let unwrap label = function
  | Ok value -> value
  | Error _ -> failwith (label ^ ": unexpected refusal")

let control label action =
  action label;
  incr controls

let definition ?(work = fuel) name ty value : B.definition =
  { name; ty; value; fuel = work }

let alias ?(work = fuel) name = definition ~work name (C.Sort 1) (C.Sort 0)

let identity name domain =
  definition name (C.Pi (C.Const domain, C.Const domain))
    (C.Lam (C.Const domain, C.Var 0))

let define env name ty value =
  unwrap ("prepare " ^ name) (C.define ~fuel env ~name ~ty ~value)

let infer env name = C.infer_in ~fuel env (C.Const name)

let run ?(scan_fuel = fuel) ?(merge_fuel = fuel) workers base jobs =
  B.run ~workers ~scan_fuel ~merge_fuel base jobs

let observe_report label expected_waves expected_types report =
  check (label ^ ": exact dependency waves") (report.B.waves = expected_waves);
  List.iter (fun (name, ty) ->
    check (label ^ ": inferred type of " ^ name)
      (infer report.B.environment name = Ok ty)) expected_types

let compare_reports label expected_types left right =
  check (label ^ ": same waves") (left.B.waves = right.B.waves);
  check (label ^ ": identical complete checked environments")
    (left.B.environment = right.B.environment);
  List.iter (fun (name, expected) ->
    let sequential = infer left.B.environment name in
    let concurrent = infer right.B.environment name in
    check (label ^ ": sequential observation " ^ name) (sequential = Ok expected);
    check (label ^ ": parallel observation " ^ name) (concurrent = sequential))
    expected_types

let merge_controls () =
  let empty = C.empty_environment in
  let base = define empty "Base" (C.Sort 1) (C.Sort 0) in
  let a = define base "A" (C.Sort 1) (C.Const "Base") in
  let b = define base "B" (C.Sort 2) (C.Sort 1) in
  control "checked sibling merge" (fun label ->
    let merged = unwrap label (C.merge_checked_branches ~fuel ~base [a; b]) in
    check (label ^ ": first expanded value") (infer merged "A" = Ok (C.Sort 1));
    check (label ^ ": second value") (infer merged "B" = Ok (C.Sort 2));
    check (label ^ ": base retained") (infer merged "Base" = Ok (C.Sort 1));
    check (label ^ ": base has no A") (infer base "A" = Error C.Unknown_constant);
    check (label ^ ": first sibling has no B") (infer a "B" = Error C.Unknown_constant);
    check (label ^ ": empty snapshot retained") (infer empty "Base" = Error C.Unknown_constant));
  control "empty merge is identity" (fun label ->
    let merged = unwrap label (C.merge_checked_branches ~fuel ~base []) in
    check (label ^ ": original value") (infer merged "Base" = Ok (C.Sort 1));
    check (label ^ ": no invented value") (infer merged "A" = Error C.Unknown_constant));
  control "unchanged parent is not an extension" (fun label ->
    expect_error label C.Invalid_branch (C.merge_checked_branches ~fuel ~base [base]));
  control "empty environment is not an extension" (fun label ->
    expect_error label C.Invalid_branch (C.merge_checked_branches ~fuel ~base [empty]));
  control "extension must have exactly the checked parent" (fun label ->
    let equal_but_distinct_base = define empty "Base" (C.Sort 1) (C.Sort 0) in
    let wrong = define equal_but_distinct_base "Wrong" (C.Sort 1) (C.Sort 0) in
    expect_error label C.Invalid_branch (C.merge_checked_branches ~fuel ~base [wrong]));
  control "two additions do not masquerade as one branch" (fun label ->
    let twice = define a "Second" (C.Sort 1) (C.Const "A") in
    expect_error label C.Invalid_branch (C.merge_checked_branches ~fuel ~base [twice]));
  control "repeated branch is refused" (fun label ->
    expect_error label C.Duplicate_branch (C.merge_checked_branches ~fuel ~base [a; a]));
  control "independently checked duplicate names are refused" (fun label ->
    let another_a = define base "A" (C.Sort 2) (C.Sort 1) in
    expect_error label C.Duplicate_branch
      (C.merge_checked_branches ~fuel ~base [a; another_a]));
  control "zero merge fuel is a resource refusal" (fun label ->
    expect_error label C.Merge_limit_exceeded
      (C.merge_checked_branches ~fuel:0 ~base [a]));
  control "negative merge fuel is a resource refusal" (fun label ->
    expect_error label C.Merge_limit_exceeded
      (C.merge_checked_branches ~fuel:(-1) ~base [a]));
  control "cyclic branch list terminates with a refusal" (fun label ->
    let rec branches = a :: branches in
    expect_error label C.Duplicate_branch
      (C.merge_checked_branches ~fuel ~base branches));
  control "failed merge preserves all supplied snapshots" (fun label ->
    ignore (C.merge_checked_branches ~fuel ~base [a; b; a]);
    check (label ^ ": parent unchanged") (infer base "A" = Error C.Unknown_constant);
    check (label ^ ": A unchanged") (infer a "A" = Ok (C.Sort 1));
    check (label ^ ": B unchanged") (infer b "B" = Ok (C.Sort 2));
    check (label ^ ": A does not acquire B") (infer a "B" = Error C.Unknown_constant))

let dependency_controls () =
  let empty = C.empty_environment in
  let diamond = [
    alias "A"; alias "B";
    identity "L" "A"; identity "R" "B";
    definition "Join" (C.Pi (C.Const "A", C.Const "A"))
      (C.Lam (C.Const "A", C.App (C.Const "L", C.App (C.Const "R", C.Var 0))));
  ] in
  let expected_types = [
    "A", C.Sort 1; "B", C.Sort 1;
    "L", C.Pi (C.Sort 0, C.Sort 0);
    "R", C.Pi (C.Sort 0, C.Sort 0);
    "Join", C.Pi (C.Sort 0, C.Sort 0);
  ] in
  control "diamond uses immutable dependency waves" (fun label ->
    let sequential = unwrap label (run 1 empty diamond) in
    observe_report label [["A"; "B"]; ["L"; "R"]; ["Join"]]
      expected_types sequential;
    List.iter (fun workers ->
      let parallel = unwrap label (run workers empty diamond) in
      compare_reports (label ^ " workers=" ^ string_of_int workers)
        expected_types sequential parallel) [2; 4; 8];
    check (label ^ ": original environment unchanged")
      (infer empty "Join" = Error C.Unknown_constant));
  control "acyclic forward references are ordered by dependencies" (fun label ->
    let jobs = List.rev diamond in
    List.iter (fun workers ->
      observe_report label [["B"; "A"]; ["R"; "L"]; ["Join"]]
        expected_types (unwrap label (run workers empty jobs))) [1; 2; 4; 8]);
  control "equal-typed distinct values retain their names" (fun label ->
    let function_type = C.Pi (C.Sort 0, C.Sort 0) in
    let jobs = [alias "Propositions";
                definition "Functions" (C.Sort 1) function_type;
                identity "LeftId" "Propositions";
                identity "RightId" "Functions"] in
    let types = ["Propositions", C.Sort 1; "Functions", C.Sort 1;
                 "LeftId", C.Pi (C.Sort 0, C.Sort 0);
                 "RightId", C.Pi (function_type, function_type)] in
    let sequential = unwrap label (run 1 empty jobs) in
    observe_report label [["Propositions"; "Functions"]; ["LeftId"; "RightId"]]
      types sequential;
    List.iter (fun workers ->
      compare_reports label types sequential (unwrap label (run workers empty jobs)))
      [2; 4; 8]);
  control "wide independent wave retains every result" (fun label ->
    let jobs = List.init 32 (fun index -> alias ("Wide" ^ string_of_int index)) in
    let names = List.map (fun (job : B.definition) -> job.name) jobs in
    let types = List.map (fun name -> name, C.Sort 1) names in
    let sequential = unwrap label (run 1 empty jobs) in
    observe_report label [names] types sequential;
    List.iter (fun workers ->
      compare_reports label types sequential (unwrap label (run workers empty jobs))) [2; 4; 8]);
  control "dependent chain cannot advance early" (fun label ->
    let jobs = List.init 20 (fun index ->
      let name = "Chain" ^ string_of_int index in
      if index = 0 then alias name
      else definition name (C.Sort 1) (C.Const ("Chain" ^ string_of_int (index - 1)))) in
    let names = List.map (fun (job : B.definition) -> job.name) jobs in
    let expected = List.map (fun name -> name, C.Sort 1) names in
    List.iter (fun workers ->
      observe_report label (List.map (fun name -> [name]) names) expected
        (unwrap label (run workers empty jobs))) [1; 4]);
  control "dependencies in declared types are observed" (fun label ->
    let jobs = [definition "Typed" (C.Const "Universe") (C.Sort 0);
                definition "Universe" (C.Sort 2) (C.Sort 1)] in
    List.iter (fun workers ->
      observe_report label [["Universe"]; ["Typed"]]
        ["Universe", C.Sort 2; "Typed", C.Sort 1]
        (unwrap label (run workers empty jobs))) [1; 4]);
  control "dependencies in erased let values are observed" (fun label ->
    let jobs = [definition "Erases" (C.Sort 1)
                  (C.Let (C.Sort 1, C.Const "Used", C.Sort 0)); alias "Used"] in
    observe_report label [["Used"]; ["Erases"]]
      ["Used", C.Sort 1; "Erases", C.Sort 1]
      (unwrap label (run 4 empty jobs)));
  control "dependencies in erased let annotations are observed" (fun label ->
    let jobs = [definition "ErasesType" (C.Sort 1)
                  (C.Let (C.Const "Annotation", C.Sort 0, C.Sort 0));
                definition "Annotation" (C.Sort 2) (C.Sort 1)] in
    observe_report label [["Annotation"]; ["ErasesType"]]
      ["ErasesType", C.Sort 1; "Annotation", C.Sort 2]
      (unwrap label (run 4 empty jobs)));
  control "existing accepted names resolve without a batch job" (fun label ->
    let base = define empty "External" (C.Sort 1) (C.Sort 0) in
    let jobs = [identity "ExternalId" "External"] in
    observe_report label [["ExternalId"]]
      ["External", C.Sort 1; "ExternalId", C.Pi (C.Sort 0, C.Sort 0)]
      (unwrap label (run 4 base jobs));
    check (label ^ ": input snapshot unchanged")
      (infer base "ExternalId" = Error C.Unknown_constant));
  control "empty batch preserves the supplied environment" (fun label ->
    let base = define empty "Existing" (C.Sort 1) (C.Sort 0) in
    List.iter (fun workers ->
      observe_report label [] ["Existing", C.Sort 1]
        (unwrap label (run workers base []))) [1; 8])

let refusal_controls () =
  let empty = C.empty_environment in
  let exact label expected jobs =
    List.iter (fun workers ->
      expect_error (label ^ " workers=" ^ string_of_int workers) expected
        (run workers empty jobs)) [1; 2; 4; 8]
  in
  control "self-reference in a value is cyclic" (fun label ->
    exact label (B.Dependency_cycle ["Self"])
      [definition "Self" (C.Sort 1) (C.Const "Self")]);
  control "self-reference in an annotation is cyclic" (fun label ->
    exact label (B.Dependency_cycle ["Self"])
      [definition "Self" (C.Const "Self") (C.Sort 0)]);
  control "cycle includes its blocked descendant" (fun label ->
    exact label (B.Dependency_cycle ["A"; "B"; "Child"])
      [definition "A" (C.Sort 1) (C.Const "B");
       definition "B" (C.Sort 1) (C.Const "A");
       definition "Child" (C.Sort 1) (C.Const "B")]);
  control "whole graph is planned before any checking" (fun label ->
    exact label (B.Dependency_cycle ["Cycle"])
      [alias ~work:0 "WouldExhaust";
       definition "Cycle" (C.Sort 1) (C.Const "Cycle")]);
  control "cycles hidden in erased children are refused" (fun label ->
    exact label (B.Dependency_cycle ["Hidden"])
      [definition "Hidden" (C.Sort 1)
         (C.Let (C.Sort 1, C.Const "Hidden", C.Sort 0))]);
  control "unknown constant remains an exact checking refusal" (fun label ->
    exact label (B.Check_failed ["Missing", C.Unknown_constant])
      [definition "Missing" (C.Sort 1) (C.Const "Absent")]);
  control "unknown erased child is still checked" (fun label ->
    exact label (B.Check_failed ["Missing", C.Unknown_constant])
      [definition "Missing" (C.Sort 1)
         (C.Let (C.Sort 1, C.Const "Absent", C.Sort 0))]);
  control "independent refusals retain input order and exact causes" (fun label ->
    exact label (B.Check_failed ["Mismatch", C.Type_mismatch;
                               "Missing", C.Unknown_constant;
                               "Exhausted", C.Limit_exceeded])
      [definition "Mismatch" (C.Sort 1) (C.Sort 1);
       definition "Missing" (C.Sort 1) (C.Const "Absent");
       alias ~work:0 "Exhausted"]);
  control "failed parent prevents dependent checking" (fun label ->
    exact label (B.Check_failed ["Parent", C.Type_mismatch])
      [definition "Child" (C.Sort 1) (C.Const "Parent");
       definition "Parent" (C.Sort 1) (C.Sort 1)]);
  control "failure after an earlier wave returns no environment" (fun label ->
    let jobs = [alias "Good";
                definition "Bad" (C.Sort 0) (C.Const "Good")] in
    exact label (B.Check_failed ["Bad", C.Type_mismatch]) jobs;
    check (label ^ ": original snapshot has no partial result")
      (infer empty "Good" = Error C.Unknown_constant));
  control "base-name collision cannot be overwritten" (fun label ->
    let base = define empty "Existing" (C.Sort 1) (C.Sort 0) in
    List.iter (fun workers ->
      expect_error label (B.Check_failed ["Existing", C.Duplicate_definition])
        (run workers base [alias "Existing";
                          definition "Child" (C.Sort 1) (C.Const "Existing")])) [1; 4];
    check (label ^ ": existing value survives") (infer base "Existing" = Ok (C.Sort 1));
    check (label ^ ": dependent absent") (infer base "Child" = Error C.Unknown_constant));
  control "duplicate batch names are not merged" (fun label ->
    exact label (B.Duplicate_name "Repeated") [alias "Repeated"; alias "Repeated"]);
  control "empty name reports its input position" (fun label ->
    exact label (B.Invalid_name 1) [alias "Good"; alias ""]);
  control "cyclic definition list terminates" (fun label ->
    let job = alias "Repeated" in
    let rec jobs = job :: jobs in
    expect_error label (B.Duplicate_name "Repeated") (run 4 empty jobs));
  control "batch length bound is enforced" (fun label ->
    let jobs = List.init 4097 (fun index -> alias ("TooMany" ^ string_of_int index)) in
    expect_error label B.Too_many_definitions (run 4 empty jobs));
  control "zero scan budget is a planning resource refusal" (fun label ->
    expect_error label (B.Dependency_scan_failed ("A", C.Limit_exceeded))
      (run ~scan_fuel:0 4 empty [alias "A"]));
  control "type and value share the scan budget" (fun label ->
    expect_error label (B.Dependency_scan_failed ("A", C.Limit_exceeded))
      (run ~scan_fuel:1 4 empty [alias "A"]));
  control "cyclic expression traversal is height-bounded" (fun label ->
    let rec cyclic = C.App (C.Sort 0, cyclic) in
    expect_error label (B.Dependency_scan_failed ("Cyclic", C.Height_limit))
      (run 4 empty [definition "Cyclic" (C.Sort 1) cyclic]));
  control "zero merge budget is never a successful batch" (fun label ->
    expect_error label (B.Merge_failed C.Merge_limit_exceeded)
      (run ~merge_fuel:0 4 empty [alias "A"]));
  control "invalid scope remains distinct from a type mismatch" (fun label ->
    exact label (B.Check_failed ["Scope", C.Invalid_scope])
      [definition "Scope" (C.Sort 1) (C.Var 0)]);
  control "invalid annotation remains an exact Expected_sort refusal" (fun label ->
    exact label (B.Check_failed ["NonType", C.Expected_sort])
      [definition "NonType" (C.Lam (C.Sort 1, C.Var 0)) (C.Sort 0)]);
  control "invalid worker counts are rejected before empty work" (fun label ->
    List.iter (fun workers ->
      expect_error label B.Invalid_workers (run workers empty [])) [-1; 0; 65; max_int]);
  control "small checking budgets agree for one and many workers" (fun label ->
    for work = 0 to 48 do
      let jobs = [alias ~work "A"; alias ~work "B";
                  definition ~work "C" (C.Sort 1) (C.Const "A")] in
      match run 1 empty jobs, run 4 empty jobs with
      | Error a, Error b -> check label (a = b)
      | Ok a, Ok b -> compare_reports label
          ["A", C.Sort 1; "B", C.Sort 1; "C", C.Sort 1] a b
      | _ -> check label false
    done)

let pool_controls () =
  control "parallel map preserves input order" (fun label ->
    List.iter (fun workers ->
      let results = unwrap label (P.map ~workers (fun x -> x * x) [|8; 3; 5; 1|]) in
      check label (results = [|64; 9; 25; 1|])) [1; 2; 4; 8]);
  control "parallel map accepts empty work" (fun label ->
    check label (P.map ~workers:4 Fun.id [||] = Ok [||]));
  control "parallel map bounds worker counts" (fun label ->
    List.iter (fun workers ->
      expect_error label P.Invalid_workers (P.map ~workers Fun.id [||]))
      [-1; 0; P.max_workers + 1; max_int]);
  control "parallel map bounds job count" (fun label ->
    expect_error label P.Too_many_jobs
      (P.map ~workers:4 Fun.id (Array.make 4097 0)));
  control "worker exceptions are execution failures in input order" (fun label ->
    List.iter (fun workers ->
      let finished = Atomic.make 0 in
      let result = P.map ~workers (fun index ->
        Fun.protect ~finally:(fun () -> ignore (Atomic.fetch_and_add finished 1))
          (fun () ->
            if index = 1 then failwith "earliest";
            if index = 4 then failwith "later";
            index)) [|0; 1; 2; 3; 4; 5|] in
      expect_error label (P.Worker_exception (1, "Failure(\"earliest\")")) result;
      check (label ^ ": all jobs finished before return") (Atomic.get finished = 6))
      [1; 2; 4; 8]);
  control "successful pool call remains usable after task failure" (fun label ->
    ignore (P.map ~workers:4 (fun _ -> failwith "deliberate") [|0; 1|]);
    check label (P.map ~workers:4 ((+) 1) [|0; 1; 2|] = Ok [|1; 2; 3|]));
  control "two jobs overlap on distinct OCaml domains" (fun label ->
    let entered = Atomic.make 0 in
    let departed = Atomic.make 0 in
    let deadline = Unix.gettimeofday () +. 5.0 in
    let results = P.map ~workers:2 (fun _ ->
      ignore (Atomic.fetch_and_add entered 1);
      while Atomic.get entered < 2 && Unix.gettimeofday () < deadline do
        Domain.cpu_relax ()
      done;
      let overlapped = Atomic.get entered = 2 in
      ignore (Atomic.fetch_and_add departed 1);
      Domain.self (), overlapped) [|0; 1|] |> unwrap label in
    let first_id, first_overlap = results.(0) in
    let second_id, second_overlap = results.(1) in
    check (label ^ ": actual overlap") (first_overlap && second_overlap);
    check (label ^ ": distinct domains") (first_id <> second_id);
    check (label ^ ": both domains joined") (Atomic.get departed = 2));
  control "active callbacks cannot exceed the requested workers" (fun label ->
    let active = Atomic.make 0 in
    let peak = Atomic.make 0 in
    let rec raise_peak observed =
      let previous = Atomic.get peak in
      if observed > previous && not (Atomic.compare_and_set peak previous observed)
      then raise_peak observed
    in
    let results = P.map ~workers:3 (fun index ->
      let count = Atomic.fetch_and_add active 1 + 1 in
      raise_peak count;
      Fun.protect ~finally:(fun () -> ignore (Atomic.fetch_and_add active (-1)))
        (fun () ->
          ignore (Unix.select [] [] [] 0.001);
          index)) (Array.init 24 Fun.id) |> unwrap label in
    check (label ^ ": bounded active jobs") (Atomic.get peak <= 3);
    check (label ^ ": all active jobs finished") (Atomic.get active = 0);
    check (label ^ ": complete ordered result") (results = Array.init 24 Fun.id))

let generated_dags () =
  (* Every generated value has type Sort 1: roots are Sort 0, and later
     definitions use checked let bindings to refer to two earlier values.
     Reversing input order exercises dependency discovery independently of
     the sequential worker count used as the execution reference. *)
  for specimen = 0 to 31 do
    let prefix = Printf.sprintf "G%d_" specimen in
    let name index = prefix ^ string_of_int index in
    let jobs = List.init 12 (fun index ->
      if index < 3 then alias (name index)
      else
        let first = (specimen * 13 + index * 3) mod index in
        let second = (specimen * 7 + index * 5 + 1) mod index in
        definition (name index) (C.Sort 1)
          (C.Let (C.Sort 1, C.Const (name first), C.Const (name second))))
      |> List.rev in
    let expected = List.init 12 (fun index -> name index, C.Sort 1) in
    let label = "generated DAG " ^ string_of_int specimen in
    let sequential = unwrap label (run 1 C.empty_environment jobs) in
    List.iter (fun workers ->
      let parallel = unwrap label (run workers C.empty_environment jobs) in
      compare_reports label expected sequential parallel) [2; 4; 8];
    incr generated_cases
  done

let () =
  merge_controls ();
  dependency_controls ();
  refusal_controls ();
  pool_controls ();
  generated_dags ();
  Printf.printf "Reference batch conformance passed: %d named controls, %d generated DAGs, %d assertions\n"
    !controls !generated_cases !assertions
