type expr =
  | Var of int
  | Sort of int
  | Const of string
  | App of expr * expr
  | Lam of expr * expr
  | Pi of expr * expr
  | Let of expr * expr * expr

type error = Invalid_scope | Invalid_universe | Limit_exceeded
  | Height_limit | Index_overflow
  | Expected_sort | Expected_function | Type_mismatch
  | Unknown_constant | Duplicate_definition | Invalid_name

let max_height = 128

exception Refusal of error

let guard predicate error = if not predicate then raise (Refusal error)

let budget fuel =
  let remaining = ref fuel in
  fun () ->
    guard (!remaining > 0) Limit_exceeded;
    decr remaining

let protect f =
  try Ok (f ()) with
  | Refusal error -> Error error
  (* Defensive runtime refusal, never an equality or typing verdict. *)
  | Stack_overflow -> Error Limit_exceeded

(* Private terms carry checked heights. Public recursive variants can contain
   cyclic values or oversized trees; only [read] admits them into this form. *)
type term = { node : node; height : int }
and node =
  | V of int
  | S of int
  | A of term * term
  | L of term * term
  | P of term * term
  | T of term * term * term

let make node =
  let children = match node with
    | V _ | S _ -> 0
    | A (a, b) | L (a, b) | P (a, b) -> max a.height b.height
    | T (a, b, c) -> max a.height (max b.height c.height)
  in
  let height = children + 1 in
  guard (height <= max_height) Height_limit;
  { node; height }

let unknown _ = raise (Refusal Unknown_constant)

(* Left-to-right validation includes all children, even ones reduction erases.
   Subtraction avoids adding the ambient scope to a binder depth near max_int. *)
let read ?(constant = unknown) tick scope expression =
  guard (scope >= 0) Invalid_scope;
  let rec visit depth height expression =
    guard (height <= max_height) Height_limit;
    tick ();
    let here = visit depth (height + 1) in
    let under = visit (depth + 1) (height + 1) in
    match expression with
    | Var index ->
        guard (index >= 0 && (index < depth || index - depth < scope)) Invalid_scope;
        make (V index)
    | Sort level ->
        guard (level >= 0) Invalid_universe;
        make (S level)
    | Const name -> constant name
    | App (f, x) ->
        let f = here f in
        let x = here x in
        make (A (f, x))
    | Lam (domain, body) ->
        let domain = here domain in
        let body = under body in
        make (L (domain, body))
    | Pi (domain, body) ->
        let domain = here domain in
        let body = under body in
        make (P (domain, body))
    | Let (ty, value, body) ->
        let ty = here ty in
        let value = here value in
        let body = under body in
        make (T (ty, value, body))
  in
  visit 0 1 expression

(* Returning a shared internal tree as public syntax also consumes fuel. *)
let rec write tick term =
  tick ();
  match term.node with
  | V index -> Var index
  | S level -> Sort level
  | A (f, x) ->
      let f = write tick f in
      let x = write tick x in
      App (f, x)
  | L (domain, body) ->
      let domain = write tick domain in
      let body = write tick body in
      Lam (domain, body)
  | P (domain, body) ->
      let domain = write tick domain in
      let body = write tick body in
      Pi (domain, body)
  | T (ty, value, body) ->
      let ty = write tick ty in
      let value = write tick value in
      let body = write tick body in
      Let (ty, value, body)

(* A binder scopes its body alone. Internal height bounds also bound [depth]. *)
let rec map tick variable depth term =
  tick ();
  let here = map tick variable depth in
  let under = map tick variable (depth + 1) in
  match term.node with
  | V index -> variable depth index
  | S _ -> term
  | A (f, x) ->
      let f = here f in
      let x = here x in
      make (A (f, x))
  | L (domain, body) ->
      let domain = here domain in
      let body = under body in
      make (L (domain, body))
  | P (domain, body) ->
      let domain = here domain in
      let body = under body in
      make (P (domain, body))
  | T (ty, value, body) ->
      let ty = here ty in
      let value = here value in
      let body = under body in
      make (T (ty, value, body))

