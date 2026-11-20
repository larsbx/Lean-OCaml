(* Untimed sequential differential observer for a new language candidate.
   Each successful definition goes through the existing public reference API.
   Resource and structural errors abort; they cannot count as semantic refusal. *)
open Conversion

let fail message = failwith ("migration_check: " ^ message)
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
        definitions := (simple_name name, child ty, child value) :: !definitions
    | _ -> fail "invalid DAG row") rows;
  if !definitions = [] then fail "empty definition inventory";
  List.rev !definitions

let semantic_error = function
  | Expected_sort -> "Expected_sort"
  | Expected_function -> "Expected_function"
  | Type_mismatch -> "Type_mismatch"
  | Unknown_constant -> "Unknown_constant"
  | Duplicate_definition -> "Duplicate_definition"
  | Invalid_scope | Invalid_universe | Limit_exceeded | Height_limit
  | Index_overflow | Invalid_name -> fail "inconclusive structural or resource refusal"

let () =
  if Array.length Sys.argv <> 3 || Sys.argv.(1) <> "--check" then
    fail "usage: migration_check --check fixture.tsv";
  if Sys.backend_type <> Bytecode then fail "OCaml bytecode backend required";
  let definitions = load Sys.argv.(2) in
  let env = ref empty_environment in
  let accepted = ref 0 in
  let outcomes = List.map (fun (name, ty, value) ->
    let outcome = match define ~fuel !env ~name ~ty ~value with
      | Ok next ->
          (match infer_in ~fuel next (Const name) with
           | Ok _ -> () | Error _ -> fail "accepted name cannot be inferred");
          env := next; incr accepted; "accepted"
      | Error error -> semantic_error error
    in
    Printf.sprintf "{\"name\":\"%s\",\"outcome\":\"%s\"}" name outcome) definitions
  in
  Printf.printf
    "{\"engine\":\"ocaml-bytecode\",\"status\":\"checked\",\"outcomes\":[%s],\"accepted\":%d,\"acceptance_authority\":false}\n%!"
    (String.concat "," outcomes) !accepted
