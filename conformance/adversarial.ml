open Conversion

(* These are executable controls for the bounded, untyped expression fragment.
   They are not a Lean compatibility proof or a second typing oracle. *)
let fuel = 1_000_000
let controls = ref 0
let disagreements = ref 0
let generated_cases = ref 0
let generated_assertions = ref 0

let error_name = function
  | Invalid_scope -> "Invalid_scope"
  | Invalid_universe -> "Invalid_universe"
  | Limit_exceeded -> "Limit_exceeded"
  | Height_limit -> "Height_limit"
  | Index_overflow -> "Index_overflow"
  | Expected_sort -> "Expected_sort"
  | Expected_function -> "Expected_function"
  | Type_mismatch -> "Type_mismatch"
  | Unknown_constant -> "Unknown_constant"
  | Duplicate_definition -> "Duplicate_definition"
  | Invalid_name -> "Invalid_name"

let fail label message = failwith (label ^ ": " ^ message)

let expect_error label expected = function
  | Error actual when actual = expected -> ()
  | Error actual ->
      fail label ("expected " ^ error_name expected ^ ", got " ^ error_name actual)
  | Ok _ -> fail label ("expected " ^ error_name expected ^ ", got success")

let expect_ok label expected = function
  | Ok actual when actual = expected -> ()
  | Ok _ -> fail label "successful result differs from expected result"
  | Error error -> fail label ("unexpected refusal: " ^ error_name error)

let unwrap label = function
  | Ok value -> value
  | Error error -> fail label ("unexpected refusal: " ^ error_name error)

let control label check =
  check label;
  incr controls

let disagreement label left right =
  expect_ok label false (beta_zeta_equal ~fuel left right);
  incr disagreements

let rec lambdas count body =
  if count = 0 then body else lambdas (count - 1) (Lam (Sort 0, body))

let identity = Lam (Sort 1, Var 0)
let delta = Lam (Sort 0, App (Var 0, Var 0))
let omega = App (delta, delta)

let scope_and_machine_integer_controls () =
  control "negative bound-variable index" (fun label ->
    expect_error label Invalid_scope (validate_scope ~fuel ~scope:0 (Var (-1))));
  control "minimum machine-integer variable" (fun label ->
    expect_error label Invalid_scope (validate_scope ~fuel ~scope:1 (Var min_int)));
  control "negative universe" (fun label ->
    expect_error label Invalid_universe (validate_scope ~fuel ~scope:0 (Sort (-1))));
  control "minimum machine-integer universe" (fun label ->
    expect_error label Invalid_universe (normalize ~fuel ~scope:0 (Sort min_int)));
  control "negative ambient scope" (fun label ->
    expect_error label Invalid_scope (validate_scope ~fuel ~scope:(-1) (Sort 0)));
  control "negative instantiation scope" (fun label ->
    expect_error label Invalid_scope
      (instantiate ~fuel ~scope:(-1) ~body:(Var 0) (Sort 0)));
  control "closed free variable" (fun label ->
    expect_error label Invalid_scope (whnf ~fuel (Var 0)));
  control "variable exactly outside open scope" (fun label ->
    expect_error label Invalid_scope (normalize ~fuel ~scope:3 (Var 3)));
  control "maximum machine-integer variable outside maximum scope" (fun label ->
    expect_error label Invalid_scope
      (validate_scope ~fuel ~scope:max_int (Var max_int)));
  control "large valid open scope does not wrap" (fun label ->
    expect_ok label ()
      (validate_scope ~fuel ~scope:max_int (Var (max_int - 1))));
  control "maximum numeric universe is syntactically valid" (fun label ->
    expect_ok label (Sort max_int) (normalize ~fuel ~scope:0 (Sort max_int)));
  control "scope increment overflow refuses instantiation" (fun label ->
    expect_error label Index_overflow
      (instantiate ~fuel ~scope:max_int ~body:(Var 0) (Sort 0)));
  control "lifting a valid open replacement cannot wrap" (fun label ->
    expect_error label Index_overflow
      (instantiate ~fuel ~scope:(max_int - 1)
         ~body:(lambdas 3 (Var 3)) (Var (max_int - 2))));
  control "lambda domain is outside its own binder" (fun label ->
    expect_error label Invalid_scope
      (validate_scope ~fuel ~scope:0 (Lam (Var 0, Var 0))));
  control "Pi domain is outside its own binder" (fun label ->
    expect_error label Invalid_scope
      (validate_scope ~fuel ~scope:0 (Pi (Var 0, Var 0))));
  control "let value is outside its own binder" (fun label ->
    expect_error label Invalid_scope
      (validate_scope ~fuel ~scope:0 (Let (Sort 1, Var 0, Var 0))));
  control "let annotation is outside its own binder" (fun label ->
    expect_error label Invalid_scope
      (validate_scope ~fuel ~scope:0 (Let (Var 0, Sort 0, Var 0))));
  control "lambda body is inside its binder" (fun label ->
    expect_ok label () (validate_scope ~fuel ~scope:0 (Lam (Sort 0, Var 0))));
  control "Pi body is inside its binder" (fun label ->
    expect_ok label () (validate_scope ~fuel ~scope:0 (Pi (Sort 1, Var 0))));
  control "open weak-head operation uses supplied scope" (fun label ->
    expect_ok label (Var 0) (whnf_in ~fuel ~scope:1 (App (identity, Var 0))));
  control "open equality uses supplied scope" (fun label ->
    expect_ok label true
      (beta_zeta_equal_in ~fuel ~scope:1 (App (identity, Var 0)) (Var 0)))

