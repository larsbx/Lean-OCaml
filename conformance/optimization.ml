(* Fresh differential observations against the pinned pre-optimization sources.
   This checks regression compatibility, not independent kernel soundness. *)
module C = Conversion
module O = Old_conversion
module B = Definition_batch
module OB = Old_definition_batch

let generous = 1_000_000
let controls = ref 0
let assertions = ref 0
let check label condition =
  incr assertions;
  if not condition then failwith ("optimization differential: " ^ label)
let control label action = action label; incr controls
let unwrap label = function Ok value -> value | Error _ -> failwith (label ^ ": refused setup")

let old_error = function
  | O.Invalid_scope -> C.Invalid_scope | O.Invalid_universe -> C.Invalid_universe
  | O.Limit_exceeded -> C.Limit_exceeded | O.Height_limit -> C.Height_limit
  | O.Index_overflow -> C.Index_overflow | O.Expected_sort -> C.Expected_sort
  | O.Expected_function -> C.Expected_function | O.Type_mismatch -> C.Type_mismatch
  | O.Unknown_constant -> C.Unknown_constant
  | O.Duplicate_definition -> C.Duplicate_definition | O.Invalid_name -> C.Invalid_name

let error_name = function
  | C.Invalid_scope -> "Invalid_scope" | C.Invalid_universe -> "Invalid_universe"
  | C.Limit_exceeded -> "Limit_exceeded" | C.Height_limit -> "Height_limit"
  | C.Index_overflow -> "Index_overflow" | C.Expected_sort -> "Expected_sort"
  | C.Expected_function -> "Expected_function" | C.Type_mismatch -> "Type_mismatch"
  | C.Unknown_constant -> "Unknown_constant"
  | C.Duplicate_definition -> "Duplicate_definition" | C.Invalid_name -> "Invalid_name"

type syntax = V of int | S of int | K of string | A of syntax * syntax
  | L of syntax * syntax | P of syntax * syntax | T of syntax * syntax * syntax
let rec current_syntax = function
  | C.Var i -> V i | C.Sort i -> S i | C.Const n -> K n
  | C.App (a,b) -> A (current_syntax a,current_syntax b)
  | C.Lam (a,b) -> L (current_syntax a,current_syntax b)
  | C.Pi (a,b) -> P (current_syntax a,current_syntax b)
  | C.Let (a,b,c) -> T (current_syntax a,current_syntax b,current_syntax c)
let rec old_syntax = function
  | O.Var i -> V i | O.Sort i -> S i | O.Const n -> K n
  | O.App (a,b) -> A (old_syntax a,old_syntax b)
  | O.Lam (a,b) -> L (old_syntax a,old_syntax b)
  | O.Pi (a,b) -> P (old_syntax a,old_syntax b)
  | O.Let (a,b,c) -> T (old_syntax a,old_syntax b,old_syntax c)

module Public_nodes = Hashtbl.Make (struct
  type t = C.expr
  let equal a b = a == b
  let hash = Hashtbl.hash_param 10 20
end)
let old_converter () =
  let table = Public_nodes.create 64 in
  let rec convert term =
    match Public_nodes.find_opt table term with
    | Some converted -> converted
    | None ->
        let converted = match term with
          | C.Var i -> O.Var i | C.Sort i -> O.Sort i | C.Const n -> O.Const n
          | C.App (a,b) -> O.App (convert a,convert b)
          | C.Lam (a,b) -> O.Lam (convert a,convert b)
          | C.Pi (a,b) -> O.Pi (convert a,convert b)
          | C.Let (a,b,c) -> O.Let (convert a,convert b,convert c)
        in
        Public_nodes.add table term converted;
        converted
  in convert

let same_result label current_map prior_map current prior =
  match current,prior with
  | Ok actual,Ok expected -> check (label ^ ": complete result") (current_map actual = prior_map expected)
  | Error actual,Error expected ->
      let expected = old_error expected in
      check (label ^ ": " ^ error_name actual ^ " versus " ^ error_name expected) (actual = expected)
  | Ok _,Error expected -> check (label ^ ": accepted versus " ^ error_name (old_error expected)) false
  | Error actual,Ok _ -> check (label ^ ": " ^ error_name actual ^ " versus accepted") false

let same_expr label = same_result label current_syntax old_syntax
let same_unit label = same_result label Fun.id Fun.id
let same_bool label = same_result label Fun.id Fun.id
let grid = [-7;-1] @ List.init 161 Fun.id @ [191;200;255;256;511;512;1023;1024;4096;16384]
let sparse = [-1;0;1;2;3;5;8;13;21;34;55;89;144;233;377;610;1024;4096]

