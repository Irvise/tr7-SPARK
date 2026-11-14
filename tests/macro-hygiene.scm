;  Hygiene and nested ellipsis for syntax-rules.
(define show (lambda (x) (write x) (newline)))

;  swap! must not capture a caller variable named tmp.
(define-syntax swap!
  (syntax-rules ()
    ((swap! a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(define p 1)
(define q 2)
(define tmp 99)
(swap! p q)
(show (list p q tmp))

;  Nested ellipsis: one repetition group per list level, two levels deep.
(define-syntax flatten
  (syntax-rules ()
    ((flatten (a b ...) ...) (list (list a b ...) ...))))
(show (flatten (1 2 3) (4 5) (6)))
(show (flatten))

(define-syntax rows
  (syntax-rules ()
    ((rows (x ...) ...) (list (list x ...) ...))))
(show (rows (1 2) (3 4 5)))
(show (rows ()))

;  Three levels of nesting.
(define-syntax cube-rows
  (syntax-rules ()
    ((cube-rows ((x ...) ...) ...)
     (list (list (list x ...) ...) ...))))
(show (cube-rows ((1 2) (3)) ((4))))

;  A macro that defines a macro.
(define-syntax define-constant
  (syntax-rules ()
    ((define-constant name value)
     (define-syntax name
       (syntax-rules ()
         ((name) value))))))
(define-constant answer 42)
(show (answer))

;  Literals.
(define-syntax my-case
  (syntax-rules (else)
    ((my-case (else e)) e)
    ((my-case (c e) rest ...) (if c e (my-case rest ...)))))
(show (my-case (#f 1) (else 2)))

;  Recursive macro; its introduced binder does not capture the caller's t.
(define-syntax my-or
  (syntax-rules ()
    ((my-or) #f)
    ((my-or x) x)
    ((my-or x y ...) (let ((t x)) (if t t (my-or y ...))))))
(define t 123)
(show (my-or #f #f 7))
(show t)

;  lambda: a template binder must not capture a caller's x.
(define-syntax add-outside
  (syntax-rules ()
    ((add-outside e) (lambda (x) (+ x e)))))
(define x 5)
(show ((add-outside x) 1))

;  let: both the binder and the caller's same-named expression stay distinct.
(define-syntax let-ten
  (syntax-rules ()
    ((let-ten e) (let ((x 10)) (+ x e)))))
(show (let-ten x))
(show x)

;  let*: sequential initializers see only the names introduced so far.
(define-syntax double-with-shadow
  (syntax-rules ()
    ((double-with-shadow e) (let* ((a e) (b a)) (+ a b)))))
(define a 100)
(define b 200)
(show (double-with-shadow 7))
(show (list a b))

;  letrec: a recursive local procedure does not capture the caller's loop.
(define-syntax count-down
  (syntax-rules ()
    ((count-down n)
     (letrec ((loop (lambda (k)
                      (if (= k 0) 0 (+ 1 (loop (- k 1)))))))
       (loop n)))))
(define loop 55)
(show (count-down 3))
(show loop)

;  Named let: name and loop variable are hygienic.
(define-syntax count-to
  (syntax-rules ()
    ((count-to n)
     (let loop ((i 0))
       (if (= i n) i (loop (+ i 1)))))))
(define i 77)
(show (count-to 4))
(show (list loop i))

;  do: bindings, test, steps and body all use the renamed variables.
(define-syntax sum-to
  (syntax-rules ()
    ((sum-to n)
     (do ((i 0 (+ i 1)) (acc 0 (+ acc i)))
         ((= i n) acc)))))
(show (sum-to 5))
(show i)

;  Internal define, both variable and function shorthand.
(define-syntax local-sum
  (syntax-rules ()
    ((local-sum e)
     (let ((x 10))
       (define y (+ x e))
       (+ x y)))))
(define y 7)
(show (local-sum x))
(show (list x y))

(define-syntax local-fn
  (syntax-rules ()
    ((local-fn e)
     (let ((x 10))
       (define (helper z) (+ x z))
       (helper e)))))
(define helper 500)
(show (local-fn x))
(show (list x helper))

;  set! on a template binder reaches the renamed binding.
(define-syntax bump
  (syntax-rules ()
    ((bump) (let ((s 0)) (set! s (+ s 1)) s))))
(show (bump))

;  quote contents are data; pattern variables inside them still substitute.
(define-syntax quoted-binder
  (syntax-rules ()
    ((quoted-binder) (let ((z 1)) (quote z)))))
(show (quoted-binder))
(define-syntax quoted-var
  (syntax-rules ()
    ((quoted-var e) (quote e))))
(show (quoted-var hello))

;  A pattern variable in binding position is the caller's identifier, and the
;  two expansions get different fresh template names.
(define-syntax bind-name
  (syntax-rules ()
    ((bind-name name val body) (let ((name val)) body))))
(define zz 0)
(show (bind-name zz 8 zz))
(show zz)

(define-syntax two-temps
  (syntax-rules ()
    ((two-temps e)
     (list (let ((v e)) v)
           (let ((v (+ e 1))) v)))))
(define v 1000)
(show (two-temps 1))
(show v)