let substitution_and_sharing_controls () =
  control "substitution lifts an open variable under lambda" (fun label ->
    expect_ok label (Lam (Sort 0, Var 1))
      (instantiate ~fuel ~scope:1 ~body:(Lam (Sort 0, Var 1)) (Var 0)));
  control "substitution lifts an open variable under Pi" (fun label ->
    expect_ok label (Pi (Sort 0, Var 1))
      (instantiate ~fuel ~scope:1 ~body:(Pi (Sort 0, Var 1)) (Var 0)));
  control "substitution decrements variables beyond removed binder" (fun label ->
    expect_ok label (Var 1)
      (instantiate ~fuel ~scope:2 ~body:(Var 2) (Var 0)));
  control "substitution distinguishes domain and body depth" (fun label ->
    expect_ok label (Lam (Var 0, App (Sort 2, Var 0)))
      (instantiate ~fuel ~scope:1
         ~body:(Lam (Var 1, App (Var 1, Var 0))) (Sort 2)));
  control "substitution leaves inner bound variables unchanged" (fun label ->
    expect_ok label (Lam (Sort 0, Var 0))
      (instantiate ~fuel ~scope:0 ~body:(Lam (Sort 0, Var 0)) (Sort 2)));
  control "substitution distinguishes let annotation value and body" (fun label ->
    expect_ok label (Let (Sort 2, Sort 2, App (Sort 2, Var 0)))
      (instantiate ~fuel ~scope:0
         ~body:(Let (Var 0, Var 0, App (Var 1, Var 0))) (Sort 2)));
  control "replacement is validated even when unused" (fun label ->
    expect_error label Invalid_scope
      (instantiate ~fuel ~scope:0 ~body:(Sort 0) (Var 0)));
  control "substitution body is validated before replacement" (fun label ->
    expect_error label Invalid_scope
      (instantiate ~fuel ~scope:0 ~body:(Var 1) (Sort 0)));
  control "shared Var node is rechecked at a shallower binder depth" (fun label ->
    let shared = Var 0 in
    expect_error label Invalid_scope
      (validate_scope ~fuel ~scope:0 (App (Lam (Sort 0, shared), shared))));
  control "shared Var node is rechecked across two nonzero depths" (fun label ->
    let shared = Var 1 in
    expect_error label Invalid_scope
      (validate_scope ~fuel ~scope:0
         (App (Lam (Sort 0, Lam (Sort 0, shared)), Lam (Sort 0, shared)))));
  control "shared Var substitution depends on occurrence depth" (fun label ->
    let shared = Var 1 in
    expect_ok label (App (Lam (Sort 0, Sort 2), Var 0))
      (instantiate ~fuel ~scope:1 ~body:(App (Lam (Sort 0, shared), shared))
         (Sort 2)));
  control "physical identity cannot bypass invalid scope" (fun label ->
    let shared = Var 0 in
    expect_error label Invalid_scope (beta_zeta_equal ~fuel shared shared));
  control "physical identity cannot bypass invalid universe" (fun label ->
    let shared = Sort (-1) in
    expect_error label Invalid_universe (beta_zeta_equal ~fuel shared shared))