let rec lambdas count tail = if count = 0 then tail else C.Lam (C.Sort 1,lambdas (count-1) tail)
let rec products count tail = if count = 0 then tail else C.Pi (C.Sort 0,products (count-1) tail)
let rec pi_domains count tail = if count = 0 then tail else C.Pi (C.Sort 1,pi_domains (count-1) tail)
let rec beta count domain tail =
  if count = 0 then tail else beta (count-1) domain (C.App (C.Lam (domain,C.Var 0),tail))
let rec shared_tree count tail = if count = 0 then tail else
  let child = shared_tree (count-1) tail in C.Pi (child,child)

let core_case label budgets scope term prior =
  List.iter (fun fuel ->
    let at operation = Printf.sprintf "%s %s scope=%d fuel=%d" label operation scope fuel in
    same_unit (at "validate") (C.validate_scope ~fuel ~scope term) (O.validate_scope ~fuel ~scope prior);
    same_expr (at "whnf") (C.whnf_in ~fuel ~scope term) (O.whnf_in ~fuel ~scope prior);
    same_expr (at "normal") (C.normalize ~fuel ~scope term) (O.normalize ~fuel ~scope prior);
    same_bool (at "reflexivity")
      (C.beta_zeta_equal_in ~fuel ~scope term term)
      (O.beta_zeta_equal_in ~fuel ~scope prior prior);
    same_bool (at "comparison")
      (C.beta_zeta_equal_in ~fuel ~scope term (C.Sort 1))
      (O.beta_zeta_equal_in ~fuel ~scope prior (O.Sort 1));
    same_expr (at "inference") (C.infer_closed ~fuel term) (O.infer_closed ~fuel prior)) budgets

