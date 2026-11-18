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

let protect f =
  try Ok (f ()) with
  | Refusal error -> Error error
  | Stack_overflow -> Error Limit_exceeded

(* Only [read] admits public, possibly cyclic syntax into checked private terms.
   Hashes and free-variable bounds are immutable deterministic metadata. *)
type term = { node : node; height : int; free : int; hash : int }
and node =
  | V of int
  | S of int
  | A of term * term
  | L of term * term
  | P of term * term
  | T of term * term * term

let mix_hash left right = ((left lxor right) * 65599) land max_int
let node_hash = function
  | V index -> mix_hash 1 index
  | S level -> mix_hash 2 level
  | A (a, b) -> mix_hash (mix_hash 3 a.hash) b.hash
  | L (a, b) -> mix_hash (mix_hash 4 a.hash) b.hash
  | P (a, b) -> mix_hash (mix_hash 5 a.hash) b.hash
  | T (a, b, c) -> mix_hash (mix_hash (mix_hash 6 a.hash) b.hash) c.hash

module Node_memo = Hashtbl.Make (struct
  type t = node
  let equal left right = match left, right with
    | V a, V b | S a, S b -> a = b
    | A (a, b), A (c, d) | L (a, b), L (c, d) | P (a, b), P (c, d) ->
        a == c && b == d
    | T (a, b, c), T (d, e, f) -> a == d && b == e && c == f
    | _ -> false
  let hash = node_hash
end)
module Term_depth_memo = Hashtbl.Make (struct
  type t = term * int
  let equal (a, d) (b, e) = a == b && d = e
  let hash (term, depth) = mix_hash term.hash depth
end)
module Infer_memo = Hashtbl.Make (struct
  type t = term * term list * int
  let equal (a, c, d) (b, e, f) = a == b && c == e && d = f
  let hash (term, context, depth) =
    mix_hash (mix_hash term.hash depth) (Hashtbl.hash context)
end)
module Term_memo = Hashtbl.Make (struct
  type t = term
  let equal a b = a == b
  let hash term = term.hash
end)

type meter = {
  mutable remaining : int;
  mutable saw_constant : bool;
  mutable nodes : term Node_memo.t option;
  mutable reads : (expr * term * int) option array option;
  mutable heads : (term * int) Term_depth_memo.t option;
  mutable normals : (term * int) Term_depth_memo.t option;
  mutable inferred : (term * int) Infer_memo.t option;
  mutable closed_types : (term * int) Term_memo.t option;
}

let budget remaining =
  { remaining; saw_constant = false; nodes = None; reads = None;
    heads = None; normals = None; inferred = None; closed_types = None }

let spend tick amount =
  guard (amount >= 0 && tick.remaining >= amount) Limit_exceeded;
  tick.remaining <- tick.remaining - amount

let make tick node =
  let children = match node with
    | V _ | S _ -> 0
    | A (a, b) | L (a, b) | P (a, b) -> max a.height b.height
    | T (a, b, c) -> max a.height (max b.height c.height)
  in
  let height = children + 1 in
  guard (height <= max_height) Height_limit;
  let cache = match tick.nodes with
    | Some cache -> cache
    | None -> let cache = Node_memo.create 32 in tick.nodes <- Some cache; cache
  in
  match Node_memo.find_opt cache node with
  | Some term -> term
  | None ->
      let free = match node with
        | V index -> index
        | S _ -> -1
        | A (a, b) -> max a.free b.free
        | L (a, b) | P (a, b) -> max a.free (b.free - 1)
        | T (a, b, c) -> max (max a.free b.free) (c.free - 1)
      in
      let term = { node; height; free; hash = node_hash node } in
      Node_memo.add cache node term;
      term

(* Reuse only successful computations, with their complete old logical charge.
   If a charge cannot fit, replay the original traversal to preserve the refusal
   reached at that budget. Public keys use identity and bounded hashing. *)
let memo_read tick expression scope depth height compute =
  match expression with
  | Var _ | Sort _ | Const _ -> compute ()
  | _ ->
      let cache = match tick.reads with
        | Some cache -> cache
        | None -> let cache = Array.make 256 None in tick.reads <- Some cache; cache
      in
      let slot = Hashtbl.hash expression land 255 in
      match cache.(slot) with
      | Some (key, result, cost)
        when key == expression && tick.remaining >= cost &&
             (result.free < depth || result.free - depth < scope) &&
             result.height <= max_height - height + 1 ->
          spend tick cost; result
      | _ ->
          let before = tick.remaining in
          let result = compute () in
          cache.(slot) <- Some (expression, result, before - tick.remaining);
          result

