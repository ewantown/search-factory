#lang racket

(require "search.rkt")

;; ==========================================================================
;; Sample data:

(define Z (node 'Z 0.0  '()))
(define G (node 'G 4.0  (list Z)))
(define H (node 'H 6.0  (list Z)))
(define F (node 'F 12.0 (list G H Z)))
(define D (node 'D 9.0  (list F)))
(define E (node 'E 11.0 (list F)))
(define C (node 'C 19.0 (list D E F)))
(define A (node 'A 21.0 (list C)))
(define B (node 'B 19.0 (list C)))
(define S (node 'S 24.0 (list A B C)))

;     A     D     G
;   /   \ /   \ /   \
;  S --- C --- F --- Z
;   \   / \   / \   /
;     B     E     H

(define (cost edge)
  (cond [(or (equal? edge (cons S B)) (equal? edge (cons G Z))) 9.0]
        [(or (equal? edge (cons C F)) (equal? edge (cons F G))) 8.0]
        [(or (equal? edge (cons E F)) (equal? edge (cons F H))) 7.0]
        [(or (equal? edge (cons C D)) (equal? edge (cons D F))) 5.0]
        [(or (equal? edge (cons S C)) (equal? edge (cons C E))) 4.0]
        [(equal? edge (cons F Z)) 18.0]
        [(equal? edge (cons B C)) 13.0]
        [(equal? edge (cons H Z)) 6.0] 
        [(equal? edge (cons S A)) 3.0]
        [(equal? edge (cons A C)) 2.0]
        [else null]))

;; ==========================================================================
;; Sample parameter specs

;; Simple tie-breaker
(define tie< (tie::< (lambda (l1 l2) (< (length l1) (length l2)))))

;; DFS order: preference-finalized stack (LIFO)
(define dfs< (dfs::< tie<))

;; BFS order: preference-finalized queue (FIFO)
(define bfs< (bfs::< tie<))

;; Least-cost-first: queue prioritized by path-cost, preference-finalized 
(define cost< (cost::< cost tie<))

;; Simple heuristic (data dependent)
(define (h< p) (if (empty? p) -inf.0 (node-data (first p)))) 

;; A*: queue prioritized by cost+heuristic weighting, preference-finalized
(define a*< (a*::< cost h< tie<))

;; Search specs
(define target? (lambda (nd) (equal? (node-id nd) 'Z)))
(define pruning prune-nothing)

;; Sample search results
(define DFS   (search S target? dfs< pruning))
(define BFS   (search S target? bfs< pruning))
(define COST< (search S target? cost< pruning))
(define A*    (search S target? a*< pruning))

(define dfbb (bnb::search dfs< h<))
(define B&B   (dfbb S cost target?))

;; For display
(define path-cost (cost::rec cost))

(define (represent results)
  (if (empty? results)
      empty
      (let ([rep-acc (foldr (lambda (lon nxt)
                              (cons (map (lambda (n) (node-id n)) lon)
                                    nxt))
                            empty
                            (first results))]
            [rep-path  (cons (map (lambda (nd) (node-id nd))
                                  (second results))
                             (path-cost (reverse (second results))))]
            
            [rep-frnt (foldr (lambda (lon nxt)
                               (cons (map (lambda (n) (node-id n)) lon)
                                     nxt))
                             empty
                             (third results))])

    (display "Probed: \n")
    (pretty-print rep-acc)
    (display "Found: \n")
    (pretty-print rep-path)
    (display "Unexpanded: \n")
    (pretty-print rep-frnt))))

(define (main)
  
  (display "DFS\n")
  (represent DFS)
  (display "\n")
  
  (display "BFS\n")
  (represent BFS)
  (display "\n")
  
  (display "COST<\n")
  (represent COST<)
  (display "\n")
  
  (display "A*\n")
  (represent A*)
  (display "\n")

  (display "B&B\n")
  (represent B&B)
  (display "\n"))



