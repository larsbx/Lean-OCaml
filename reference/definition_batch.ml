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

type report = {
  environment : Conversion.environment;
  waves : string list list;
}

exception Refusal of error
module Names = Map.Make (String)
module Constants = Set.Make (String)

let refuse error = raise (Refusal error)

let definitions_array definitions =
  (* A public immutable OCaml list can still be cyclic. Bound its traversal
     before using Array.of_list or List.length. *)
  let rec collect count names reversed = function
    | [] -> Array.of_list (List.rev reversed), names
    | definition :: rest ->
        if count >= Bounded_parallel.max_jobs then refuse Too_many_definitions;
        if definition.name = "" then refuse (Invalid_name count);
        if Names.mem definition.name names then
          refuse (Duplicate_name definition.name);
        collect (count + 1) (Names.add definition.name count names)
          (definition :: reversed) rest
  in
  collect 0 Names.empty [] definitions

let constants ~scan_fuel definition =
  let remaining = ref scan_fuel in
  let found = ref Constants.empty in
  let failure error = refuse (Dependency_scan_failed (definition.name, error)) in
  let rec visit height expression =
    if height > Conversion.max_height then failure Conversion.Height_limit;
    if !remaining <= 0 then failure Conversion.Limit_exceeded;
    decr remaining;
    let child = visit (height + 1) in
    match expression with
    | Conversion.Var _ | Conversion.Sort _ -> ()
    | Conversion.Const name -> found := Constants.add name !found
    | Conversion.App (a, b) | Conversion.Lam (a, b) | Conversion.Pi (a, b) ->
        child a; child b
    | Conversion.Let (a, b, c) -> child a; child b; child c
  in
  visit 1 definition.ty;
  visit 1 definition.value;
  !found

let plan ~scan_fuel definitions names =
  let dependencies = Array.map (fun definition ->
    Constants.fold (fun name result ->
      match Names.find_opt name names with
      | None -> result
      | Some index -> index :: result)
      (constants ~scan_fuel definition) []) definitions
  in
  let count = Array.length definitions in
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
  waves 0 ready []

let run ~workers ~scan_fuel ~merge_fuel base definitions =
  try
    if workers < 1 || workers > Bounded_parallel.max_workers then
      refuse Invalid_workers;
    let definitions, names = definitions_array definitions in
    (* Compute the full plan first: no candidate definition is checked if the
       graph is cyclic, even when it also has an independent ready component. *)
    let waves = plan ~scan_fuel definitions names in
    let environment = List.fold_left (fun snapshot wave ->
      let results = match Bounded_parallel.map ~workers (fun index ->
        let definition = definitions.(index) in
        Conversion.define ~fuel:definition.fuel snapshot ~name:definition.name
          ~ty:definition.ty ~value:definition.value) wave with
        | Ok results -> results
        | Error error -> refuse (Worker_failed error)
      in
      let errors = ref [] in
      let branches = ref [] in
      Array.iteri (fun position result ->
        match result with
        | Ok branch -> branches := branch :: !branches
        | Error error ->
            errors := (definitions.(wave.(position)).name, error) :: !errors) results;
      if !errors <> [] then refuse (Check_failed (List.rev !errors));
      match Conversion.merge_checked_branches ~fuel:merge_fuel ~base:snapshot
        (List.rev !branches) with
      | Ok next -> next
      | Error error -> refuse (Merge_failed error)) base waves
    in
    Ok { environment;
         waves = List.map (fun wave ->
           Array.to_list (Array.map (fun index -> definitions.(index).name) wave)) waves }
  with Refusal error -> Error error