let erasure_and_fragment_controls () =
  control "discarded beta argument is scope checked" (fun label ->
    expect_error label Invalid_scope
      (whnf ~fuel (App (Lam (Sort 1, Sort 0), Var 0))));
  control "discarded beta domain is universe checked" (fun label ->
    expect_error label Invalid_universe
      (whnf ~fuel (App (Lam (Sort (-1), Var 0), Sort 0))));
  control "discarded let annotation is scope checked" (fun label ->
    expect_error label Invalid_scope
      (whnf ~fuel (Let (Var 0, Sort 0, Sort 0))));
  control "discarded let value is scope checked" (fun label ->
    expect_error label Invalid_scope
      (whnf ~fuel (Let (Sort 1, Var 0, Sort 0))));
  control "discarded let annotation is universe checked" (fun label ->
    expect_error label Invalid_universe
      (whnf ~fuel (Let (Sort (-1), Sort 0, Sort 0))));
  control "bare constants require an environment" (fun label ->
    expect_error label Unknown_constant (whnf ~fuel (Const "untrusted")));
  control "discarded constant beta argument is rejected" (fun label ->
    expect_error label Unknown_constant
      (whnf ~fuel (App (Lam (Sort 1, Sort 0), Const "untrusted"))));
  control "discarded constant beta domain is rejected" (fun label ->
    expect_error label Unknown_constant
      (whnf ~fuel (App (Lam (Const "untrusted", Var 0), Sort 0))));
  control "discarded constant let annotation is rejected" (fun label ->
    expect_error label Unknown_constant
      (whnf ~fuel (Let (Const "untrusted", Sort 0, Sort 0))));
  control "discarded constant let value is rejected" (fun label ->
    expect_error label Unknown_constant
      (normalize ~fuel ~scope:0 (Let (Sort 1, Const "untrusted", Sort 0))));
  control "same constant object cannot bypass unsupported-feature check" (fun label ->
    let shared = Const "untrusted" in
    expect_error label Unknown_constant (beta_zeta_equal ~fuel shared shared));
  control "bounded conversion does not pretend to type check" (fun label ->
    let ill_typed = App (Sort 0, Sort 0) in
    expect_ok label ill_typed (normalize ~fuel ~scope:0 ill_typed));
  control "weak-head reduction stops under lambda" (fun label ->
    let term = Lam (Sort 1, App (identity, Sort 0)) in
    expect_ok label term (whnf ~fuel term));
  control "normalization reduces under lambda" (fun label ->
    expect_ok label (Lam (Sort 1, Sort 0))
      (normalize ~fuel ~scope:0 (Lam (Sort 1, App (identity, Sort 0)))));
  control "normalization reduces Pi domain and body" (fun label ->
    expect_ok label (Pi (Sort 1, Sort 0))
      (normalize ~fuel ~scope:0
         (Pi (App (identity, Sort 1), App (identity, Sort 0)))));
  control "weak-head reduction leaves a neutral argument unreduced" (fun label ->
    let term = App (Sort 0, App (identity, Sort 0)) in
    expect_ok label term (whnf ~fuel term));
  control "normalization reduces a neutral argument" (fun label ->
    expect_ok label (App (Sort 0, Sort 0))
      (normalize ~fuel ~scope:0 (App (Sort 0, App (identity, Sort 0)))));
  control "unused divergent beta argument is not evaluated" (fun label ->
    expect_ok label (Sort 0)
      (normalize ~fuel ~scope:0 (App (Lam (Sort 1, Sort 0), omega))));
  control "unused divergent let value is not evaluated" (fun label ->
    expect_ok label (Sort 0)
      (normalize ~fuel ~scope:0 (Let (Sort 1, omega, Sort 0))))

