(* Independent adapter for the exact, pinned Rust PR #1 Lean oracle corpus. *)
open Conversion

let require message condition = if not condition then failwith message

let natural text =
  require "invalid natural number"
    (text <> "" && String.for_all (fun c -> c >= '0' && c <= '9') text);
  int_of_string text

let expression text =
  require "oversized fixture expression" (String.length text <= 1_000_000);
  let rec parse height tokens =
    require "fixture expression exceeds height 128" (height <= 128);
    let next = parse (height + 1) in
    match tokens with
    | ("a" | "l" | "p" as tag) :: rest ->
        let left, rest = next rest in
        let right, rest = next rest in
        let term = match tag with
          | "a" -> App (left, right)
          | "l" -> Lam (left, right)
          | _ -> Pi (left, right)
        in
        term, rest
    | "t" :: rest ->
        let ty, rest = next rest in
        let value, rest = next rest in
        let body, rest = next rest in
        Let (ty, value, body), rest
    | token :: rest when String.length token > 1 ->
        let value = natural (String.sub token 1 (String.length token - 1)) in
        (match token.[0] with
         | 'v' -> Var value, rest
         | 's' -> Sort value, rest
         | _ -> failwith "unsupported fixture constructor")
    | _ -> failwith "truncated or invalid fixture expression"
  in
  match parse 1 (String.split_on_char ' ' text) with
  | term, [] -> term
  | _ -> failwith "trailing fixture tokens"

let boolean = function
  | "true" -> true
  | "false" -> false
  | _ -> failwith "invalid fixture boolean"

let equality_cases = [
  "beta", (true, true); "zeta", (true, true); "alpha", (true, true);
  "beta-under-pi", (true, true); "dependent-beta", (true, true);
  "capture-under-lambda", (true, true); "shadowing", (false, false);
  "different-sorts", (false, false); "different-domains", (false, false);
  "eta-outside-fragment", (true, false);
  "proof-irrelevance-outside-fragment", (true, false)
]

let head_cases = [
  "beta-head"; "zeta-head"; "whnf-stops-under-lambda";
  "let-in-function-position"
]

let substitution_cases = [
  "lift-open-replacement"; "preserve-inner-and-decrement-outer";
  "let-scopes"; "lift-cutoff"
]

let replay rows =
  let seen = Hashtbl.create 19 in
  let record id =
    require ("duplicate fixture: " ^ id) (not (Hashtbl.mem seen id));
    Hashtbl.add seen id ()
  in
  List.iter (fun row ->
    match String.split_on_char '\t' row with
    | ["eq"; id; lean; fragment; left; right] ->
        record id;
        let expected = match List.assoc_opt id equality_cases with
          | Some expected -> expected
          | None -> failwith ("unregistered equality fixture: " ^ id)
        in
        let lean, fragment = boolean lean, boolean fragment in
        require ("unregistered agreement/disagreement: " ^ id)
          ((lean, fragment) = expected);
        require ("OCaml conversion differs: " ^ id)
          (beta_zeta_equal ~fuel:1_000_000
            (expression left) (expression right) = Ok fragment)
    | ["whnf"; id; input; expected] ->
        record id;
        require ("unregistered WHNF fixture: " ^ id) (List.mem id head_cases);
        (* Structural comparison must not perform any further reduction. *)
        require ("OCaml WHNF differs: " ^ id)
          (whnf ~fuel:1_000_000 (expression input) = Ok (expression expected))
    | ["inst"; id; scope; body; value; expected] ->
        record id;
        require ("unregistered substitution fixture: " ^ id)
          (List.mem id substitution_cases);
        require ("OCaml substitution differs: " ^ id)
          (instantiate ~fuel:1_000_000 ~scope:(natural scope)
            ~body:(expression body) (expression value) = Ok (expression expected))
    | _ -> failwith "invalid oracle fixture row") rows;
  require "incomplete Rust baseline corpus" (Hashtbl.length seen = 19)

let negative_controls rows =
  let controls = ref 0 in
  let refuses label operation =
    incr controls;
    let refused = try operation (); false with Failure _ -> true in
    require ("negative harness control accepted: " ^ label) refused
  in
  refuses "missing fixture" (fun () -> replay (List.tl rows));
  refuses "duplicate fixture" (fun () -> replay (List.hd rows :: rows));
  refuses "malformed row" (fun () -> replay ("eq\tmalformed" :: List.tl rows));
  let change id transform =
    List.map (fun row -> match String.split_on_char '\t' row with
      | tag :: found :: rest when found = id ->
          String.concat "\t" (transform (tag :: found :: rest))
      | _ -> row) rows
  in
  refuses "invented disagreement"
    (fun () -> replay (change "eta-outside-fragment" (function
      | tag :: _ :: rest -> tag :: "unlisted-outside-fragment" :: rest
      | fields -> fields)));
  refuses "silenced known disagreement"
    (fun () -> replay (change "eta-outside-fragment" (function
      | [tag; id; _; fragment; left; right] ->
          [tag; id; "false"; fragment; left; right]
      | fields -> fields)));
  refuses "changed expected conversion"
    (fun () -> replay (change "beta" (function
      | [tag; id; lean; _; left; right] -> [tag; id; lean; "false"; left; right]
      | fields -> fields)));
  List.iter (fun text -> refuses ("invalid expression: " ^ text)
    (fun () -> ignore (expression text)))
    ["s0 v0"; "a s0"; "s-1"; "v+0"; "cOpaque"; "s99999999999999999999999999"];
  !controls

let () =
  require "usage: rust_replay path/to/rust-v1.tsv" (Array.length Sys.argv = 2);
  let rows = In_channel.with_open_text Sys.argv.(1) In_channel.input_lines in
  replay rows;
  let controls = negative_controls rows in
  Printf.printf
    "19 Rust-baseline Lean fixtures passed (9 matching equality, 2 registered disagreements, 4 WHNF, 4 substitution); %d harness rejection controls passed\n"
    controls
