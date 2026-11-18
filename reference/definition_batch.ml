type definition = {
  name : string;
  ty : Conversion.expr;
  value : Conversion.expr;
  fuel : int;
}
type error =
  | Invalid_workers
  | Too_many_definitions
  | Invalid_name of int
  | Duplicate_name of string
  | Dependency_scan_failed of string * Conversion.error
  | Dependency_cycle of string list
  | Check_failed of (string * Conversion.error) list
  | Worker_failed of Bounded_parallel.error
  | Merge_failed of Conversion.merge_error

type report = { environment : Conversion.environment; waves : string list list }
exception Refusal of error
module Names = Hashtbl.Make (struct
  type t = string
  let equal = String.equal
  let hash = Hashtbl.hash
end)
module Constants = Set.Make (String)
type scan_summary = { constants : Constants.t; visits : int; height : int }
let refuse error = raise (Refusal error)

let definitions_array definitions =
  let names = Names.create 128 in
  let rec collect count reversed = function
    | [] -> Array.of_list (List.rev reversed), names
    | definition :: rest ->
        if count >= Bounded_parallel.max_jobs then refuse Too_many_definitions;
        if definition.name = "" then refuse (Invalid_name count);
        if Names.mem names definition.name then
          refuse (Duplicate_name definition.name);
        Names.add names definition.name count;
        collect (count + 1) (definition :: reversed) rest
  in
  collect 0 [] definitions

let constants cache ~scan_fuel definition =
  let remaining = ref scan_fuel in
  let failure error = refuse (Dependency_scan_failed (definition.name, error)) in
  let leaf = { constants = Constants.empty; visits = 1; height = 1 } in
  let spend_one () =
    if !remaining <= 0 then failure Conversion.Limit_exceeded;
    decr remaining
  in
  let rec visit height expression =
    if height > Conversion.max_height then failure Conversion.Height_limit;
    match expression with
    | Conversion.Var _ | Conversion.Sort _ -> spend_one (); leaf
    | Conversion.Const name ->
        spend_one (); { constants = Constants.singleton name; visits = 1; height = 1 }
    | _ ->
        (* Direct mapping bounds lookup work for equal-shaped distinct inputs.
           A collision loses reuse without changing a judgment. *)
        let slot = Hashtbl.hash_param 10 20 expression land (Array.length cache - 1) in
        match cache.(slot) with
        | Some (prior, summary) when prior == expression && summary.visits <= !remaining &&
            summary.height <= Conversion.max_height - height + 1 ->
            remaining := !remaining - summary.visits;
            summary
        | _ ->
            (* Replay an unaffordable cached subtree in original order. *)
            let before = !remaining in
            spend_one ();
            let child = visit (height + 1) in
            let constants, subtree_height = match expression with
              | Conversion.Var _ | Conversion.Sort _ | Conversion.Const _ -> assert false
              | Conversion.App (a, b) | Conversion.Lam (a, b) | Conversion.Pi (a, b) ->
                  let a = child a in
                  let b = child b in
                  Constants.union a.constants b.constants, 1 + max a.height b.height
              | Conversion.Let (a, b, c) ->
                  let a = child a in
                  let b = child b in
                  let c = child c in
                  Constants.union a.constants (Constants.union b.constants c.constants),
                  1 + max a.height (max b.height c.height)
            in
            let summary = { constants; visits = before - !remaining; height = subtree_height } in
            cache.(slot) <- Some (expression, summary);
            summary
  in
  let ty = visit 1 definition.ty in
  let value = visit 1 definition.value in
  Constants.union ty.constants value.constants

let plan ~scan_fuel definitions names =
  let cache = Array.make 512 None in
  let has_dependencies = ref false in
  let dependencies = Array.map (fun definition ->
    let dependencies = Constants.fold (fun name result ->
      match Names.find_opt names name with
      | None -> result
      | Some index -> index :: result)
      (constants cache ~scan_fuel definition) [] in
    if dependencies <> [] then has_dependencies := true;
    dependencies) definitions
  in
  let count = Array.length definitions in
  if count = 0 then []
  else if not !has_dependencies then [Array.init count Fun.id]
  else (
    let outstanding = Array.map List.length dependencies in
    let dependents = Array.make count [] in
    Array.iteri (fun index prerequisites ->
      List.iter (fun dependency ->
        dependents.(dependency) <- index :: dependents.(dependency)) prerequisites)
      dependencies;
    let rec waves completed ready reversed =
      if ready = [] then (
        if completed <> count then (
          let residual = ref [] in
          Array.iteri (fun index remaining ->
            if remaining > 0 then residual := definitions.(index).name :: !residual)
            outstanding;
          refuse (Dependency_cycle (List.rev !residual)));
        List.rev reversed)
      else (
        let next = ref [] in
        List.iter (fun index ->
          List.iter (fun dependent ->
            outstanding.(dependent) <- outstanding.(dependent) - 1;
            if outstanding.(dependent) = 0 then next := dependent :: !next)
            dependents.(index)) ready;
        waves (completed + List.length ready) (List.sort Int.compare !next)
          (Array.of_list ready :: reversed))
    in
    let ready = List.filter (fun index -> outstanding.(index) = 0)
      (List.init count Fun.id) in
    waves 0 ready [])