let core_controls () =
  let shared_open = C.App (C.Lam (C.Sort 1,C.Var 0),C.Var 0) in
  let context_witness =
    let first = C.App (C.Lam (C.Sort 1,C.Var 0),C.Var 0) in
    let second = C.App (C.Lam (C.Sort 1,C.Var 0),C.Var 0) in
    C.Let (C.Pi (C.Sort 1,C.Sort 1),C.Lam (C.Sort 1,first),
      C.Let (C.Pi (C.Sort 2,C.Sort 1),C.Lam (C.Sort 2,second),C.Sort 0))
  in
  let deep = products 36 (C.Sort 0) in
  let specs = [
    "sort zero",0,C.Sort 0; "sort successor",0,C.Sort 1;
    "negative universe",0,C.Sort (-1); "maximum universe",0,C.Sort max_int;
    "largest successful successor",0,C.Sort (max_int-1);
    "negative variable",1,C.Var (-1); "closed free variable",0,C.Var 0;
    "ambient variable",1,C.Var 0; "ambient edge",2,C.Var 2;
    "maximum ambient scope",max_int,C.Var (max_int-1);
    "negative ambient scope",-1,C.Sort 0;
    "identity",0,C.Lam (C.Sort 1,C.Var 0);
    "beta identity",0,beta 4 (C.Sort 1) (C.Sort 0);
    "typed let",0,C.Let (C.Sort 1,C.Sort 0,C.Var 0);
    "ill typed erased let",0,C.Let (C.Sort 1,C.Sort 1,C.Sort 0);
    "unknown erased child",0,C.Let (C.Sort 1,C.Const "Absent",C.Sort 0);
    "invalid erased scope",0,C.App (C.Lam (C.Sort 1,C.Sort 0),C.Var 0);
    "invalid erased universe",0,C.Let (C.Sort (-1),C.Sort 0,C.Sort 0);
    "nonfunction application",0,C.App (C.Sort 0,C.Sort 0);
    "non-sort annotation",0,C.Lam (C.Lam (C.Sort 1,C.Var 0),C.Var 0);
    "dependent identity",0,C.Lam (C.Sort 1,C.Lam (C.Var 0,C.Var 0));
    "dependent codomain",0,C.Pi (C.Sort 1,C.Pi (C.Var 0,C.Var 1));
    "shared tree",0,shared_tree 6 (beta 2 (C.Sort 1) (C.Sort 0));
    "shared open node with valid scope",1,C.Pi (C.Sort 1,shared_open);
    "shared open node moves scope",0,C.App (C.Lam (C.Sort 1,shared_open),shared_open);
    "private interning retains context",0,context_witness;
    "height exact boundary",0,products 127 (C.Sort 0);
    "height beyond boundary",0,products 128 (C.Sort 0);
    "cached subtree height cannot move deeper",0,C.App (deep,lambdas 100 deep);
    "unknown constant",0,C.Const "Absent";
  ] in
  List.iter (fun (name,scope,term) -> control name (fun label ->
    core_case label grid scope term ((old_converter ()) term))) specs;
  control "cyclic public application" (fun label ->
    let rec term = C.App (C.Sort 0,term) in
    let rec prior = O.App (O.Sort 0,prior) in
    core_case label sparse 0 term prior);
  control "cyclic binder" (fun label ->
    let rec term = C.Lam (C.Sort 1,term) in
    let rec prior = O.Lam (O.Sort 1,prior) in
    core_case label sparse 0 term prior);
  control "context witness designated refusal" (fun label ->
    check label (C.infer_closed ~fuel:generous context_witness = Error C.Type_mismatch));
  let state = Random.State.make [|0x341;0x2026|] in
  let rec generate depth scope =
    if depth = 0 then
      if Random.State.bool state then C.Sort (Random.State.int state 4)
      else C.Var (Random.State.int state (scope+2))
    else match Random.State.int state 6 with
    | 0 -> C.Sort (Random.State.int state 4)
    | 1 -> C.Var (Random.State.int state (scope+2))
    | 2 -> C.App (generate (depth-1) scope,generate (depth-1) scope)
    | 3 -> C.Lam (generate (depth-1) scope,generate (depth-1) (scope+1))
    | 4 -> C.Pi (generate (depth-1) scope,generate (depth-1) (scope+1))
    | _ -> C.Let (generate (depth-1) scope,generate (depth-1) scope,
                  generate (depth-1) (scope+1))
  in
  for index=0 to 31 do
    let scope=index mod 4 in
    let term=generate 5 scope in
    control ("generated syntax " ^ string_of_int index) (fun label ->
      core_case label sparse scope term ((old_converter ()) term))
  done;
  List.iter (fun (scope,body,replacement) ->
    control ("substitution scope " ^ string_of_int scope) (fun label ->
      let convert=old_converter () in
      let old_body=convert body and old_replacement=convert replacement in
      List.iter (fun fuel ->
        same_expr (Printf.sprintf "%s fuel=%d" label fuel)
          (C.instantiate ~fuel ~scope ~body replacement)
          (O.instantiate ~fuel ~scope ~body:old_body old_replacement)) grid))
    [0,C.Var 0,C.Sort 0; 1,C.Lam (C.Sort 1,C.Var 1),C.Var 0;
     2,C.Pi (C.Var 0,C.Var 3),C.Var 1;
     0,C.App (C.Var 0,C.Var 0),shared_tree 4 (C.Sort 0);
     0,C.Sort 0,C.Const "Missing"; -1,C.Var 0,C.Sort 0;
     max_int,C.Var max_int,C.Var 0];
  List.iter (fun power -> control ("long terminating beta tail " ^ string_of_int power) (fun label ->
    let identity=C.Lam (C.Sort 1,C.Var 0) in
    let double=C.Lam (C.Pi (C.Sort 1,C.Sort 1),
      C.Lam (C.Sort 1,C.App (C.Var 1,C.App (C.Var 1,C.Var 0)))) in
    let rec iter n term = if n=0 then term else iter (n-1) (C.App (double,term)) in
    let term=C.App (iter power identity,C.Sort 0) in
    let prior=(old_converter ()) term in
    List.iter (fun fuel -> same_expr (Printf.sprintf "%s fuel=%d" label fuel)
      (C.whnf ~fuel term) (O.whnf ~fuel prior)) [0;1;100;1000;20000;250000;generous];
    check (label ^ ": terminates") (C.whnf ~fuel:generous term = Ok (C.Sort 0)))) [6;9;11]

let define_pair env prior name ty value =
  let convert=old_converter () in
  unwrap name (C.define ~fuel:generous env ~name ~ty ~value),
  unwrap name (O.define ~fuel:generous prior ~name ~ty:(convert ty) ~value:(convert value))

