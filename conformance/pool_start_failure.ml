(* Standalone because this installs a process-wide Domain.DLS splitting hook.
   The hook injects a parent-side exception on the second Domain.spawn after
   the first worker has entered a callback. It exercises pool cleanup without
   exhausting host resources or claiming to simulate every runtime failure. *)
module P = Bounded_parallel

let checks = ref 0

let check label condition =
  incr checks;
  if not condition then failwith label

let wait_until deadline predicate =
  while not (predicate ()) && Unix.gettimeofday () < deadline do
    Domain.cpu_relax ()
  done;
  predicate ()

let () =
  let initial_domains = Domain.count () in
  let parent_id = Domain.self () in
  let attempts = ref 0 in
  let injected = Atomic.make false in
  let release_worker = Atomic.make false in
  let started = Atomic.make 0 in
  let completed = Atomic.make 0 in
  let registered_exit = Atomic.make false in
  let worker_exited = Atomic.make false in
  let distinct_domain = Atomic.make false in
  let deadline = Unix.gettimeofday () +. 5.0 in
  let split_from_parent value =
    incr attempts;
    if !attempts = 2 then (
      if not (wait_until deadline (fun () -> Atomic.get started > 0)) then (
        Atomic.set release_worker true;
        failwith "first worker did not enter its callback");
      Atomic.set injected true;
      Atomic.set release_worker true;
      failwith "injected parent split failure");
    value
  in
  let key = Domain.DLS.new_key ~split_from_parent (fun () -> ()) in
  Domain.DLS.set key ();
  let action index =
    if Atomic.compare_and_set registered_exit false true then
      Domain.at_exit (fun () -> Atomic.set worker_exited true);
    if Domain.self () <> parent_id then Atomic.set distinct_domain true;
    ignore (Atomic.fetch_and_add started 1);
    Fun.protect
      ~finally:(fun () -> ignore (Atomic.fetch_and_add completed 1))
      (fun () ->
        if not (wait_until deadline (fun () -> Atomic.get release_worker)) then
          failwith "worker release deadline expired";
        index)
  in
  let result = P.map ~workers:4 action [|0; 1; 2; 3; 4; 5; 6; 7|] in
  check "failure was injected on the second spawn" (!attempts = 2 && Atomic.get injected);
  check "spawn failure remains a runtime failure"
    (result = Error (P.Runtime_failure "Failure(\"injected parent split failure\")"));
  check "a previously spawned worker was active" (Atomic.get started > 0);
  check "callback ran on a distinct domain" (Atomic.get distinct_domain);
  check "every started callback finished before return"
    (Atomic.get completed = Atomic.get started);
  check "worker exit hook completed before return" (Atomic.get worker_exited);
  check "no spawned domain remains alive" (Domain.count () = initial_domains);
  check "pool can subsequently start and join workers"
    (P.map ~workers:2 ((+) 1) [|1; 2|] = Ok [|2; 3|]);
  check "recovery leaves no live workers" (Domain.count () = initial_domains);
  Printf.printf "Injected pool startup failure passed: %d cleanup assertions\n" !checks
