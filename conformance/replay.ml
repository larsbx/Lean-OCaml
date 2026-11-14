open Conversion

let nat token =
  if token = "" || not (String.for_all (fun c -> c >= '0' && c <= '9') token)
  then failwith "invalid natural number";
  int_of_string token

let expr text =
  let rec parse depth tokens =
    if depth > 128 then failwith "vector expression too deep";
    let next = parse (depth + 1) in
    match tokens with
    | ("a" | "l" | "p" as tag) :: rest ->
        let a, rest = next rest in
        let b, rest = next rest in
        let expression = match tag with
          | "a" -> App (a, b)
          | "l" -> Lam (a, b)
          | _ -> Pi (a, b)
        in
        expression, rest
    | "t" :: rest ->
        let ty, rest = next rest in
        let value, rest = next rest in
        let body, rest = next rest in
        Let (ty, value, body), rest
    | token :: rest when String.length token > 1 && token.[0] = 'c' ->
        Const (String.sub token 1 (String.length token - 1)), rest
    | token :: rest when String.length token > 1 ->
        let n = nat (String.sub token 1 (String.length token - 1)) in
        (match token.[0] with
         | 'v' -> Var n, rest
         | 's' -> Sort n, rest
         | _ -> failwith "invalid leaf tag")
    | _ -> failwith "invalid expression"
  in
  match parse 0 (String.split_on_char ' ' text) with
  | term, [] -> term
  | _ -> failwith "trailing expression tokens"

let boolean = function
  | "true" -> true
  | "false" -> false
  | _ -> failwith "invalid boolean"

let check label condition = if not condition then failwith label

(* These fixtures apply an A-valued identity to an argument bound at type B.
   A different semantic error is not evidence for that intended rejection. *)
let dependent_refusals = [
  "depth-0-wrong-binder", Type_mismatch;
  "depth-1-wrong-binder", Type_mismatch;
  "depth-2-wrong-binder", Type_mismatch;
  "depth-3-wrong-binder", Type_mismatch;
  "depth-4-wrong-binder", Type_mismatch;
  "depth-5-wrong-binder", Type_mismatch;
  "depth-6-wrong-binder", Type_mismatch;
  "depth-7-wrong-binder", Type_mismatch;
  "depth-8-wrong-binder", Type_mismatch;
]

let typing_matches id result expected =
  match List.assoc_opt id dependent_refusals, expected, result with
  | Some required, "refused", Error actual -> actual = required
  | Some _, _, _ -> false
  | None, "refused", Error (Expected_sort | Expected_function | Type_mismatch) -> true
  | None, "refused", Ok _ -> false
  | None, expected, Ok actual -> actual = expr expected
  | None, _, Error _ -> false

let check_typing_refusal_controls () =
  let controls = [
    "wrong binder rejects Expected_sort", Error Expected_sort, "refused";
    "wrong binder rejects Expected_function", Error Expected_function, "refused";
    "wrong binder rejects fuel exhaustion", Error Limit_exceeded, "refused";
    "wrong binder rejects height refusal", Error Height_limit, "refused";
    "wrong binder rejects index overflow", Error Index_overflow, "refused";
    "wrong binder rejects successful inference", Ok (Sort 1), "refused";
    "wrong binder requires a refusal expectation", Ok (Sort 1), "s1";
  ] in
  List.iter (fun (label, result, expected) ->
    check label (not (typing_matches "depth-0-wrong-binder" result expected))) controls;
  List.length controls

let replay path =
  In_channel.with_open_text path (fun input ->
    let ids = Hashtbl.create 144 in
    In_channel.input_lines input |> List.iter (fun line ->
      match String.split_on_char '\t' line with
      | ["eq"; id; lean; expected; left; right] ->
          check ("duplicate vector: " ^ id) (not (Hashtbl.mem ids id));
          Hashtbl.add ids id ();
          let expected = boolean expected in
          check ("Lean disagrees: " ^ id) (boolean lean = expected);
          check ("OCaml disagrees: " ^ id)
            (beta_zeta_equal ~fuel:100_000 (expr left) (expr right) = Ok expected)
      | _ -> failwith "invalid vector row");
    check "incomplete corpus" (Hashtbl.length ids = 144))