let observe_env label names env prior =
  List.iter (fun name ->
    List.iter (fun fuel ->
      same_expr (Printf.sprintf "%s observe=%S fuel=%d" label name fuel)
        (C.infer_in ~fuel env (C.Const name)) (O.infer_in ~fuel prior (O.Const name)))
      [0;1;2;7;19;127;1024;generous];
    same_expr (label ^ ": value as dependent domain " ^ name)
      (C.infer_in ~fuel:generous env (C.Lam (C.Const name,C.Var 0)))
      (O.infer_in ~fuel:generous prior (O.Lam (O.Const name,O.Var 0)))) ("AbsentProbe"::names)

let same_env label names current prior =
  match current,prior with
  | Ok env,Ok old -> observe_env label names env old
  | Error actual,Error expected -> check (label ^ ": refusal") (actual=old_error expected)
  | _ -> check (label ^ ": environment outcome differs") false

let definition_controls () =
  let base,old_base=define_pair C.empty_environment O.empty_environment "Existing" (C.Sort 1) (C.Sort 0) in
  let ty=beta 7 (C.Sort 2) (C.Sort 1) in
  let value=shared_tree 4 (beta 2 (C.Sort 1) (C.Sort 0)) in
  List.iter (fun (case_name,ty,value) -> control case_name (fun label ->
    let convert=old_converter () in
    let old_ty=convert ty and old_value=convert value in
    let checker=C.make_definition_checker base in
    same_env (label ^ ": warm success") ["Existing";"Warm"]
      (checker ~fuel:generous ~name:"Warm" ~ty ~value)
      (O.define ~fuel:generous old_base ~name:"Warm" ~ty:old_ty ~value:old_value);
    List.iteri (fun index fuel ->
      let name="Checked" ^ string_of_int index in
      same_env (Printf.sprintf "%s fuel=%d" label fuel) ["Existing";name]
        (checker ~fuel ~name ~ty ~value)
        (O.define ~fuel old_base ~name ~ty:old_ty ~value:old_value)) (grid @ [generous]);
    List.iter (fun name -> List.iter (fun fuel ->
      same_env (Printf.sprintf "%s name=%S fuel=%d" label name fuel) ["Existing"]
        (checker ~fuel ~name ~ty:(C.Var (-1)) ~value)
        (O.define ~fuel old_base ~name ~ty:(O.Var (-1)) ~value:old_value)) sparse) ["";"Existing"]))
    ["shared complete judgment",ty,value;
     "identity judgment",C.Pi (C.Sort 1,C.Sort 1),C.Lam (C.Sort 1,C.Var 0);
     "sort judgment",C.Sort 1,C.Sort 0];
  control "cached failures cannot establish success" (fun label ->
    let checker=C.make_definition_checker base in
    let sequence=[0,C.Sort 1,C.Sort 0; generous,C.Sort 1,C.Sort 1;
      generous,C.Sort 1,C.Sort 0; 1,C.Sort 1,C.Sort 0;
      generous,C.Sort 1,C.Const "Absent"; generous,C.Sort 1,C.Sort 0] in
    List.iteri (fun i (fuel,ty,value) ->
      let name="Sequence" ^ string_of_int i in
      let convert=old_converter () in
      same_env (label ^ name) [name;"Existing"]
        (checker ~fuel ~name ~ty ~value)
        (O.define ~fuel old_base ~name ~ty:(convert ty) ~value:(convert value))) sequence);
  control "definition minimum-success boundaries" (fun label ->
    let convert=old_converter () in
    let old_ty=convert ty and old_value=convert value in
    let old fuel=O.define ~fuel old_base ~name:"Threshold" ~ty:old_ty ~value:old_value in
    check (label ^ ": old accepts generous fuel") (Result.is_ok (old generous));
    let rec threshold lo hi = if lo+1>=hi then hi else
      let mid=lo+(hi-lo)/2 in
      if Result.is_ok (old mid) then threshold lo mid else threshold mid hi in
    let required=threshold 0 generous in
    let checker=C.make_definition_checker base in
    ignore (unwrap label (checker ~fuel:generous ~name:"Warm" ~ty ~value));
    List.iter (fun fuel -> same_env (Printf.sprintf "%s fuel=%d" label fuel) ["Existing";"Threshold"]
      (checker ~fuel ~name:"Threshold" ~ty ~value) (old fuel))
      [required-2;required-1;required;required+1;required+2]);
  let other,old_other=define_pair C.empty_environment O.empty_environment "Existing" (C.Sort 2) (C.Sort 1) in
  List.iter (fun source -> control "annotation cache across parents" (fun label ->
    let cache=C.create_checking_cache () in
    List.iteri (fun parent_index (env,old_env) ->
      let check_cached=C.make_definition_checker ~cache env in
      let convert=old_converter () in
      let old_source=convert source in
      List.iteri (fun index fuel ->
        let name=Printf.sprintf "Annotation%d_%d" parent_index index in
        same_env (Printf.sprintf "%s parent=%d fuel=%d" label parent_index fuel) [name;"Existing"]
          (check_cached ~fuel ~name ~ty:source ~value:(C.Sort 0))
          (O.define ~fuel old_env ~name ~ty:old_source ~value:(O.Sort 0)))
        (generous::sparse))
      [base,old_base;other,old_other;C.empty_environment,O.empty_environment]))
    [beta 10 (C.Sort 2) (C.Sort 1);
     C.Let (C.Sort 2,C.Const "Existing",C.Sort 1);
     C.App (C.Lam (C.Sort 2,C.Sort 1),C.Const "Existing")];
  control "value import precedes cached annotation inference" (fun label ->
    let cache=C.create_checking_cache () in
    let source=beta 10 (C.Sort 2) (C.Sort 1) in
    let old_source=(old_converter ()) source in
    let warm=C.make_definition_checker ~cache base in
    ignore (unwrap label (warm ~fuel:generous ~name:"Warm" ~ty:source ~value:(C.Sort 0)));
    List.iter (fun body ->
      let old_body=(old_converter ()) body in
      let checker=C.make_definition_checker ~cache other in
      List.iter (fun fuel -> same_env (Printf.sprintf "%s fuel=%d" label fuel) ["Probe"]
        (checker ~fuel ~name:"Probe" ~ty:source ~value:body)
        (O.define ~fuel old_other ~name:"Probe" ~ty:old_source ~value:old_body)) grid)
      [C.Const "Missing"; C.Var 0; C.Sort (-1); C.Let (C.Sort 1,C.Const "Missing",C.Sort 0)]);
  control "unsuccessful annotation is never promoted" (fun label ->
    let cache=C.create_checking_cache () in
    let bad_ty=C.Let (C.Sort 1,C.Sort 1,C.Sort 1) in
    let old_ty=(old_converter ()) bad_ty in
    let checker=C.make_definition_checker ~cache base in
    List.iter (fun body ->
      let old_body=(old_converter ()) body in
      List.iter (fun fuel -> same_env (Printf.sprintf "%s fuel=%d" label fuel) ["Probe"]
        (checker ~fuel ~name:"Probe" ~ty:bad_ty ~value:body)
        (O.define ~fuel old_base ~name:"Probe" ~ty:old_ty ~value:old_body)) (sparse@[generous]))
      [C.Var 0;C.Sort 0;C.Const "Missing";C.Sort 0]);
  control "annotation collision discards reuse without changing judgment" (fun label ->
    let ty_a=pi_domains 40 (C.Sort 1) and ty_b=pi_domains 40 (C.Sort 2) in
    let value_a=lambdas 40 (C.Sort 0) and value_b=lambdas 40 (C.Sort 1) in
    check (label ^ ": witnessed direct-mapped collision")
      ((Hashtbl.hash ty_a land 255)=(Hashtbl.hash ty_b land 255));
    let cache=C.create_checking_cache () in
    let run fuel name ty value =
      let checker=C.make_definition_checker ~cache base in
      let convert=old_converter () in
      let current=checker ~fuel ~name ~ty ~value in
      same_env (Printf.sprintf "%s name=%s fuel=%d" label name fuel) [name]
        current (O.define ~fuel old_base ~name ~ty:(convert ty) ~value:(convert value));
      current
    in
    check (label ^ ": first warm success") (Result.is_ok (run generous "WarmA" ty_a value_a));
    check (label ^ ": colliding warm success") (Result.is_ok (run generous "WarmB" ty_b value_b));
    List.iteri(fun i fuel ->
      ignore(run generous ("B"^string_of_int i) ty_b value_b);
      ignore(run fuel ("A"^string_of_int i) ty_a value_a);
      ignore(run fuel ("Bad"^string_of_int i) ty_a value_b)) (sparse@[generous]))

