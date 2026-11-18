#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <time.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>

/* Timing only: all importing, checking and merging remains OCaml bytecode. */
CAMLprim value lean_ocaml_benchmark_monotonic_ns(value unit)
{
  CAMLparam1(unit);
  struct timespec instant;
  if (clock_gettime(CLOCK_MONOTONIC, &instant) != 0)
    caml_failwith("benchmark monotonic clock failed");
  CAMLreturn(caml_copy_int64((int64_t)instant.tv_sec * INT64_C(1000000000)
                            + (int64_t)instant.tv_nsec));
}