let lift tick amount =
  map tick (fun cutoff index ->
    if index < cutoff then make (V index)
    else (
      guard (index <= max_int - amount) Index_overflow;
      make (V (index + amount)))) 0

let substitute tick replacement body =
  map tick (fun depth index ->
    if index < depth then make (V index)
    else if index > depth then make (V (index - 1))
    else if depth = 0 then replacement
    else lift tick depth replacement) 0 body

let validate_scope ~fuel ~scope expression =
  protect (fun () -> ignore (read (budget fuel) scope expression))

let instantiate ~fuel ~scope ~body replacement =
  protect (fun () ->
    let tick = budget fuel in
    guard (scope >= 0) Invalid_scope;
    guard (scope < max_int) Index_overflow;
    let body = read tick (scope + 1) body in
    let replacement = read tick scope replacement in
    write tick (substitute tick replacement body))

(* [depth] bounds the evaluator's active expression contexts as well as term
   height. Tail reductions retain it; descent through an application adds one. *)
let rec head tick depth term =
  guard (depth <= max_height) Height_limit;
  tick ();
  match term.node with
  | T (_, value, body) -> head tick depth (substitute tick value body)
  | A (f, x) ->
      let f = head tick (depth + 1) f in
      (match f.node with
      | L (_, body) -> head tick depth (substitute tick x body)
      | _ -> make (A (f, x)))
  | _ -> term

let rec normal tick depth term =
  match (head tick depth term).node with
  | A (f, x) ->
      let f = normal tick (depth + 1) f in
      let x = normal tick (depth + 1) x in
      make (A (f, x))
  | L (ty, body) ->
      let ty = normal tick (depth + 1) ty in
      let body = normal tick (depth + 1) body in
      make (L (ty, body))
  | P (ty, body) ->
      let ty = normal tick (depth + 1) ty in
      let body = normal tick (depth + 1) body in
      make (P (ty, body))
  | (V _ | S _) as node -> make node
  | T (_, value, body) -> normal tick depth (substitute tick value body)

let rec equal tick left right =
  tick ();
  match left.node, right.node with
  | V a, V b | S a, S b -> a = b
  | A (a, b), A (c, d) | L (a, b), L (c, d) | P (a, b), P (c, d) ->
      equal tick a c && equal tick b d
  | T (a, b, c), T (d, e, f) ->
      equal tick a d && equal tick b e && equal tick c f
  | _ -> false

let whnf_in ~fuel ~scope expression =
  protect (fun () ->
    let tick = budget fuel in
    let term = read tick scope expression in
    write tick (head tick 1 term))

let whnf ~fuel expression = whnf_in ~fuel ~scope:0 expression

let normalize ~fuel ~scope expression =
  protect (fun () ->
    let tick = budget fuel in
    let term = read tick scope expression in
    write tick (normal tick 1 term))

let beta_zeta_equal_in ~fuel ~scope left right =
  protect (fun () ->
    let tick = budget fuel in
    let left = read tick scope left in
    let right = read tick scope right in
    let left = normal tick 1 left in
    let right = normal tick 1 right in
    equal tick left right)

let beta_zeta_equal ~fuel left right = beta_zeta_equal_in ~fuel ~scope:0 left right