let resource_controls () =
  control "zero validation budget" (fun label ->
    expect_error label Limit_exceeded (validate_scope ~fuel:0 ~scope:0 (Sort 0)));
  control "negative validation budget" (fun label ->
    expect_error label Limit_exceeded (validate_scope ~fuel:(-1) ~scope:0 (Sort 0)));
  control "minimum machine-integer budget" (fun label ->
    expect_error label Limit_exceeded
      (validate_scope ~fuel:min_int ~scope:0 (Sort 0)));
  control "zero weak-head budget" (fun label ->
    expect_error label Limit_exceeded (whnf ~fuel:0 (Sort 0)));
  control "zero instantiation budget" (fun label ->
    expect_error label Limit_exceeded
      (instantiate ~fuel:0 ~scope:0 ~body:(Var 0) (Sort 0)));
  control "zero normalization budget" (fun label ->
    expect_error label Limit_exceeded (normalize ~fuel:0 ~scope:0 (Sort 0)));
  control "physical equality still requires a positive budget" (fun label ->
    let shared = Sort 0 in
    expect_error label Limit_exceeded (beta_zeta_equal ~fuel:0 shared shared));
  control "work budget bounds traversal of a shared binary DAG" (fun label ->
    let rec dag depth term =
      if depth = 0 then term else dag (depth - 1) (App (term, term))
    in
    expect_error label Limit_exceeded
      (validate_scope ~fuel:1_000 ~scope:0 (dag 20 (Sort 0))));
  control "divergent weak-head evaluation exhausts work budget" (fun label ->
    expect_error label Limit_exceeded (whnf ~fuel:1_000 omega));
  control "divergent normalization exhausts work budget" (fun label ->
    expect_error label Limit_exceeded (normalize ~fuel:1_000 ~scope:0 omega));
  control "self comparison of omega is inconclusive" (fun label ->
    expect_error label Limit_exceeded (beta_zeta_equal ~fuel:1_000 omega omega));
  control "divergent comparison is not reported as inequality" (fun label ->
    expect_error label Limit_exceeded
      (beta_zeta_equal ~fuel:1_000 omega (Sort 0)));
  control "different completed normal forms are a boolean inequality" (fun label ->
    expect_ok label false (beta_zeta_equal ~fuel (Sort 0) (Sort 1)));
  control "height 128 input succeeds with leaf height one" (fun label ->
    expect_ok label () (validate_scope ~fuel ~scope:0 (lambdas 127 (Sort 0))));
  control "height 129 input is a height refusal" (fun label ->
    expect_error label Height_limit
      (validate_scope ~fuel ~scope:0 (lambdas 128 (Sort 0))));
  control "very deep caller AST is refused before stack exhaustion" (fun label ->
    expect_error label Height_limit
      (whnf ~fuel (lambdas 10_000 (Sort 0))));
  control "cyclic lambda created by OCaml let-rec is refused" (fun label ->
    let rec cyclic = Lam (Sort 0, cyclic) in
    expect_error label Height_limit (validate_scope ~fuel ~scope:0 cyclic));
  control "cyclic application created by OCaml let-rec is refused" (fun label ->
    let rec cyclic = App (cyclic, Sort 0) in
    expect_error label Height_limit (whnf ~fuel cyclic));
  control "cyclic let body is refused before erasure" (fun label ->
    let rec cyclic = Let (Sort 1, Sort 0, cyclic) in
    expect_error label Height_limit (normalize ~fuel ~scope:0 cyclic));
  control "intermediate substitution height is bounded" (fun label ->
    expect_error label Height_limit
      (instantiate ~fuel ~scope:0 ~body:(lambdas 80 (Var 80))
         (lambdas 60 (Sort 0))));
  control "intermediate beta result height is bounded" (fun label ->
    expect_error label Height_limit
      (whnf ~fuel
         (App (Lam (Sort 1, lambdas 80 (Var 80)), lambdas 60 (Sort 0)))));
  control "intermediate zeta result height is bounded" (fun label ->
    expect_error label Height_limit
      (whnf ~fuel
         (Let (Sort 1, lambdas 60 (Sort 0), lambdas 80 (Var 80)))))