let lookup_controls () =
  let names=Array.init 33 (fun i -> match i with
    | 0 -> "A" | 1 -> "a" | 2 -> "binary\000name" | _ -> "Key" ^ string_of_int i) in
  let snapshots=Array.make 34 (C.empty_environment,O.empty_environment) in
  for i=0 to 32 do
    let a,b=snapshots.(i) in
    snapshots.(i+1)<-define_pair a b names.(i) (C.Sort (1+i mod 3)) (C.Sort (i mod 3))
  done;
  List.iter (fun size -> control ("indexed names size " ^ string_of_int size) (fun label ->
    let env,old_env=snapshots.(size) in
    let selected=Array.to_list names |> List.filteri (fun i _ -> i<size) in
    List.iter (fun name ->
      List.iter (fun fuel ->
        same_expr (Printf.sprintf "%s name=%S fuel=%d" label name fuel)
          (C.infer_in ~fuel env (C.Const name)) (O.infer_in ~fuel old_env (O.Const name));
        same_env (Printf.sprintf "%s duplicate=%S fuel=%d" label name fuel) []
          (C.define ~fuel env ~name ~ty:(C.Var (-1)) ~value:(C.Sort 0))
          (O.define ~fuel old_env ~name ~ty:(O.Var (-1)) ~value:(O.Sort 0)))
        (List.init (size+12) Fun.id)) ("Absent"::selected);
    observe_env (label ^ ": retained snapshot") selected env old_env)) [0;1;2;7;16;33]