(* Each context entry is scoped in the tail that was present when it was added. *)
let infer_type tick term =
  let rec lookup context index =
    tick ();
    match context with
    | [] -> raise (Refusal Invalid_scope)
    | ty :: _ when index = 0 -> ty
    | _ :: tail -> lookup tail (index - 1)
  in
  let rec infer depth context term =
    guard (depth <= max_height) Height_limit;
    tick ();
    match term.node with
    | V index ->
        guard (index < max_int) Index_overflow;
        lift tick (index + 1) (lookup context index)
    | S level ->
        guard (level < max_int) Index_overflow;
        make (S (level + 1))
    | L (domain, body) ->
        ignore (sort_level (depth + 1) context domain);
        let body_type = infer (depth + 1) (domain :: context) body in
        make (P (domain, body_type))
    | P (domain, body) ->
        let input = sort_level (depth + 1) context domain in
        let output = sort_level (depth + 1) (domain :: context) body in
        make (S (if output = 0 then 0 else max input output))
    | A (fn, arg) ->
        (match (head tick 1 (infer (depth + 1) context fn)).node with
        | P (domain, body) ->
            check (depth + 1) context arg domain;
            substitute tick arg body
        | _ -> raise (Refusal Expected_function))
    | T (ty, value, body) ->
        ignore (sort_level (depth + 1) context ty);
        check (depth + 1) context value ty;
        (* Zeta-expand before inferring so the local value affects conversion. *)
        infer depth context (substitute tick value body)
  and sort_level depth context term =
    match (head tick 1 (infer depth context term)).node with
    | S level -> level
    | _ -> raise (Refusal Expected_sort)
  and check depth context term expected =
    let actual = normal tick 1 (infer depth context term) in
    let expected = normal tick 1 expected in
    guard (equal tick actual expected) Type_mismatch
  in
  normal tick 1 (infer 1 [] term)

let infer_closed ~fuel expression =
  protect (fun () ->
    let tick = budget fuel in
    let term = read tick 0 expression in
    write tick (infer_type tick term))

(* Values are expanded, checked, and closed before becoming visible. *)
type environment = (string * term) list

let empty_environment = []

let rec find_definition tick name entries =
  tick ();
  match entries with
  | [] -> None
  | (key, value) :: rest ->
      if String.equal key name then Some value else find_definition tick name rest

let expand tick env expression =
  let constant name =
    match find_definition tick name env with
    | Some value -> value
    | None -> raise (Refusal Unknown_constant)
  in
  read ~constant tick 0 expression

let infer_in ~fuel env expression =
  protect (fun () ->
    let tick = budget fuel in
    let term = expand tick env expression in
    write tick (infer_type tick term))

let define ~fuel env ~name ~ty ~value =
  protect (fun () ->
    let tick = budget fuel in
    guard (name <> "") Invalid_name;
    guard (find_definition tick name env = None) Duplicate_definition;
    let ty = expand tick env ty in
    let value = expand tick env value in
    let ty_sort = infer_type tick ty in
    (match ty_sort.node with S _ -> () | _ -> raise (Refusal Expected_sort));
    let actual = infer_type tick value in
    let expected = normal tick 1 ty in
    guard (equal tick actual expected) Type_mismatch;
    (name, value) :: env)

type merge_error = Invalid_branch | Duplicate_branch | Merge_limit_exceeded

exception Merge_refusal of merge_error

module Definition_names = Set.Make (String)

let merge_checked_branches ~fuel ~base branches =
  let remaining = ref fuel in
  let tick () =
    if !remaining <= 0 then raise (Merge_refusal Merge_limit_exceeded);
    decr remaining
  in
  let rec collect names heads = function
    | [] ->
        (* Match a left-to-right insertion fold, without repeating type checks.
           The checked values contain no name references to reinterpret. *)
        List.fold_left (fun env binding -> tick (); binding :: env)
          base (List.rev heads)
    | branch :: rest ->
        tick ();
        (match branch with
        | ((name, _) as binding) :: parent when parent == base ->
            if Definition_names.mem name names then
              raise (Merge_refusal Duplicate_branch);
            collect (Definition_names.add name names) (binding :: heads) rest
        | _ -> raise (Merge_refusal Invalid_branch))
  in
  try
    tick ();
    Ok (collect Definition_names.empty [] branches)
  with Merge_refusal error -> Error error
