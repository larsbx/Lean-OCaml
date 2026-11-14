type expr =
  | Var of int
  | Sort of int
  | Const of string
  | App of expr * expr
  | Lam of expr * expr
  | Pi of expr * expr
  | Let of expr * expr * expr

type error = Invalid_scope | Invalid_universe | Limit_exceeded
  | Expected_sort | Expected_function | Type_mismatch
  | Unknown_constant | Duplicate_definition | Invalid_name
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
  | Stack_overflow -> Error Limit_exceeded

(* Walk only through expression structure. A binder scopes its body alone. *)
let rec map ?(constant = fun name -> Const name) tick variable depth term =
  tick ();
  let here = map ~constant tick variable depth in
  let under term = map ~constant tick variable (depth + 1) term in
  match term with
  | Var index -> variable depth index
  | Const name -> constant name
  | Sort level ->
      guard (level >= 0) Invalid_universe;
      term
  | App (f, x) -> App (here f, here x)
  | Lam (domain, body) -> Lam (here domain, under body)
  | Pi (domain, body) -> Pi (here domain, under body)
  | Let (ty, value, body) -> Let (here ty, here value, under body)

let validate tick scope term =
  guard (scope >= 0) Invalid_scope;
  ignore (map ~constant:(fun _ -> raise (Refusal Unknown_constant)) tick (fun depth index ->
    guard (index >= 0 && (index < depth || index - depth < scope)) Invalid_scope;
    Var index) 0 term)

let lift tick amount =
  map tick (fun cutoff index ->
    if index < cutoff then Var index
    else (
      guard (index <= max_int - amount) Limit_exceeded;
      Var (index + amount))) 0

let substitute tick replacement body =
  map tick (fun depth index ->
    if index < depth then Var index
    else if index > depth then Var (index - 1)
    else if depth = 0 then replacement
    else lift tick depth replacement) 0 body

let instantiate ~fuel ~scope ~body replacement =
  protect (fun () ->
    let tick = budget fuel in
    guard (scope >= 0) Invalid_scope;
    guard (scope < max_int) Limit_exceeded;
    validate tick (scope + 1) body;
    validate tick scope replacement;
    substitute tick replacement body)

let rec head tick term =
  tick ();
  match term with
  | Let (_, value, body) -> head tick (substitute tick value body)
  | App (f, x) ->
      (match head tick f with
      | Lam (_, body) -> head tick (substitute tick x body)
      | f -> App (f, x))
  | term -> term

let rec normal tick term =
  match head tick term with
  | App (f, x) -> App (normal tick f, normal tick x)
  | Lam (ty, body) -> Lam (normal tick ty, normal tick body)
  | Pi (ty, body) -> Pi (normal tick ty, normal tick body)
  | term -> term

let whnf ~fuel term =
  protect (fun () ->
    let tick = budget fuel in
    validate tick 0 term;
    head tick term)

let beta_zeta_equal ~fuel left right =
  protect (fun () ->
    let tick = budget fuel in
    validate tick 0 left;
    validate tick 0 right;
    let left = normal tick left in
    let right = normal tick right in
    left = right)

(* Each context entry is scoped in the tail that was present when it was added. *)
let infer_type tick term =
  let rec lookup context index =
    tick ();
    match context with
    | [] -> raise (Refusal Invalid_scope)
    | ty :: _ when index = 0 -> ty
    | _ :: tail -> lookup tail (index - 1)
  in
  let rec infer context term =
    tick ();
    match term with
    | Var index ->
        guard (index < max_int) Limit_exceeded;
        lift tick (index + 1) (lookup context index)
    | Const _ -> raise (Refusal Unknown_constant)
    | Sort level ->
        guard (level < max_int) Limit_exceeded;
        Sort (level + 1)
    | Lam (domain, body) ->
        ignore (sort_level context domain);
        Pi (domain, infer (domain :: context) body)
    | Pi (domain, body) ->
        let input = sort_level context domain in
        let output = sort_level (domain :: context) body in
        Sort (if output = 0 then 0 else max input output)
    | App (fn, arg) ->
        (match head tick (infer context fn) with
        | Pi (domain, body) ->
            check context arg domain;
            substitute tick arg body
        | _ -> raise (Refusal Expected_function))
    | Let (ty, value, body) ->
        ignore (sort_level context ty);
        check context value ty;
        (* Zeta-expand before inferring so the local value can affect conversion. *)
        infer context (substitute tick value body)
  and sort_level context term =
    match head tick (infer context term) with
    | Sort level -> level
    | _ -> raise (Refusal Expected_sort)
  and check context term expected =
    let actual = normal tick (infer context term) in
    let expected = normal tick expected in
    guard (actual = expected) Type_mismatch
  in
  validate tick 0 term;
  normal tick (infer [] term)

let infer_closed ~fuel term =
  protect (fun () -> infer_type (budget fuel) term)

(* Values are expanded, checked, and closed before becoming visible. *)
type environment = (string * expr) list

let empty_environment = []

let rec find_definition tick name entries =
  tick ();
  match entries with
  | [] -> None
  | (key, value) :: rest ->
      if key = name then Some value else find_definition tick name rest

let expand tick env =
  let constant name =
    match find_definition tick name env with
    | Some value -> value
    | None -> raise (Refusal Unknown_constant)
  in
  map ~constant tick (fun _ index -> Var index) 0

let infer_in ~fuel env term =
  protect (fun () ->
    let tick = budget fuel in
    infer_type tick (expand tick env term))

let define ~fuel env ~name ~ty ~value =
  protect (fun () ->
    let tick = budget fuel in
    guard (name <> "") Invalid_name;
    guard (find_definition tick name env = None) Duplicate_definition;
    let ty = expand tick env ty in
    let value = expand tick env value in
    let ty_sort = infer_type tick ty in
    (match ty_sort with Sort _ -> () | _ -> raise (Refusal Expected_sort));
    let actual = infer_type tick value in
    guard (actual = normal tick ty) Type_mismatch;
    (name, value) :: env)