let old_merge_error = function
  | O.Invalid_branch -> C.Invalid_branch | O.Duplicate_branch -> C.Duplicate_branch
  | O.Merge_limit_exceeded -> C.Merge_limit_exceeded
let same_merge label names current prior = match current,prior with
  | Ok env,Ok old -> observe_env label names env old
  | Error e,Error f -> check (label ^ ": exact merge error") (e=old_merge_error f)
  | _ -> check (label ^ ": merge result differs") false

let merge_controls () =
  let base,old_base=define_pair C.empty_environment O.empty_environment "Base" (C.Sort 1) (C.Sort 0) in
  let a,oa=define_pair base old_base "A" (C.Sort 1) (C.Const "Base") in
  let b,ob=define_pair base old_base "B" (C.Sort 2) (C.Sort 1) in
  let another,old_another=define_pair C.empty_environment O.empty_environment "Base" (C.Sort 1) (C.Sort 0) in
  let wrong,old_wrong=define_pair another old_another "Wrong" (C.Sort 1) (C.Sort 0) in
  let double,old_double=define_pair a oa "Double" (C.Sort 1) (C.Sort 0) in
  List.iteri (fun index (branches,old_branches) -> control ("merge branches " ^ string_of_int index) (fun label ->
    List.iter (fun fuel ->
      same_merge (Printf.sprintf "%s fuel=%d" label fuel) ["Base";"A";"B";"Wrong";"Double"]
        (C.merge_checked_branches ~fuel ~base branches)
        (O.merge_checked_branches ~fuel ~base:old_base old_branches)) [-1;0;1;2;3;4;5;6;7;8;16;100]))
    [[],[];[a],[oa];[a;b],[oa;ob];[b;a],[ob;oa];[a;a],[oa;oa];
     [base],[old_base];[wrong],[old_wrong];[double],[old_double]];
  control "singleton merge retains distinct parent identity" (fun label ->
    let merged=unwrap label (C.merge_checked_branches ~fuel:generous ~base [a]) in
    let old_merged=unwrap label (O.merge_checked_branches ~fuel:generous ~base:old_base [oa]) in
    let child,old_child=define_pair a oa "Child" (C.Sort 1) (C.Sort 0) in
    same_merge label ["Base";"A";"Child"]
      (C.merge_checked_branches ~fuel:generous ~base:merged [child])
      (O.merge_checked_branches ~fuel:generous ~base:old_merged [old_child]);
    check (label ^ ": rejects branch of old object")
      (C.merge_checked_branches ~fuel:generous ~base:merged [child]=Error C.Invalid_branch);
    observe_env (label ^ ": originals unchanged") ["Base";"A";"Child"] a oa);
  control "cyclic branch list bounded by duplicate refusal" (fun label ->
    let rec branches=a::branches in
    let rec prior=oa::prior in
    same_merge label [] (C.merge_checked_branches ~fuel:100 ~base branches)
      (O.merge_checked_branches ~fuel:100 ~base:old_base prior))

let worker_error = function
  | Bounded_parallel.Invalid_workers -> "invalid workers"
  | Bounded_parallel.Too_many_jobs -> "too many jobs"
  | Bounded_parallel.Worker_exception(i,s) -> Printf.sprintf "worker %d %s" i s
  | Bounded_parallel.Runtime_failure s -> "runtime " ^ s