let memo_head tick key compute =
  let cache = match tick.heads with
    | Some cache -> cache
    | None -> let cache = Term_depth_memo.create 32 in tick.heads <- Some cache; cache
  in
  match Term_depth_memo.find_opt cache key with
  | Some (result, cost) when tick.remaining >= cost -> spend tick cost; result
  | _ ->
      let before = tick.remaining in
      let result = compute () in
      Term_depth_memo.replace cache key (result, before - tick.remaining);
      result

let memo_normal tick key compute =
  let cache = match tick.normals with
    | Some cache -> cache
    | None -> let cache = Term_depth_memo.create 32 in tick.normals <- Some cache; cache
  in
  match Term_depth_memo.find_opt cache key with
  | Some (result, cost) when tick.remaining >= cost -> spend tick cost; result
  | _ ->
      let before = tick.remaining in
      let result = compute () in
      Term_depth_memo.replace cache key (result, before - tick.remaining);
      result

let memo_infer tick key compute =
  let cache = match tick.inferred with
    | Some cache -> cache
    | None -> let cache = Infer_memo.create 32 in tick.inferred <- Some cache; cache
  in
  match Infer_memo.find_opt cache key with
  | Some (result, cost) when tick.remaining >= cost -> spend tick cost; result
  | _ ->
      let before = tick.remaining in
      let result = compute () in
      Infer_memo.replace cache key (result, before - tick.remaining);
      result

let closed_type_cache tick =
  match tick.closed_types with
  | Some cache -> cache
  | None ->
      let cache = Term_memo.create 16 in
      tick.closed_types <- Some cache;
      cache

let memo_closed_type tick term compute =
  let cache = closed_type_cache tick in
  match Term_memo.find_opt cache term with
  | Some (result, cost) when tick.remaining >= cost -> spend tick cost; result
  | _ ->
      let before = tick.remaining in
      let result = compute () in
      Term_memo.replace cache term (result, before - tick.remaining);
      result

let unknown _ = raise (Refusal Unknown_constant)

(* Validation includes erased children. Subtraction avoids overflow when the
   ambient scope is near max_int. *)
let read ?(constant = unknown) tick scope expression =
  guard (scope >= 0) Invalid_scope;
  let rec visit depth height expression =
    memo_read tick expression scope depth height (fun () ->
    guard (height <= max_height) Height_limit;
    spend tick 1;
    let here = visit depth (height + 1) in
    let under = visit (depth + 1) (height + 1) in
    match expression with
    | Var index ->
        guard (index >= 0 && (index < depth || index - depth < scope)) Invalid_scope;
        make tick (V index)
    | Sort level ->
        guard (level >= 0) Invalid_universe;
        make tick (S level)
    | Const name -> constant name
    | App (f, x) ->
        let f = here f in
        let x = here x in
        make tick (A (f, x))
    | Lam (domain, body) ->
        let domain = here domain in
        let body = under body in
        make tick (L (domain, body))
    | Pi (domain, body) ->
        let domain = here domain in
        let body = under body in
        make tick (P (domain, body))
    | Let (ty, value, body) ->
        let ty = here ty in
        let value = here value in
        let body = under body in
        make tick (T (ty, value, body)))
  in
  visit 0 1 expression

let rec write tick term =
  spend tick 1;
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

let rec map tick variable depth term =
  spend tick 1;
  let here = map tick variable depth in
  let under = map tick variable (depth + 1) in
  match term.node with
  | V index -> variable depth index
  | S _ -> term
  | A (f, x) ->
      let f = here f in
      let x = here x in
      make tick (A (f, x))
  | L (domain, body) ->
      let domain = here domain in
      let body = under body in
      make tick (L (domain, body))
  | P (domain, body) ->
      let domain = here domain in
      let body = under body in
      make tick (P (domain, body))
  | T (ty, value, body) ->
      let ty = here ty in
      let value = here value in
      let body = under body in
      make tick (T (ty, value, body))

let lift tick amount =
  map tick (fun cutoff index ->
    if index < cutoff then make tick (V index)
    else (
      guard (index <= max_int - amount) Index_overflow;
      make tick (V (index + amount)))) 0

