(** Non-authoritative observations for a bounded Lean expression fragment.
    These operations do not import or admit Lean declarations. *)
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

(** Maximum expression height, with a leaf at height one. Input, intermediate
    and result trees obey this bound; active evaluator contexts are bounded too. *)
val max_height : int

(** Validates every child at the given nonnegative ambient binder scope.
    Numeric sorts must be nonnegative. Bare conversion rejects [Const] with
    [Unknown_constant]; named unfolding belongs to [infer_in] below.
    A shared operation budget charges input visits, reduction/substitution,
    normalization, structural comparison and result export. Exhaustion, including
    zero or negative fuel, is [Limit_exceeded], never inequality. [Limit_exceeded]
    also serves as a defensive refusal for a runtime stack overflow.
    Cyclic public OCaml values terminate with a height or fuel refusal.
    Integer lifting/successor overflow is [Index_overflow]. *)
val validate_scope : fuel:int -> scope:int -> expr -> (unit, error) result

(** Remove one binder without capture. [body] is scoped in [scope + 1], while
    the replacement is scoped in [scope]. Body and replacement are validated
    before substitution. [scope = max_int] refuses with [Index_overflow]. *)
val instantiate :
  fuel:int -> scope:int -> body:expr -> expr -> (expr, error) result

(** Head beta/zeta reduction, following function positions only. *)
val whnf_in : fuel:int -> scope:int -> expr -> (expr, error) result
val whnf : fuel:int -> expr -> (expr, error) result

(** Full beta/zeta normalization; scoped syntax need not be well typed. *)
val normalize : fuel:int -> scope:int -> expr -> (expr, error) result

(** Compares beta/zeta normal forms. [Ok false] is an observation within this
    fragment, not a Lean non-convertibility certificate: eta and proof
    irrelevance are not implemented. Neither operand is type checked here.
    Both inputs are validated before reduction, and there is no physical
    identity shortcut; divergent self-comparisons can exhaust the budget. *)
val beta_zeta_equal_in : fuel:int -> scope:int -> expr -> expr -> (bool, error) result
val beta_zeta_equal : fuel:int -> expr -> expr -> (bool, error) result

(** Existing, separate reference typing path. Infers a closed term's normalized
    type using only beta/zeta conversion and numeric universe expressions. *)
val infer_closed : fuel:int -> expr -> (expr, error) result

(** Persistent, reference-only environment of transparent monomorphic definitions.
    It is not a Lean declaration-admission mechanism. *)
type environment

val empty_environment : environment
val define :
  fuel:int -> environment -> name:string -> ty:expr -> value:expr ->
  (environment, error) result
val infer_in : fuel:int -> environment -> expr -> (expr, error) result