let old_worker_error = function
  | Old_bounded_parallel.Invalid_workers -> "invalid workers"
  | Old_bounded_parallel.Too_many_jobs -> "too many jobs"
  | Old_bounded_parallel.Worker_exception(i,s) -> Printf.sprintf "worker %d %s" i s
  | Old_bounded_parallel.Runtime_failure s -> "runtime " ^ s
let old_batch_error = function
  | OB.Invalid_workers -> B.Invalid_workers
  | OB.Too_many_definitions -> B.Too_many_definitions
  | OB.Invalid_name i -> B.Invalid_name i
  | OB.Duplicate_name s -> B.Duplicate_name s
  | OB.Dependency_scan_failed(s,e) -> B.Dependency_scan_failed(s,old_error e)
  | OB.Dependency_cycle ns -> B.Dependency_cycle ns
  | OB.Check_failed es -> B.Check_failed(List.map(fun(n,e)->n,old_error e)es)
  | OB.Merge_failed e -> B.Merge_failed(old_merge_error e)
  | OB.Worker_failed _ -> failwith "worker failures compared separately"
let same_batch label names current prior = match current,prior with
  | Ok report,Ok old ->
      check (label ^ ": exact waves") (report.B.waves=old.OB.waves);
      observe_env label names report.B.environment old.OB.environment
  | Error(B.Worker_failed a),Error(OB.Worker_failed b) ->
      check (label ^ ": worker error") (worker_error a=old_worker_error b)
  | Error a,Error b -> check (label ^ ": exact batch refusal") (a=old_batch_error b)
  | _ -> check (label ^ ": batch outcome differs") false
let definition ?(fuel=generous) name ty value : B.definition = {name;ty;value;fuel}
let old_jobs jobs =
  let convert=old_converter () in
  List.map(fun(d:B.definition)->OB.{name=d.name;ty=convert d.ty;value=convert d.value;fuel=d.fuel})jobs