let replay_types path =
  In_channel.with_open_text path (fun input ->
    let ids = Hashtbl.create 40 in
    In_channel.input_lines input |> List.iter (fun line ->
      match String.split_on_char '\t' line with
      | ["type"; id; term; expected] ->
          check ("duplicate type vector: " ^ id) (not (Hashtbl.mem ids id));
          Hashtbl.add ids id ();
          let matches = typing_matches id (infer_closed ~fuel:100_000 (expr term)) expected in
          check ("OCaml typing disagrees: " ^ id) matches
      | _ -> failwith "invalid type vector row");
    check "incomplete type corpus" (Hashtbl.length ids = 40);
    List.iter (fun (id, _) ->
      check ("missing dependent refusal: " ^ id) (Hashtbl.mem ids id)) dependent_refusals)

let replay_definitions path =
  let rows = In_channel.with_open_text path In_channel.input_lines in
  check "incomplete definition corpus" (List.length rows = 7);
  let replay env line =
    match String.split_on_char '\t' line with
    | ["def"; name; ty; value; expected] ->
        (match define ~fuel:100_000 env ~name ~ty:(expr ty) ~value:(expr value),
          boolean expected with
        | Ok next, true -> next
        | Error (Duplicate_definition | Unknown_constant | Expected_sort | Type_mismatch),
          false -> env
        | _ -> failwith ("OCaml definition disagrees: " ^ name))
    | ["infer"; term; expected] ->
        check "OCaml named inference disagrees"
          (infer_in ~fuel:100_000 env (expr term) = Ok (expr expected));
        env
    | _ -> failwith "invalid definition vector row"
  in
  ignore (List.fold_left replay empty_environment rows)

let () =
  replay Sys.argv.(1);
  replay_types (Sys.argv.(1) ^ ".types");
  replay_definitions (Sys.argv.(1) ^ ".defs");
  let typing_refusal_controls = check_typing_refusal_controls () in
  let ty = Sort 1 in
  let id = Lam (ty, Var 0) in
  let self = Lam (ty, App (Var 0, Var 0)) in
  check "beta" (whnf ~fuel:100 (App (id, Sort 0)) = Ok (Sort 0));
  check "capture" (instantiate ~fuel:100 ~scope:1
    ~body:(Lam (ty, Var 1)) (Var 0) = Ok (Lam (ty, Var 1)));
  check "pi body normalization"
    (beta_zeta_equal ~fuel:100 (Pi (ty, App (id, Var 0))) (Pi (ty, Var 0)) = Ok true);
  check "let value scope" (whnf ~fuel:100 (Let (ty, Var 0, Var 0)) = Error Invalid_scope);
  check "negative index" (whnf ~fuel:100 (Var (-1)) = Error Invalid_scope);
  check "negative sort" (whnf ~fuel:100 (Sort (-1)) = Error Invalid_universe);
  check "zero fuel" (whnf ~fuel:0 id = Error Limit_exceeded);
  check "divergence" (whnf ~fuel:1000 (App (self, self)) = Error Limit_exceeded);
  check "trailing tokens refused"
    (match expr "s1 v0" with _ -> false | exception Failure _ -> true);
  check "inference checks scope" (infer_closed ~fuel:100 (Var 0) = Error Invalid_scope);
  check "inference shares fuel" (infer_closed ~fuel:1 id = Error Limit_exceeded);
  check "sort successor overflow" (infer_closed ~fuel:100 (Sort max_int) = Error Index_overflow);
  let initial = empty_environment in
  let next = match define ~fuel:100 initial ~name:"prop" ~ty ~value:(Sort 0) with
    | Ok env -> env
    | Error _ -> failwith "valid definition refused"
  in
  check "definition is closed under binders"
    (infer_in ~fuel:100 next (Lam (ty, Const "prop")) = Ok (Pi (ty, ty)));
  check "earlier snapshot is immutable"
    (infer_in ~fuel:100 initial (Const "prop") = Error Unknown_constant);
  check "definition lookup shares fuel"
    (infer_in ~fuel:1 next (Const "prop") = Error Limit_exceeded);
  check "unknown constant in erased argument"
    (infer_in ~fuel:100 next (App (Lam (ty, Sort 0), Const "missing"))
      = Error Unknown_constant);
  Printf.printf
    "144 Lean conversion, 40 typing, 7 environment vectors, 16 controls and %d typing refusal controls passed\n"
    typing_refusal_controls
