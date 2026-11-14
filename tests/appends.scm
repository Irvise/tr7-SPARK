(define show (lambda (x) (write x) (newline)))
;;  append over several lists and list-copy/reverse on long lists: these
;;  allocate their result in one step, so the sizes here are what a
;;  4,096-cell arena can hold with the sources live.  The soft collection
;;  trigger sweeps the build loops' garbage before each big allocation.
(define (build n) (let loop ((i 0) (acc '())) (if (= i n) acc (loop (+ i 1) (cons i acc)))))
(define j (append (build 350) (build 350)))
(show (length j))
(show (list-ref j 699))
(show (list-ref j 349))
(show (length (list-copy j)))
(show (length (reverse j)))
;;  the old 1,024 cap would have called this list a type error
(show (length (build 1100)))
