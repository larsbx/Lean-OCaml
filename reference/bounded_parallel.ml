let max_workers = 64
let max_jobs = 4096

type error =
  | Invalid_workers
  | Too_many_jobs
  | Worker_exception of int * string
  | Runtime_failure of string

let map ~workers action jobs =
  let count = Array.length jobs in
  if workers < 1 || workers > max_workers then Error Invalid_workers
  else if count > max_jobs then Error Too_many_jobs
  else if count = 0 then Ok [||]
  else
    let next = Atomic.make 0 in
    let stop = Atomic.make false in
    let results = Array.make count None in
    let rec work () =
      if not (Atomic.get stop) then (
        let index = Atomic.fetch_and_add next 1 in
        if index < count then (
          (* The atomic index gives one writer to each array slot. Joins occur
             before the calling domain reads any worker-written slot. *)
          results.(index) <- Some (
            try Ok (action jobs.(index))
            with error -> Error (Printexc.to_string error));
          work ()))
    in
    (* Keep each handle in a bounded stack frame. Recording it in a newly
       allocated list/option after spawning could itself fail and lose the
       handle. Every normal and exceptional path below joins its own worker. *)
    let rec launch remaining =
      if remaining = 0 then work ()
      else
        let domain = Domain.spawn work in
        match launch (remaining - 1) with
        | () -> Domain.join domain
        | exception error ->
            Atomic.set stop true;
            (try Domain.join domain with _ -> ());
            raise error
    in
    let runtime_error =
      try launch (min workers count - 1); None
      with error ->
        Atomic.set stop true;
        Some (Printexc.to_string error)
    in
    match runtime_error with
    | Some message -> Error (Runtime_failure message)
    | None ->
        let first_error = ref None in
        Array.iteri (fun index result ->
          if !first_error = None then
            match result with
            | Some (Ok _) -> ()
            | Some (Error message) ->
                first_error := Some (Worker_exception (index, message))
            | None ->
                first_error := Some (Runtime_failure "worker result missing")) results;
        match !first_error with
        | Some error -> Error error
        | None ->
            Ok (Array.map (function
              | Some (Ok value) -> value
              | _ -> assert false) results)
