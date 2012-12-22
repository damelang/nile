(define-struct nile_Process ())
(define-type nile_Process_t struct nile_Process)

(define (nile_Process_pipe (nile_Process_t *
  nile_Process_t * nile_Process_t *) *)
  (extern nile_Process_pipe))

(define-type nile_Process_work_function_t (int
   nile_Process_t * float * int int float * int int) *)

(define (nile_Process (nile_Process_t *
  nile_Process_t * int int nile_Process_work_function_t
  nile_Process_work_function_t nile_Process_work_function_t) *)
  (extern nile_Process))

(define (nile_Process_memory (void *
  nile_Process_t *) *)
  (extern nile_Process_memory))

(define (nile_Process_advance_output (void
  nile_Process_t * float * * int * int *) *)
  (extern nile_Process_advance_output))

(define (nile_Process_advance_input (int
  nile_Process_t * float * * int * int *) *)
  (extern nile_Process_advance_input))

(define (nile_Process_prefix_input (void
  nile_Process_t * float * * int * int *) *)
  (extern nile_Process_prefix_input))

(define (nile_Process_return (int
  nile_Process_t * int int int) *)
  (extern nile_Process_return))

(define (nile_Process_reroute (int
  nile_Process_t * int int nile_Process_t *) *)
  (extern nile_Process_reroute))

(define (nile_PassThrough (nile_Process_t *
  nile_Process_t * int) *)
  (extern nile_PassThrough))

(define (nile_Reverse (nile_Process_t *
  nile_Process_t * int) *)
  (extern nile_Reverse))

(define (nile_SortBy (nile_Process_t *
  nile_Process_t * int float) *)
  (extern nile_SortBy))

(define (nile_DupZip (nile_Process_t *
  nile_Process_t * int nile_Process_t * nile_Process_t *) *)
  (extern nile_DupZip))

(define (nile_DupCat (nile_Process_t *
  nile_Process_t * int nile_Process_t * nile_Process_t *) *)
  (extern nile_DupCat))
