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

val instantiate :
  fuel:int -> scope:int -> body:expr -> expr -> (expr, error) result
val whnf : fuel:int -> expr -> (expr, error) result
val beta_zeta_equal : fuel:int -> expr -> expr -> (bool, error) result

(** Infers a closed term's normalized type using only β/ζ conversion. *)
val infer_closed : fuel:int -> expr -> (expr, error) result

(** Persistent, reference-only environment of transparent monomorphic definitions. *)
type environment

val empty_environment : environment
val define :
  fuel:int -> environment -> name:string -> ty:expr -> value:expr ->
  (environment, error) result
val infer_in : fuel:int -> environment -> expr -> (expr, error) result
