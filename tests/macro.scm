(define show (lambda (x) (write x) (newline)))

(define-syntax my-if
  (syntax-rules ()
    ((my-if c a b) (if c a b))))
(show (my-if #t 'yes 'no))

(define-syntax my-when
  (syntax-rules ()
    ((my-when c body ...) (if c (begin body ...) #f))))
(show (my-when #t 1 2 3))
(show (my-when #f 1 2 3))

(define-syntax my-or
  (syntax-rules ()
    ((my-or) #f)
    ((my-or x) x)
    ((my-or x y ...) (let ((t x)) (if t t (my-or y ...))))))
(show (my-or #f #f 7))

(define-syntax swap!
  (syntax-rules ()
    ((swap! a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(define p 1)
(define q 2)
(swap! p q)
(show (list p q))

(define-syntax my-cond
  (syntax-rules (else)
    ((my-cond (else e)) e)
    ((my-cond (c e) rest ...) (if c e (my-cond rest ...)))))
(show (my-cond (#f 1) (else 2)))

(define-syntax make-def
  (syntax-rules ()
    ((make-def n v) (define n v))))
(make-def xx 9)
(show xx)

(define-syntax pair-of
  (syntax-rules ()
    ((pair-of a b) (cons a b))))
(show (pair-of 1 2))
