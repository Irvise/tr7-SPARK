(define show (lambda (x) (write x) (newline)))
(show "before")
(error "boom" 1 2)
