#lang racket

(require "graph.rkt"
         "fluent.rkt")
;; ===========================================================================
;; Interface:
(provide inspect::once inspect::bnb
         inspect::fluent->models
         inspect::sat inspect::satset)
;; ===========================================================================
;; Result formatting:

(define (format:: inspect::X)
  (cond [(or (equal? inspect::X inspect::once)
             (equal? inspect::X inspect::bnb))
         (lambda (acc res frnt)
           (list (cons (cons 'Checked: (length acc))
                       (list (map (lambda (lon) (map (lambda (n) (node-id n)) lon))
                            acc)))
                 (cons 'Found:
                       (list (map (lambda (n) (node-id n)) res)))
                 (cons 'Frontier:
                       (list (map (lambda (lon) (map (lambda (n) (node-id n)) lon))
                                  frnt)))))]
        [(equal? inspect::X inspect::sat)
         (lambda (sol cutcnt) (list (cons 'Cuts: cutcnt) sol))]
        [(or (equal? inspect::X inspect::fluent->models)
             (equal? inspect::X inspect::satset))
         (lambda (sols cutcnt) (list (cons 'Cuts: cutcnt) sols))]
        [else empty]))

;; ===========================================================================
;; "Reflective" versions of searchers, with much larger memory footprints

(define (inspect::once path< prune)
  (lambda (start goal?)
    (local [(define (probe frnt acc)
              (if (empty? frnt)
                  ((format:: inspect::once)
                   (reverse (map (lambda (d) (reverse d)) acc))
                   empty
                   empty)
                  (let ([path  (first frnt)])
                    (if (goal? (first path))
                        ((format:: inspect::once)
                         (reverse (map (lambda (d) (reverse d)) acc))
                         (reverse path)
                         (map (lambda (d) (reverse d))
                                       (rest frnt)))

                        (let ([reduct
                               (filter (lambda (d) (not (equal? (first d)
                                                                (first path))))
                                       (prune frnt
                                              (map (lambda (n) (cons n path))
                                                   (node-arcs (first path)))))])
                          (probe (sort reduct path<)
                                 (cons path acc)))))))]      
      (probe (list (list start)) empty))))


(define (inspect::bnb path< weight)
  (lambda (start goal?)
    (local [(define probe (inspect::once path< prune-cycles))
            (define bench (probe start goal?))
            (define (optimize frnt rsf bnd acc)
              (if (empty? frnt)
                  ((format:: inspect::bnb)
                   (reverse acc) (reverse rsf) (reverse frnt))
                  (let ([path (first frnt)])
                    (if (goal? (first path))
                        (let ([nxtbnd (min (weight path) bnd)])
                          (optimize (filter (lambda (p) (< (weight p) nxtbnd))
                                            (rest frnt))
                                    (if (= nxtbnd bnd) rsf path)
                                    nxtbnd
                                    (cons (reverse path) acc)))
                        (let ([reduct (filter (lambda (p)
                                                (and (not (equal? p path))
                                                     (< (weight p) bnd)))
                                       (append (map (lambda (n) (cons n path))
                                                    (node-arcs (first path)))
                                               frnt))])
                          (optimize (sort reduct path<)
                                    rsf
                                    bnd
                                    (cons (reverse path) acc)))))))]
      (if (empty? bench)
          empty
          (optimize (list (list start))
                    (second bench)
                    (weight (reverse (second bench)))
                    empty)))))

(define (inspect::fluent->models pigeonvars var< legal?)
  (lambda (f0)
    (local [(define root
              ((fluent::->tree pigeonvars var< (lambda (x y) true)) f0))
            (define (goal? n)
              (and (empty? (node-arcs n))
                   (= (length (node-data n)) (length (fluent-vars f0)))))
            (define (probe frnt acc cutcnt)
              (if (empty? frnt)
                  ((format:: inspect::fluent->models) (reverse acc) cutcnt)
                  (local [(define path (first frnt))]
                    (if (goal? (first path))
                        (probe (rest frnt)
                               (cons (reverse (node-data (first path))) acc)
                               cutcnt)
                        (let ([arc-reduct
                               (filter
                                (lambda (c)
                                  (and (andmap (lambda (p)
                                                 (legal? p (node-data (first path))))
                                               (node-data c))
                                       (not (equal? c (first path)))))
                                (node-arcs (first path)))])
                          (probe (sort (append (map (lambda (n) (cons n path))
                                                    arc-reduct)
                                               (rest frnt))
                                       path<::dfs)
                                 acc
                                 (+ cutcnt (- (length (node-arcs (first path)))
                                              (length arc-reduct)))))))))]
      (probe (list (list root)) empty 0))))


(define (inspect::sat pigeonvars var< legal? flu<)
  (lambda (loflu)
    (local [(define ->models
              (inspect::fluent->models pigeonvars var< legal?))
            (define annotated (map (lambda (f) (->models f)) (sort loflu flu<)))
            (define cells (map (lambda (ant) (last ant)) annotated))
            (define (unify ctx agg aggwl ctxwl cutcnt)
              (if (empty? ctx)
                  ((format:: inspect::sat) agg cutcnt)
                  (local [(define admit
                            (filter (lambda (mdl)
                                      (andmap (lambda (pair) (legal? pair agg))
                                              mdl))
                                    (first ctx)))
                          (define nxtcutcnt (+ cutcnt
                                               (- (length (first ctx))
                                                  (length admit))))]
                    (if (empty? admit)
                        (if (empty? ctxwl)
                            ((format:: inspect::sat) empty nxtcutcnt)
                            (unify (first ctxwl)
                                   (first aggwl)
                                   (rest  aggwl)
                                   (rest  ctxwl)
                                   nxtcutcnt))
                        (unify (rest ctx)
                               (append agg (first admit))
                               (append (map (lambda (mdl) (append agg mdl))
                                            (rest admit))
                                       aggwl)
                               (append (map (lambda (i) (rest ctx))
                                            (rest admit))
                                       ctxwl)
                               nxtcutcnt)))))]
      (unify cells empty empty empty
             (foldr (lambda (i nx) (+ i nx))
                    0
                    (map (lambda (ant) (cdr (first ant))) annotated))))))
             
(define (inspect::satset pigeonvars var< legal? flu<)
  (lambda (loflu)
    (local [(define ->models
              (inspect::fluent->models pigeonvars var< legal?))
            (define annotated (map (lambda (f) (->models f)) (sort loflu flu<)))
            (define cells (map (lambda (ant) (last ant)) annotated))
            (define (unify ctx agg aggwl ctxwl rsf cutcnt)
              (if (empty? ctx)
                  (if (empty? aggwl)
                      ((format:: inspect::satset)
                       (reverse (cons agg rsf)) cutcnt)
                      (unify (first ctxwl) (first aggwl)
                             (rest  aggwl) (rest  ctxwl)
                             (cons agg rsf) cutcnt))
                  (local [(define admit
                            (filter (lambda (mdl)
                                      (andmap (lambda (pair) (legal? pair agg))
                                              mdl))
                                    (first ctx)))
                          (define nxtcutcnt (+ cutcnt
                                               (- (length (first ctx))
                                                  (length admit))))]
                    (if (empty? admit)
                        (if (empty? ctxwl)
                            ((format:: inspect::satset)
                             (reverse rsf) nxtcutcnt)
                            (unify (first ctxwl) (first aggwl)
                                   (rest  aggwl) (rest  ctxwl)
                                   rsf             nxtcutcnt))
                        (unify (rest ctx)
                               (append agg (first admit))
                               (append (map (lambda (mdl) (append agg mdl))
                                            (rest admit))
                                       aggwl)
                               (append (map (lambda (i) (rest ctx))
                                            (rest admit))
                                       ctxwl)
                               rsf
                               nxtcutcnt)))))]
      (unify cells empty empty empty empty
             (foldr (lambda (i nx) (+ i nx))
                    0
                    (map (lambda (ant) (cdr (first ant))) annotated))))))