let known_disagreement_controls () =
  (* Lean identifies these pairs using rules deliberately absent here. These
     successful controls mean the restriction is preserved, not correspondence. *)
  disagreement "function eta remains outside beta-zeta conversion"
    (Lam (Pi (Sort 0, Sort 0), Var 0))
    (Lam (Pi (Sort 0, Sort 0), Lam (Sort 0, App (Var 1, Var 0))));
  disagreement "proof irrelevance remains outside beta-zeta conversion"
    (Lam (Sort 0, Lam (Var 0, Lam (Var 1, Var 1))))
    (Lam (Sort 0, Lam (Var 0, Lam (Var 1, Var 0))))

(* Fixed integer recurrence with Int64 arithmetic gives the same corpus on
   different OCaml integer widths; it does not depend on Random's implementation.
   Generated terms are scoped beta-zeta normal forms, not necessarily well typed. *)
let generator_state = ref 0x4c45414eL

let next bound =
  generator_state :=
    Int64.logand 0x7fffffffL
      (Int64.add (Int64.mul !generator_state 1_103_515_245L) 12_345L);
  Int64.to_int (Int64.rem !generator_state (Int64.of_int bound))

let leaf scope =
  if scope > 0 && next 3 = 0 then Var (next scope) else Sort (next 3)

let rec generated_normal depth scope =
  if depth = 0 then leaf scope
  else
    match next 5 with
    | 0 | 1 -> leaf scope
    | 2 ->
        let domain = generated_normal (depth - 1) scope in
        let body = generated_normal (depth - 1) (scope + 1) in
        Lam (domain, body)
    | 3 ->
        let domain = generated_normal (depth - 1) scope in
        let body = generated_normal (depth - 1) (scope + 1) in
        Pi (domain, body)
    | _ ->
        (* A variable or sort head is neutral, so this creates no beta redex. *)
        let head = leaf scope in
        let argument = generated_normal (depth - 1) scope in
        App (head, argument)

let generated_properties () =
  let property index name expected actual =
    expect_ok (Printf.sprintf "generated case %d: %s" index name) expected actual;
    incr generated_assertions
  in
  for index = 0 to 1023 do
    let scope = index mod 5 in
    let term = generated_normal (index mod 7) scope in
    let normal = unwrap "generated normalization" (normalize ~fuel ~scope term) in
    let beta = App (identity, term) in
    let zeta = Let (Sort 1, term, Var 0) in
    (* A proper neutral extension is structurally distinct from the original
       finite normal form. Both directions must complete with false, not error. *)
    let different = App (Sort 0, term) in
    property index "input scope" () (validate_scope ~fuel ~scope term);
    property index "normalization stability" term (normalize ~fuel ~scope term);
    property index "normal output scope" () (validate_scope ~fuel ~scope normal);
    property index "normalization idempotence" normal (normalize ~fuel ~scope normal);
    property index "beta expansion" term (normalize ~fuel ~scope beta);
    property index "zeta expansion" term (normalize ~fuel ~scope zeta);
    property index "beta-zeta conversion" true
      (beta_zeta_equal_in ~fuel ~scope beta zeta);
    property index "conversion symmetry" true
      (beta_zeta_equal_in ~fuel ~scope zeta beta);
    property index "distinct normal forms" false
      (beta_zeta_equal_in ~fuel ~scope term different);
    property index "inequality symmetry" false
      (beta_zeta_equal_in ~fuel ~scope different term);
    incr generated_cases
  done

let () =
  scope_and_machine_integer_controls ();
  substitution_and_sharing_controls ();
  erasure_and_fragment_controls ();
  resource_controls ();
  known_disagreement_controls ();
  generated_properties ();
  if !controls <> 75 || !disagreements <> 2 ||
     !generated_cases <> 1024 || !generated_assertions <> 10240
  then failwith "incomplete adversarial/property test inventory";
  Printf.printf
    "adversarial: %d controls passed; known-disagreement: %d controls passed; generated: %d deterministic cases / %d property assertions passed\n"
    !controls !disagreements !generated_cases !generated_assertions
