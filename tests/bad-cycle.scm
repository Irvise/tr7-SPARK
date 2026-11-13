(define c (cons (cons 'a 1) '()))
(set-cdr! c c)
(write (assq 'x c))