let substitute tick replacement body =
  map tick (fun depth index ->
    if index < depth then make tick (V index)
    else if index > depth then make tick (V (index - 1))
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

(* Tail reductions retain evaluator depth and remain host-language tail calls. *)
let rec head tick depth term =
  match term.node with
  | V _ | S _ | L _ | P _ -> head_core tick depth term
  | A _ | T _ -> memo_head tick (term, depth) (fun () -> head_core tick depth term)
and head_core tick depth term =
  guard (depth <= max_height) Height_limit;
  spend tick 1;
  match term.node with
  | T (_, value, body) -> head_core tick depth (substitute tick value body)
  | A (f, x) ->
      let f = head tick (depth + 1) f in
      (match f.node with
      | L (_, body) -> head_core tick depth (substitute tick x body)
      | _ -> make tick (A (f, x)))
  | _ -> term

let rec normal tick depth term =
  match term.node with
  | V _ | S _ ->
      guard (depth <= max_height) Height_limit;
      spend tick 1;
      term
  | _ -> memo_normal tick (term, depth) (fun () ->
      match (head tick depth term).node with
      | A (f, x) ->
          let f = normal tick (depth + 1) f in
          let x = normal tick (depth + 1) x in
          make tick (A (f, x))
      | L (ty, body) ->
          let ty = normal tick (depth + 1) ty in
          let body = normal tick (depth + 1) body in
          make tick (L (ty, body))
      | P (ty, body) ->
          let ty = normal tick (depth + 1) ty in
          let body = normal tick (depth + 1) body in
          make tick (P (ty, body))
      | (V _ | S _) as node -> make tick node
      | T (_, value, body) -> normal tick depth (substitute tick value body))

let rec equal tick left right =
  spend tick 1;
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

(* Each context entry is scoped in the tail present when it was added. *)
let infer_type tick term =
  match term.node with
  | S level ->
      spend tick 1;
      guard (level < max_int) Index_overflow;
      let result = make tick (S (level + 1)) in
      spend tick 1;
      result
  | _ -> memo_closed_type tick term (fun () ->
      let rec lookup context index =
        spend tick 1;
        match context with
        | [] -> raise (Refusal Invalid_scope)
        | ty :: _ when index = 0 -> ty
        | _ :: tail -> lookup tail (index - 1)
      in
      let rec infer depth context term =
        match term.node with
        | V _ | S _ -> infer_core depth context term
        | _ ->
            let cache_context = if term.free < 0 then [] else context in
            memo_infer tick (term, cache_context, depth)
              (fun () -> infer_core depth context term)
      and infer_core depth context term =
        guard (depth <= max_height) Height_limit;
        spend tick 1;
        match term.node with
        | V index ->
            guard (index < max_int) Index_overflow;
            lift tick (index + 1) (lookup context index)
        | S level ->
            guard (level < max_int) Index_overflow;
            make tick (S (level + 1))
        | L (domain, body) ->
            ignore (sort_level (depth + 1) context domain);
            let body_type = infer (depth + 1) (domain :: context) body in
            make tick (P (domain, body_type))
        | P (domain, body) ->
            let input = sort_level (depth + 1) context domain in
            let output = sort_level (depth + 1) (domain :: context) body in
            make tick (S (if output = 0 then 0 else max input output))
        | A (fn, arg) ->
            (match (head tick 1 (infer (depth + 1) context fn)).node with
            | P (domain, body) ->
                check (depth + 1) context arg domain;
                substitute tick arg body
            | _ -> raise (Refusal Expected_function))
        | T (ty, value, body) ->
            ignore (sort_level (depth + 1) context ty);
            check (depth + 1) context value ty;
            infer_core depth context (substitute tick value body)
      and sort_level depth context term =
        match (head tick 1 (infer depth context term)).node with
        | S level -> level
        | _ -> raise (Refusal Expected_sort)
      and check depth context term expected =
        let actual = normal tick 1 (infer depth context term) in
        let expected = normal tick 1 expected in
        guard (equal tick actual expected) Type_mismatch
      in
      normal tick 1 (infer 1 [] term))

let infer_closed ~fuel expression =
  protect (fun () ->
    let tick = budget fuel in
    let term = read tick 0 expression in
    write tick (infer_type tick term))

type checked_value = { value : term; value_type : term; inference_cost : int }
module Definition_index = Map.Make (String)
type environment = {
  entries : (string * checked_value) list;
  index : (int * checked_value) Definition_index.t;
  size : int;
}
let empty_environment = { entries = []; index = Definition_index.empty; size = 0 }
let extend env name value =
  { entries = (name, value) :: env.entries;
    index = Definition_index.add name (env.size, value) env.index;
    size = env.size + 1 }

let find_definition tick name env =
  (* Immutable insertion ordinals recover the exact old list lookup charge. *)
  match Definition_index.find_opt name env.index with
  | Some (ordinal, value) -> spend tick (env.size - ordinal); Some value
  | None ->
      guard (env.size < max_int) Limit_exceeded;
      spend tick (env.size + 1);
      None

let expand tick env expression =
  let constant name =
    tick.saw_constant <- true;
    match find_definition tick name env with
    | Some checked ->
        (match checked.value.node with
         | S _ -> ()
         | _ -> Term_memo.replace (closed_type_cache tick) checked.value
             (checked.value_type, checked.inference_cost));
        checked.value
    | None -> raise (Refusal Unknown_constant)
  in
  read ~constant tick 0 expression
let infer_in ~fuel env expression =
  protect (fun () ->
    let tick = budget fuel in
    let term = expand tick env expression in
    write tick (infer_type tick term))

(* Only successful annotations with no constant occurrence in their original
   imported syntax may cross parent snapshots. Each stage retains its charge. *)
type checked_annotation = {
  source : expr;
  imported_type : term;
  import_cost : int;
  type_sort : term;
  type_cost : int;
  normalized_type : term;
  normal_cost : int;
}
type checking_cache = checked_annotation option array
let create_checking_cache () = Array.make 256 None

let make_definition_checker ?cache env =
  let checked = ref None in
  fun ~fuel ~name ~ty ~value ->
    protect (fun () ->
      let tick = budget fuel in
      guard (name <> "") Invalid_name;
      guard (find_definition tick name env = None) Duplicate_definition;
      let result = match !checked with
        | Some (saved_type, saved_value, result, cost)
          when saved_type == ty && saved_value == value && tick.remaining >= cost ->
            spend tick cost; result
        | _ ->
            let before = tick.remaining in
            let source_type = ty in
            let source_value = value in
            let annotation_slot = Hashtbl.hash source_type land 255 in
            let annotation = match cache with
              | Some cache ->
                  (match cache.(annotation_slot) with
                   | Some saved when saved.source == source_type -> Some saved
                   | _ -> None)
              | None -> None
            in
            let before_import = tick.remaining in
            let ty = match annotation with
              | Some saved when tick.remaining >= saved.import_cost ->
                  spend tick saved.import_cost; saved.imported_type
              | _ -> expand tick env ty
            in
            let import_cost = before_import - tick.remaining in
            let constant_free = not tick.saw_constant in
            let value = expand tick env value in
            let before_type = tick.remaining in
            let ty_sort = match annotation with
              | Some saved when tick.remaining >= saved.type_cost ->
                  spend tick saved.type_cost; saved.type_sort
              | _ -> infer_type tick ty
            in
            let type_cost = before_type - tick.remaining in
            (match ty_sort.node with S _ -> () | _ -> raise (Refusal Expected_sort));
            let before_infer = tick.remaining in
            let actual = infer_type tick value in
            let inference_cost = before_infer - tick.remaining in
            let before_normal = tick.remaining in
            let expected = match annotation with
              | Some saved when tick.remaining >= saved.normal_cost ->
                  spend tick saved.normal_cost; saved.normalized_type
              | _ -> normal tick 1 ty
            in
            let normal_cost = before_normal - tick.remaining in
            guard (equal tick actual expected) Type_mismatch;
            (match cache with
             | Some cache when constant_free ->
                 cache.(annotation_slot) <- Some {
                   source = source_type; imported_type = ty; import_cost;
                   type_sort = ty_sort; type_cost;
                   normalized_type = expected; normal_cost }
             | _ -> ());
            let result = { value; value_type = actual; inference_cost } in
            checked := Some (source_type, source_value, result, before - tick.remaining);
            result
      in
      extend env name result)
let define ~fuel env ~name ~ty ~value =
  make_definition_checker env ~fuel ~name ~ty ~value

type merge_error = Invalid_branch | Duplicate_branch | Merge_limit_exceeded
exception Merge_refusal of merge_error
let merge_checked_branches ~fuel ~base branches =
  let remaining = ref fuel in
  let tick () =
    if !remaining <= 0 then raise (Merge_refusal Merge_limit_exceeded);
    decr remaining
  in
  let rec collect names heads = function
    | [] ->
        List.fold_left (fun env (name, value) -> tick (); extend env name value)
          base (List.rev heads)
    | branch :: rest ->
        tick ();
        (match branch.entries with
        | ((name, _) as binding) :: parent when parent == base.entries ->
            if Hashtbl.mem names name then raise (Merge_refusal Duplicate_branch);
            Hashtbl.add names name ();
            collect names (binding :: heads) rest
        | _ -> raise (Merge_refusal Invalid_branch))
  in
  try
    tick ();
    match branches with
    | [] -> Ok base
    | [branch] ->
        tick ();
        (match branch.entries with
         | binding :: parent when parent == base.entries ->
             tick ();
             (* A fresh entry head preserves later exact-parent observations. *)
             Ok { entries = binding :: base.entries;
                  index = branch.index; size = branch.size }
         | _ -> Error Invalid_branch)
    | _ -> Ok (collect (Hashtbl.create 16) [] branches)
  with Merge_refusal error -> Error error
