(* Matched-input timing of the reference batch API. The DAG fixture preserves
   the same physical subexpression sharing for both implementations. Parsing,
   one-worker reference preparation, full GC and result verification are outside
   each batch timer. Planning, import validation, checking, domain startup/join
   and checked merging are inside it. *)
open Conversion

external monotonic_ns : unit -> int64 = "lean_ocaml_benchmark_monotonic_ns"

let fail text = failwith ("benchmark_compare: " ^ text)
let fuel = 10_000_000
let natural text =
  if text = "" || not (String.for_all (fun c -> c >= '0' && c <= '9') text)
  then fail "invalid natural";
  int_of_string text

let simple_name text =
  if text = "" || not (String.for_all (function
      | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' -> true | _ -> false) text)
  then fail "invalid name";
  text

let load path =
  let rows = In_channel.with_open_text path In_channel.input_lines in
  let rows = match rows with
    | "lean-ocaml-benchmark-dag-v1" :: rest -> rest
    | _ -> fail "unknown DAG schema"
  in
  let nodes = Array.make (List.length rows) (Sort 0) in
  let count = ref 0 in
  let definitions = ref [] in
  let child text =
    let index = natural text in
    if index >= !count then fail "node reference must precede its use";
    nodes.(index)
  in
  List.iter (fun row ->
    match String.split_on_char '\t' row with
    | "n" :: index :: tag :: fields ->
        if !definitions <> [] then fail "node follows definition";
        if natural index <> !count then fail "noncontiguous node index";
        let term = match tag, fields with
          | "s", [level] -> Sort (natural level)
          | "v", [index] -> Var (natural index)
          | "c", [name] -> Const (simple_name name)
          | "a", [a; b] -> App (child a, child b)
          | "l", [a; b] -> Lam (child a, child b)
          | "p", [a; b] -> Pi (child a, child b)
          | "t", [a; b; c] -> Let (child a, child b, child c)
          | _ -> fail "invalid node"
        in
        nodes.(!count) <- term;
        incr count
    | ["d"; name; ty; value] ->
        definitions := Definition_batch.{
          name = simple_name name; ty = child ty; value = child value; fuel
        } :: !definitions
    | _ -> fail "invalid DAG row") rows;
  if !definitions = [] then fail "empty definition inventory";
  List.rev !definitions

let check workers definitions =
  match Definition_batch.run ~workers ~scan_fuel:1_000_000 ~merge_fuel:1_000_000
      empty_environment definitions with
  | Ok report -> report
  | Error _ -> fail "definition batch refused"

let verify_reference definitions report =
  List.iter (fun (d : Definition_batch.definition) ->
    let expected = match normalize ~fuel ~scope:0 d.ty with
      | Ok ty -> ty | Error _ -> fail "annotation normalization refused"
    in
    match infer_in ~fuel report.Definition_batch.environment (Const d.name) with
    | Ok actual when actual = expected -> ()
    | _ -> fail ("inferred type differs: " ^ d.name)) definitions

let refusal_control () =
  match define ~fuel empty_environment ~name:"benchmarkInvalid"
      ~ty:(Sort 1) ~value:(Sort 1) with
  | Error Type_mismatch -> ()
  | _ -> fail "invalid declaration was not rejected with Type_mismatch"

let () =
  if Array.length Sys.argv <> 4 then
    fail "usage: benchmark_compare fixture.tsv workers iterations";
  if Sys.backend_type <> Bytecode then fail "OCaml bytecode backend required";
  let definitions = load Sys.argv.(1) in
  let workers = natural Sys.argv.(2) in
  let iterations = natural Sys.argv.(3) in
  if workers < 1 || workers > 64 || iterations < 1 || iterations > 100_000 then
    fail "workers or iterations outside bounds";
  refusal_control ();
  let reference = check 1 definitions in
  verify_reference definitions reference;
  let elapsed = ref 0L in
  let cpu = ref 0.0 in
  for _ = 1 to iterations do
    Gc.full_major ();
    let cpu_start = Sys.time () in
    let start = monotonic_ns () in
    let report = check workers definitions in
    let stop = monotonic_ns () in
    let cpu_stop = Sys.time () in
    if stop <= start then fail "non-positive monotonic interval";
    elapsed := Int64.add !elapsed (Int64.sub stop start);
    cpu := !cpu +. cpu_stop -. cpu_start;
    if report.Definition_batch.waves <> reference.Definition_batch.waves then
      fail "dependency waves differ from one-worker reference";
    if report.environment <> reference.environment then
      fail "checked environment differs from one-worker reference"
  done;
  Printf.printf
    "{\"engine\":\"ocaml-bytecode\",\"status\":\"passed\",\"workers\":%d,\"iterations\":%d,\"definitions\":%d,\"waves\":%d,\"elapsed_ns\":%Ld,\"per_batch_ns\":%.3f,\"cpu_s\":%.9f,\"validated_batches\":%d,\"refusal_controls\":1}\n%!"
    workers iterations (List.length definitions)
    (List.length reference.waves) !elapsed
    (Int64.to_float !elapsed /. float_of_int iterations) !cpu iterations