(* A complete successful judgment may be reused only in the same snapshot.
   Every member's name and budget remain independent. *)
let checking_groups definitions wave =
  let first = definitions.(wave.(0)) in
  if Array.for_all (fun index ->
      let definition = definitions.(index) in
      definition.ty == first.ty && definition.value == first.value) wave then
    [| Array.init (Array.length wave) Fun.id |]
  else (
    let indexed = Array.make 256 None in
    let groups = ref [] in
    Array.iteri (fun position index ->
      let definition = definitions.(index) in
      let slot = (Hashtbl.hash_param 10 20 definition.ty lxor
                  (Hashtbl.hash_param 10 20 definition.value lsl 1)) land 255 in
      match indexed.(slot) with
      | Some (ty, value, positions)
        when ty == definition.ty && value == definition.value ->
          positions := position :: !positions
      | _ ->
          let positions = ref [position] in
          indexed.(slot) <- Some (definition.ty, definition.value, positions);
          groups := positions :: !groups) wave;
    Array.of_list (List.map (fun positions -> Array.of_list (List.rev !positions))
      (List.rev !groups)))

let run ~workers ~scan_fuel ~merge_fuel base definitions =
  try
    if workers < 1 || workers > Bounded_parallel.max_workers then refuse Invalid_workers;
    let definitions, names = definitions_array definitions in
    let waves = plan ~scan_fuel definitions names in
    (* Each slot is exclusive to one group; all groups join before the next
       wave can reuse constant-free annotation evidence. Nothing escapes run. *)
    let checking_caches = ref [||] in
    let ensure_caches count =
      let previous = !checking_caches in
      if Array.length previous < count then
        checking_caches := Array.init count (fun index ->
          if index < Array.length previous then previous.(index)
          else Conversion.create_checking_cache ())
    in
    let merge snapshot branches =
      match Conversion.merge_checked_branches ~fuel:merge_fuel ~base:snapshot branches with
      | Ok next -> next
      | Error error -> refuse (Merge_failed error)
    in
    let environment = List.fold_left (fun snapshot wave ->
      if Array.length wave = 1 then (
        ensure_caches 1;
        let definition = definitions.(wave.(0)) in
        let result = try
          let check = Conversion.make_definition_checker
            ~cache:(!checking_caches).(0) snapshot in
          Ok (check ~fuel:definition.fuel ~name:definition.name
            ~ty:definition.ty ~value:definition.value)
        with error -> Error (Printexc.to_string error)
        in
        match result with
        | Ok (Ok branch) -> merge snapshot [branch]
        | Ok (Error error) -> refuse (Check_failed [definition.name, error])
        | Error message ->
            refuse (Worker_failed (Bounded_parallel.Worker_exception (0, message))))
      else (
        let groups = checking_groups definitions wave in
        ensure_caches (Array.length groups);
        let results = Array.make (Array.length wave) None in
        let check_group group_index group =
          let check = Conversion.make_definition_checker
            ~cache:(!checking_caches).(group_index) snapshot in
          (* The groups partition positions: one writer per slot, with all
             readers after the worker joins. *)
          Array.iter (fun position ->
            let definition = definitions.(wave.(position)) in
            results.(position) <- Some (try Ok (check ~fuel:definition.fuel
              ~name:definition.name ~ty:definition.ty ~value:definition.value)
              with error -> Error (Printexc.to_string error))) group
        in
        let scheduled =
          if Array.length groups = 1 then
            (try check_group 0 groups.(0); Ok ()
             with error -> Error (Bounded_parallel.Worker_exception (0, Printexc.to_string error)))
          else
            let tasks = Array.mapi (fun index group -> index, group) groups in
            match Bounded_parallel.map ~workers (fun (index, group) ->
              check_group index group) tasks with
            | Ok _ -> Ok ()
            | Error error -> Error error
        in
        (match scheduled with
         | Ok () -> ()
         | Error (Bounded_parallel.Worker_exception (group, message)) ->
             refuse (Worker_failed (Bounded_parallel.Worker_exception (groups.(group).(0), message)))
         | Error error -> refuse (Worker_failed error));
        let errors = ref [] in
        let branches = ref [] in
        let worker_error = ref None in
        Array.iteri (fun position result ->
          match result with
          | Some (Ok (Ok branch)) -> branches := branch :: !branches
          | Some (Ok (Error error)) ->
              errors := (definitions.(wave.(position)).name, error) :: !errors
          | Some (Error message) ->
              if !worker_error = None then
                worker_error := Some (Bounded_parallel.Worker_exception (position, message))
          | None ->
              if !worker_error = None then
                worker_error := Some (Bounded_parallel.Runtime_failure "group result missing")) results;
        (match !worker_error with Some error -> refuse (Worker_failed error) | None -> ());
        if !errors <> [] then refuse (Check_failed (List.rev !errors));
        merge snapshot (List.rev !branches))) base waves
    in
    Ok { environment;
         waves = List.map (fun wave ->
           Array.to_list (Array.map (fun index -> definitions.(index).name) wave)) waves }
  with Refusal error -> Error error
