(define saved #f)
(call/cc (lambda (k) (set! saved k)))
(saved 'late)
