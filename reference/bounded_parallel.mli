(** Bounded, one-shot parallel map using OCaml domains. The calling domain is
    one worker; at most [workers - 1] additional domains are started. Each call
    joins every started domain before returning, including failure paths.
    The input array must not be mutated during the call. Callbacks must arrange
    their own synchronization if they share mutable state. *)
val max_workers : int
val max_jobs : int

type error =
  | Invalid_workers
  | Too_many_jobs
  | Worker_exception of int * string
  | Runtime_failure of string

(** Results retain input order. All callback exceptions are collected; the
    lowest input index with an exception is reported after joining workers.
    A spawn/join or scheduler failure is [Runtime_failure], never a callback
    result. Such a failure may occur after some callbacks have run. Invalid
    worker counts are refused even for an empty array. *)
val map : workers:int -> ('a -> 'b) -> 'a array -> ('b array, error) result