let batch_controls () =
  let ty=beta 4 (C.Sort 2) (C.Sort 1) in
  let value=shared_tree 4 (C.Sort 0) in
  let repeated=List.init 9(fun i->definition ("R"^string_of_int i) ty value) in
  let diamonds=[definition "Base" (C.Sort 1) value;
    definition "Left" ty (C.Const "Base"); definition "Right" ty (C.Const "Base");
    definition "Join" ty (C.Pi(C.Const "Left",C.Const "Right"))] in
  let chain=List.init 9(fun i->definition ("Chain"^string_of_int i) ty
    (if i=0 then value else C.Const("Chain"^string_of_int(i-1)))) in
  let malformed=[definition "EmptyFuel" ~fuel:0 ty value;
    definition "Mismatch" (C.Sort 1) (C.Sort 1);
    definition "Unknown" (C.Sort 1) (C.Const "Missing");
    definition "Fine" ty value] in
  let cases=["empty",[];"repeated group",repeated;"distinct groups",diamonds;
    "forward dependencies",List.rev diamonds;"serial chain",chain;
    "all refusal order",malformed;
    "cycle before checking",[definition "Bad" ~fuel:0 ty value;
      definition "Cycle" ty (C.Const "Cycle")];
    "duplicate names",[definition "Dup" ty value;definition "Dup" ty value];
    "invalid name",[definition "" ty value];
    "unknown erased reference",[definition "Erases" (C.Sort 1)
      (C.Let(C.Sort 1,C.Const "Missing",C.Sort 0))]] in
  List.iter(fun(name,jobs)->control ("batch "^name)(fun label ->
    let prior=old_jobs jobs in
    let names=List.map(fun(d:B.definition)->d.name)jobs in
    let budgets=[0,generous;1,generous;3,generous;30,generous;127,generous;
      1024,generous;generous,0;generous,1;generous,2;generous,3;
      generous,7;generous,100;generous,generous] in
    List.iter(fun workers->List.iter(fun(scan_fuel,merge_fuel)->
      let at=Printf.sprintf "%s workers=%d scan=%d merge=%d" label workers scan_fuel merge_fuel in
      same_batch at names
        (B.run ~workers ~scan_fuel ~merge_fuel C.empty_environment jobs)
        (OB.run ~workers ~scan_fuel ~merge_fuel O.empty_environment prior)) budgets)
      [0;1;2;4;8;65])) cases;
  control "mixed per-job fuels within cached group" (fun label ->
    List.iter(fun fuel ->
      let jobs=[definition "Warm" ty value;definition ~fuel "Maybe" ty value;
        definition "Later" ty value;definition ~fuel:0 "Empty" ty value] in
      let prior=old_jobs jobs in
      List.iter(fun workers->same_batch (Printf.sprintf "%s fuel=%d workers=%d" label fuel workers)
        ["Warm";"Maybe";"Later";"Empty"]
        (B.run ~workers ~scan_fuel:generous ~merge_fuel:generous C.empty_environment jobs)
        (OB.run ~workers ~scan_fuel:generous ~merge_fuel:generous O.empty_environment prior))
        [1;2;4;8]) (sparse@[generous]));
  control "public cache collision retains scan and group results" (fun label ->
    let ty_a=pi_domains 40(C.Sort 1) and ty_b=pi_domains 40(C.Sort 2) in
    let val_a=lambdas 40(C.Sort 0) and val_b=lambdas 40(C.Sort 1) in
    let hash term=Hashtbl.hash_param 10 20 term in
    check (label ^ ": witnessed type collision") (hash ty_a=hash ty_b);
    check (label ^ ": witnessed value collision") (hash val_a=hash val_b);
    check (label ^ ": first successful judgment")
      (Result.is_ok (C.define ~fuel:generous C.empty_environment ~name:"SanityA" ~ty:ty_a ~value:val_a));
    check (label ^ ": second successful judgment")
      (Result.is_ok (C.define ~fuel:generous C.empty_environment ~name:"SanityB" ~ty:ty_b ~value:val_b));
    List.iter(fun fuel ->
      let jobs=[definition "A" ty_a val_a;definition "B" ty_b val_b;
        definition ~fuel "C" ty_a val_a;definition "Bad" ty_a val_b;
        definition ~fuel "Again" ty_a val_a] in
      let prior=old_jobs jobs in
      List.iter(fun workers->same_batch (Printf.sprintf "%s fuel=%d workers=%d" label fuel workers) []
        (B.run ~workers ~scan_fuel:generous ~merge_fuel:generous C.empty_environment jobs)
        (OB.run ~workers ~scan_fuel:generous ~merge_fuel:generous O.empty_environment prior))
        [1;2;4;8]) (sparse@[generous]));
  control "batch cached subtree height and scan precedence" (fun label ->
    let tree=products 36(C.Sort 0) in
    let jobs=[definition "Shallow" (C.Sort 1) tree;
      definition "Deep" (C.Sort 1) (lambdas 100 tree)] in
    let prior=old_jobs jobs in
    List.iter(fun scan_fuel->List.iter(fun workers->same_batch
      (Printf.sprintf "%s scan=%d workers=%d" label scan_fuel workers) []
      (B.run ~workers ~scan_fuel ~merge_fuel:generous C.empty_environment jobs)
      (OB.run ~workers ~scan_fuel ~merge_fuel:generous O.empty_environment prior)) [1;4]) grid);
  control "batch public cycles" (fun label ->
    let rec term=C.Pi(C.Sort 0,term) in
    let rec prior=O.Pi(O.Sort 0,prior) in
    let jobs=[definition "Cyclic" (C.Sort 1) term] in
    let old=[OB.{name="Cyclic";ty=O.Sort 1;value=prior;fuel=generous}] in
    List.iter(fun scan_fuel->same_batch (Printf.sprintf "%s scan=%d" label scan_fuel) []
      (B.run ~workers:4 ~scan_fuel ~merge_fuel:generous C.empty_environment jobs)
      (OB.run ~workers:4 ~scan_fuel ~merge_fuel:generous O.empty_environment old)) sparse);
  control "cyclic definition list is bounded" (fun label ->
    let item=definition "Repeat" (C.Sort 1) (C.Sort 0) in
    let old_item=OB.{name="Repeat";ty=O.Sort 1;value=O.Sort 0;fuel=generous} in
    let rec jobs=item::jobs and prior=old_item::prior in
    same_batch label []
      (B.run ~workers:1 ~scan_fuel:generous ~merge_fuel:generous C.empty_environment jobs)
      (OB.run ~workers:1 ~scan_fuel:generous ~merge_fuel:generous O.empty_environment prior))

let () =
  check "bytecode backend" (Sys.backend_type=Sys.Bytecode);
  core_controls ();
  definition_controls ();
  lookup_controls ();
  merge_controls ();
  batch_controls ();
  Printf.printf "Optimization differential passed: %d controls, %d exact-result assertions against pinned pre-optimization code\n%!"
    !controls !assertions
