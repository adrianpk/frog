#lang rackjure/base

(require racket/function
         racket/match
         racket/port
         racket/runtime-path
         racket/system
         rackjure/str
         "html.rkt"
         "params.rkt"
         "verbosity.rkt")

(provide pygmentize)

;; Launch process that runs Python with our pipe.py script.
(define should-start? #t)
(define-values (pyg-in pyg-out pyg-pid pyg-err pyg-proc)
  (values #f #f #f #f #f))
(define-runtime-path pipe.py "pipe.py")

(define (start)
  (match (process (str "python -u " pipe.py
                       (if (current-pygments-linenos?) " --linenos" "")
                       " --cssclass " (current-pygments-cssclass)))
    [(list in out pid err proc)
     (set!-values (pyg-in pyg-out pyg-pid pyg-err pyg-proc)
                  (values in out pid err proc))
     (file-stream-buffer-mode out 'line)])
  (read-line pyg-in 'any)) ;; consume "ready" line or EOF

(define (running?)
  (define (?)
    (and pyg-proc
         (eq? (pyg-proc 'status) 'running)))
  (when should-start? ;; first time
    (set! should-start? #f)
    (start)
    (unless (?)
      (prn1 "Pygments not installed. Using plain `pre` blocks.")))
  (?))

(define (stop) ;; -> void
  (when (running?)
    (displayln "__EXIT__" pyg-out)
    (begin0 (or (pyg-proc 'exit-code) (pyg-proc 'kill))
      (close-input-port pyg-in)
      (close-output-port pyg-out)
      (close-input-port pyg-err)))
  (void))

(exit-handler
 (let ([old-exit-handler (exit-handler)])
   (lambda (v)
     (stop)
     (old-exit-handler v))))

(define (pygmentize code lang) ;; string? string? -> (listof xexpr?)
  (define (default code)
    `((pre () (code () ,code))))
  (cond [(running?)
         (displayln lang pyg-out)
         (displayln code pyg-out)
         (displayln "__END__" pyg-out)
         (let loop ([s ""])
           (match (read-line pyg-in 'any)
             ["__END__" (with-input-from-string s read-html-as-xexprs)]
             [(? string? v) (loop (str s v "\n"))]
             [_ (copy-port pyg-err (current-output-port)) ;echo error msg
                (default code)]))]
        [else (default code)]))
