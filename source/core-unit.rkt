#lang racket/unit

(require lens racket/list threading
  "core-sig.rkt" "identity-generator-sig.rkt" "utilities-sig.rkt"
  "control-panel.rkt" "data-structures.rkt" "elevator-hardware/elevator-interface.rkt" "logger.rkt" "motor.rkt" "network.rkt")

(import identity-generator^ utilities^)
(export core^)

;; Ensure that we use the incremental garbage collector
(collect-garbage 'incremental)

(define (core#io complex-struct)
  ; (trce complex-struct)
  (if (not (complex? complex-struct))
    (complex (list 0 0) (list empty empty) (list empty empty) empty)
    (let ([complex* (lens-transform complex-elevators-lens complex-struct discuss-good-solution-with-other-elevators-and-execute#io)]
          [cel complex-elevators-lens] [lt lens-transform])
      (~>
        complex*
        (lens-transform cel _ (lambda (elevators)
          (~>
            elevators
            (insert-button-presses-into-this-elevator-as-requests (pop-button-states#io) _)
            update-position#io
            store-commands#io
            set-motor-direction-to-task#io)))
        (lt complex-floors-lens   _ (lambda (floors)  (list (lens-view (lens-compose this:position  cel) complex*) (first floors))))
        (lt complex-calls-lens    _ (lambda (buttons) (list (lens-view (lens-compose this:call      cel) complex*) (first buttons))))
        (lt complex-commands-lens _ (lambda (buttons) (list (lens-view (lens-compose this:command   cel) complex*) (first buttons))))
        (if-changed-call complex-floors set-floor-indicator#io)
        (if-changed-call complex-calls set-call-lights#io)
        (if-changed-call complex-commands set-command-lights#io)))))

;; This algorithm consumes a hash-table of elevators
;; and performs side effects with it, returning a new
;; hash-table of elevators.
(define (discuss-good-solution-with-other-elevators-and-execute#io elevators)
  (if (or (empty? elevators) (not (hash-has-key? elevators id)))
    (discuss-good-solution-with-other-elevators-and-execute#io (hash id (make-empty-elevator#io id name)))
    (begin
      ; (trce (lens-view this:servicing elevators))
      (broadcast#io (lens-view this:state elevators))
      (sleep iteration-sleep-time)
      (let ([current-open (lens-view this:opening elevators)])
        (if (positive? current-open)
          (begin
            (cond
              ([= current-open door-open-iterations] (elevator-hardware:open-door#io))
              ([= current-open 1] (elevator-hardware:close-door#io)))
            (lens-transform this:opening elevators sub1))
          (~>
            (receive#io)
            filter-newest-to-hash
            (unify-messages-and-elevators elevators)
            (insert-self-into-elevators elevators)
            remove-all-dead-elevators
            decrement-all-time-to-live
            ; trce* ; You can add a trce* anywhere inside a ~> to print the state
            unify-requests
            prune-call-requests-that-are-done
            assign-call-requests
            service-commands
            sort-servicing
            prune-done-requests
            prune-servicing-requests
            detect-and-remove-floor-cycle
            check-for-fatal-situations))))))