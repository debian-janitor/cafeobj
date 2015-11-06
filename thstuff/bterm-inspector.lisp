;;;-*-Mode:LISP; Package: CHAOS; Base:10; Syntax:Common-lisp -*-
;;;
;;; Copyright (c) 2000-2015, Toshimi Sawada. All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;;
;;;   * Redistributions of source code must retain the above copyright
;;;     notice, this list of conditions and the following disclaimer.
;;;
;;;   * Redistributions in binary form must reproduce the above
;;;     copyright notice, this list of conditions and the following
;;;     disclaimer in the documentation and/or other materials
;;;     provided with the distribution.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED
;;; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
;;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
;;; GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;
(in-package :chaos)
#|=============================================================================
                                    System:CHAOS
                                   Module:thstuff
                                File:bool-term.lisp
 =============================================================================|#
#-:chaos-debug
(declaim (optimize (speed 3) (safety 0) #-GCL (debug 0)))
#+:chaos-debug
(declaim (optimize (speed 1) (safety 3) #-GCL (debug 3)))

;;;=============================================================================
;;; Utilities to support investigating big boolean term of xor-and normal form.
;;;=============================================================================

(defvar .bterm-assoc-table. nil)
(defvar .bvar-num. 0)
(declaim (type fixnum .bvar-num.))

(defun clear-bterm-memo-table ()
  (setq .bterm-assoc-table. nil))

(defun reset-bvar ()
  (setq .bvar-num. 0)
  (clear-bterm-memo-table))

(defun make-bterm-variable ()
   (let ((varname (intern (format nil "P-~d" (incf .bvar-num.)))))
     (make-variable-term *bool-sort* varname)))

(defun get-bterm-variable (term)
  (unless (or (is-true? term)
              (is-false? term))
    (let ((ent (assoc term .bterm-assoc-table. :test #'term-equational-equal)))
      (if ent
          (cdr ent)
        (let ((var (make-bterm-variable)))
          (push (cons term var) .bterm-assoc-table.)
          var)))))

;;; =======================================================================
;;; Abstracted representation of a _xor_-_and_ normal form of boolean term.

;;; ABS-BTERM:
;;; abstracted boolean term.
;;; each non _and_ or _xor_ boolean sub-term is abstracted by a
;;; variable. 
(defstruct (abst-bterm (:print-function print-bterm))
  (module nil)                          ; context module
  (term nil)                            ; the original term
  (subst nil)                           ; list of substitution 
                                        ; or instance of abst-bterm(for _and_ abstraction)
  )

(defstruct (abst-and (:include abst-bterm)))

(defun print-bterm (bt &optional (stream *standard-output*) &rest ignore)
  (declare (ignore ignore))
  (with-in-module ((abst-bterm-module bt))
    (if (abst-and-p bt)
        (princ ":and[" stream)
      (princ ":xor[" stream))
    (let ((*print-indent* (+ 2 *print-indent*))
          (num 0))
      (declare (type fixnum *print-indent* num))
      (dolist (sub (abst-bterm-subst bt))
        (print-next nil *print-indent* stream)
        (format stream "(~d) " (incf num))
        (if (abst-bterm-p sub)
            (print-bterm sub stream)
          (progn
            (let ((var (car sub))
                  (term (cdr sub)))
              (term-print var)
              (princ " |-> ")
              (term-print term))))))
    (princ " ]" stream)))

;;;===========================================================================
;;; make abst-bterm from a term of sort 'Bool'

;;; xtract-xor-subterms : term
;;; returns ac subterms of the given term iff the top op is _xor_
;;;
(defun xtract-xor-subterms (term)
  (if (method= (term-head term) *bool-xor*)
      (list-ac-subterms term *bool-xor*)
    nil))

;;; xtract-and-subterms : term
;;; returns ac subterms of the given term iff the top op is _and_
;;;
(defun xtract-and-subterms (term)
  (if (method= (term-head term) *bool-and*)
      (list-ac-subterms term *bool-and*)
    nil))

;;; xtract-tfs : term -> List({'true'|'false'})
;;;
(defun xtract-tfs (mode term)
  (let ((subs (if (eq mode :xor)
                  (xtract-xor-subterms term)
                (xtract-and-subterms term)))
        (res nil))
    (dolist (x subs)
      (when (or (is-true? x) (is-false? x))
        (push x res)))
    res))

;;; abstract-boolen-term : bool-term -> abst-bterm
;;; 
(defun make-and-abstraction (term subterms module)
  (let ((subst nil))
    (dolist (sub subterms)
      (let ((ss (get-bterm-variable sub)))
        (when ss 
          (push (cons ss sub) subst))))
    (make-abst-and :term term :subst (nreverse subst) :module module)))

;;; assign-tf 
;;; make all posssible variable substitutions with the domain {'true' ,'false'}.
;;;
(defun make-tf-combination (rows columns)
  (let ((assignment nil)
        (subst (make-array (list rows columns))))
    (flet ((change-parity ()
             (if (is-true? assignment)
                 (setq assignment *bool-false*)
               (setq assignment *bool-true*))))
      (dotimes (c columns)
        (setq assignment nil)
        (let ((cycle (expt 2 c)))
          (dotimes (r rows)
            (if (not assignment)
                (setq assignment *bool-true*)
              (if (= 0 (mod r cycle))
                  (change-parity)))
            (setf (aref subst r c) assignment))))
      subst)))

(defun assign-tf (list-vars)
  (let* ((columns (length list-vars))
         (rows (expt 2 columns))
         (assignments (make-tf-combination rows columns))
         (l-subst nil))
    (dotimes (r rows)
      (let ((subst nil))
        (dotimes (c columns)
          (push (cons (nth c list-vars) (aref assignments r c)) subst))
        (push (nreverse subst) l-subst)))
    (when *debug-bterm*
      (with-in-module ((get-context-module))
        (let ((num 0))
          (dolist (sub (reverse l-subst))
            (format t "~%(~d): " (incf num))
            (print-substitution sub)))))
    (nreverse l-subst)))

;;; make-abst-boolean-term : term -> Values (abst-bterm List(substitution))
;;;
(defvar *abst-bterm* nil)
(defvar *abst-bterm-representation* nil)

(defun make-abst-boolean-term (term module)
  (unless (sort= (term-sort term) *bool-sort*)
    (with-output-chaos-warning ()
      (format t "Given term is not of sort Bool. Ignored.")
      (return-from make-abst-boolean-term nil)))
  (!setup-reduction module)
  (with-in-module (module)
    (reset-reduced-flag term)
    (when *citp-verbose*
      (format t "~%-- computing normal form."))
    (let* ((*always-memo* t)
           (target (reducer-no-stat term module :red)))
      (format t "~%--> ")
      (term-print term)
      ;; abstract
      (when *citp-verbose*
        (format t "~%-- starting abstraction"))
      (let ((bterm (abstract-boolean-term target module)))
        (when bterm
          (setq *abst-bterm* bterm)
          (setq *abst-bterm-representation*
          (make-bterm-representation bterm))
          (let ((*print-indent* (+ 2 *print-indent*)))
            (format t "~%** Abstracted boolean term:")
            (with-in-module (module)
              (print-next)
              (term-print *abst-bterm-representation*)
              (when *citp-verbose*
                (print-term-horizontal *abst-bterm-representation* module))
              (print-bterm-substitution bterm *abst-bterm-representation*))))))))

;;; find-bvar-subst : variable abst-bterm -> assigned term
;;; returns the assigned term of the variable.
;;;
(defun find-bvar-subst (var bterm)
  (declare (type abst-bterm bterm))
  (dolist (sub (abst-bterm-subst bterm))
    (if (abst-bterm-p sub)
        (let ((subst (find-bvar-subst var sub)))
          (when subst (return-from find-bvar-subst subst)))
      (when (variable= var (car sub))
        (return-from find-bvar-subst (cdr sub))))))

(defun print-bterm-substitution (bterm &optional 
                                       (term-representation *abst-bterm-representation*))
  (declare (type abst-bterm bterm))
  (with-in-module ((abst-bterm-module bterm))
    (let ((vars (nreverse (term-variables term-representation))))
      (unless vars (return-from print-bterm-substitution nil))
      (print-next)
      (princ "where")
      (let ((*print-indent* (+ 2 *print-indent*)))
        (dolist (var (nreverse (term-variables term-representation)))
          (let ((mapping (find-bvar-subst var bterm)))
            (unless mapping
              (with-output-chaos-error ('internal-err)
                (format t "Could not find the mapping of variable ~a." (variable-name var))))
            (print-next)
            (term-print var)
            (princ " |-> ")
            (term-print mapping)))))
    (terpri)))

(defun print-bterm-with-subst (substl bterm)
  (declare (type abst-bterm bterm))
  (with-in-module ((abst-bterm-module bterm))
    (let ((done nil))
      (dolist (subst substl)
        (dolist (sub subst)
          (let ((var (car sub)))
            (unless (member var done)
              (push var done)
              (let ((mapping (find-bvar-subst var bterm)))
                (unless mapping
                  (with-output-chaos-error ('internal-error)
                    (format t "Could not find the mapping of variable ~a." (variable-name var))))
                (princ (string (variable-print-name var)))
                (princ " = ")
                (term-print mapping)
                (print-next)))))))))

;;; abstract-boolean-term : term context-module -> abst-bterm
;;; converts given boolen term into abst-bterm.
;;;
(defun abstract-boolean-term (term module)
  (let ((bterm (make-abst-bterm :term term :module module))
        (xor-subs (xtract-xor-subterms term))
        (subst nil))
    ;; reset variable number & term hash
    (reset-bvar)
    (if xor-subs
        ;; top operator is _xor_
        ;; we further decompose by _and_
        (dolist (xs xor-subs)
          (let ((as (xtract-and-subterms xs)))
            (if as 
                (push (make-and-abstraction xs as module) subst)
              (let ((ss (get-bterm-variable xs)))
                (when ss 
                  (push (cons ss xs) subst))))))
      ;; top operator is not xor
      (let ((as (xtract-and-subterms term)))
        (if as
            (push (make-and-abstraction term as module) subst)
          ;; we only accept xor-and normal form
          (with-output-msg ()
            (format t "'bresolve' does not treate trivial form like this.")
            (print-next)
            (term-print term)
            (return-from abstract-boolean-term nil)))))
    (setf (abst-bterm-subst bterm) (nreverse subst))
    bterm))

;;; make-bterm-representation : bterm -> boolen term
;;; from bterm make a concrete representation of abstracted boolean term
;;;
(defun make-and-representation (abst-and)
  (declare (type abst-and abst-and))
  (let ((and-subs (xtract-tfs :and (abst-and-term abst-and))))
    (let ((repre (make-right-assoc-normal-form 
                  *bool-and*
                  (nconc and-subs
                         (mapcar #'(lambda (x) (car x))
                                 (abst-and-subst abst-and))))))
      (update-lowest-parse repre)
      repre)))

(defun make-xor-representation (bterm)
  (declare (type abst-bterm bterm))
  (let ((xor-subs (xtract-tfs :xor (abst-bterm-term bterm))))
    (let ((repre (make-right-assoc-normal-form 
                  *bool-xor*
                  (nconc xor-subs
                         (mapcar #'(lambda (x) (if (abst-and-p x)
                                                   (make-and-representation x)
                                                 (car x)))
                                 (abst-bterm-subst bterm))))))
      (update-lowest-parse repre)
      repre)))

(defun make-bterm-representation (bterm)
  (let ((subst (abst-bterm-subst bterm)))
    ;; no _xor nor _and_ ops in original term
    (unless subst
      (return-from make-bterm-representation (abst-bterm-term bterm)))
    ;; sole _and_ term.
    (when (and (null (cdr subst))
               (abst-and-p (car subst)))
      (return-from make-bterm-representation (make-and-representation (car subst))))
    ;; _xor_ normal form
    (make-xor-representation bterm)))

;;; ===========================================================================================
;;; PRINTERS
;;; abst-bterm printers

;;; simple-print-bterm : bterm -> void
(defun simple-print-bterm (bterm)
  (declare (type abst-bterm bterm))
  (let ((aterm (make-bterm-representation bterm)))
    (term-print-with-sort aterm)))

;;; print-bterm-tree : bterm -> void
(defun print-bterm-tree (bterm &optional (mode :vertical))
  (declare (type abst-bterm bterm))
  (with-in-module ((abst-bterm-module bterm))
    (let ((aterm (make-bterm-representation bterm)))
      (if (eq mode :vertical)
          (print-term-graph aterm *chaos-verbose*)
        (print-term-horizontal (make-bterm-representation bterm) *current-module*)))))

;;; print-bterm-grinding : term -> void
;;;
(defun print-bterm-grinding (bt)
  (with-in-module ((abst-bterm-module bt))
    (let ((torf nil))
      (if (abst-and-p bt)
          (progn
            (setq torf (xtract-tfs :and (abst-bterm-term bt)))
            (princ ">> and --->"))
        (progn
          (setq torf (xtract-tfs :xor (abst-bterm-term bt)))
          (princ ">> xor ***>")))
      (dolist (sub torf)
        (print-next)
        (term-print sub))
      (dolist (sub (abst-bterm-subst bt))
        (print-next)
        (if (abst-bterm-p sub)
            (print-bterm-grinding sub)
          (let ((var (car sub))
                (term (cdr sub)))
            (princ (variable-name var))
            (princ " |-> ")
            (term-print term))))
      (print-next)
      (if (abst-and-p bt)
          (princ "<----------")
        (princ "<**********")))))

;;; print-abst-bterm : bterm &key mode
;;; mode :simple print term representation
;;;      :tree   print term representation as vertical tree structure
;;;      :horizontal print term representation horizontal tree structure
;;; also shows a substitution used for abstruction.
;;;
(defun print-abst-bterm (bterm &key (mode :simple))
  (case mode
    (:simple (simple-print-bterm bterm))
    (:tree   (print-bterm-tree bterm))
    (:horizontal (print-bterm-tree bterm :horizontal))
    (:grind (print-bterm-grinding bterm))
    (otherwise
     (with-output-chaos-error ('invalid-mode)
       (format t "Invalid print mode ~a." mode)))))

;;; ===========================================================================================
;;; RESOLVER
;;; computes possible solutions (assignments) which makes abstracted boolean term to be 'true.'
;;;

;;; find-bterm-solution-with-subst : List(substitution) abst-bterm-representation -> List(Substitution)
;;; retuns a list of substitution which makes bterm to be true.
;;;
(defun find-bterm-solution-with-subst (all-subst abst-term &optional (module (get-context-module)))
  (let ((answers nil))
    (dolist (subst all-subst)
      (let ((target (substitution-image-cp subst abst-term)))
        (reset-reduced-flag target)
        (let ((*always-memo* t))
          (setq target (reducer-no-stat target module :red)))
        (when (is-true? $$term)
          (push subst answers))))
    (nreverse answers)))
    
;;; resolve-bterm-by-wf : bterm [limit] -> void
;;; working hourse
;;;
(defun resolve-bterm-by-wf (bterm &optional (comb-limit nil))
  (declare (type (or null fixnum) comb-limit)
           (type abst-bterm bterm))
  (with-in-module ((abst-bterm-module bterm))
    (let* ((abst-term (make-bterm-representation bterm))
           (vars (reverse (term-variables abst-term)))
           (init (mapcar #'list vars))
           (len (length vars))
           (comb (make-array len))
           (lim (or comb-limit len)))
      (declare (type list init)
               (type fixnum len)
               (type simple-array comb))
      ;; 
      (when (> lim len)
        (with-output-chaos-warning ()
          (format t "Too many combination limit ~D. Reset to ~D" lim len))
        (setq lim len))
      ;; initial combinations: no variable combinations
      (dotimes (i len)
        (setf (aref comb i) (list (nth i init))))
      ;; repeat step by step 
      ;; untill reaches to limited number of variable combinations
      (dotimes (i lim)
        ;; do the job: 
        (let ((answers nil))
          (dotimes (n len)
            (dolist (variables (aref comb n))
              (let ((ans (find-bterm-solution-with-subst (assign-tf variables) abst-term)))
                (when ans
                  (push ans answers)))))
          (when answers
            (let ((num 0))
              (declare (type fixnum num))
              (format t "~%** (~d) The following assignment(s) makes the term to be 'true'."
                      (1+ i))
              (let ((*print-indent* (+ 2 *print-indent*)))
                (dolist (solution (nreverse answers))
                  (dolist (subst solution)
                    (format t "~%[~d] " (incf num))
                    (print-substitution subst))
                  (format t "~%where")
                  (print-next)
                  (print-bterm-with-subst solution bterm))))
            (unless *bterm-all-solutions*
              (return-from resolve-bterm-by-wf t))))
        ;; prepare next variable combinations
        (dotimes (j len)
          (let ((bases (aref comb j)))
            (let ((next nil)
                  (seedbase (nthcdr (+ 1 j i) vars)))
              (dotimes (k (length bases))
                (let ((base (nth k bases))
                      (seedl (nthcdr k seedbase)))
                  (dolist (seed seedl)
                    (let ((new (append base (list seed))))
                      (when new
                        (push new next))))))
              (setf (aref comb j) (reverse next)))))))))

;;; try-resolve-bterm
;;; finds all variable assignments which make *abst-bterm* to be 'true'.
;;; 
(defun try-resolve-bterm (&optional (comb-limit nil))
  (unless *abst-bterm*
    (with-output-chaos-error ('no-bterm)
      (format t "No abstracted boolean term is specified. ~%Please do 'binspect' or ':binspect' first.")))
  ;; find solutions
  (resolve-bterm-by-wf *abst-bterm* comb-limit))

;;; binspect-in-goal : goal-name term-form
;;; abstract boolean term in the context of the goal given by goal-name.
;;;
(defun binspect-in-goal (goal-name preterm)
  (let* ((goal-node (get-target-goal-node goal-name))
         (context-module (goal-context (ptree-node-goal goal-node)))
         (target (do-parse-term* preterm context-module)))
    (make-abst-boolean-term target context-module)))

;;; binspect-in-module
;;; abstract boolean term in the context of a module
;;;
(defun binspect-in-module (mod-name preterm)
  (multiple-value-bind (target context-module)
      (do-parse-term* preterm mod-name)
    (make-abst-boolean-term target context-module)))

;;;=========================================================================
;;; TOP LEVEL FUNCTION
;;; 

;;; binspect-in
;;; make abstracted boolean term.
;;; :binspect [in <goal-name> :]   <boolean-term> .
;;; binspect  [in <module-name> :] <boolean-term> .
;;;
(defun binspect-in (mode goal-or-module-name preterm)
  (cond ((eq mode :citp)
         (binspect-in-goal goal-or-module-name preterm))
        (t 
         (binspect-in-module goal-or-module-name preterm))))

;;; bresolve
;;; finds variable assignments which make abst bterm 'true'.
;;;
(defun bresolve (&rest args)
  (let ((limit-arg (cadar args))
        (limit nil))
    (when (and limit-arg
               (not (equal "." limit-arg)))
      (setq limit (read-from-string limit-arg))
      (unless (and (integerp limit) (< 0 limit))
        (with-output-chaos-error ('invalid-limit)
          (format t "bresolve: invalid <limit> argument ~a" limit-arg))))
    (try-resolve-bterm limit)))

;;; bshow
;;; print out abst bterm. 
;;; bshow [tree]
(defun bshow (tree?)
  (unless *abst-bterm*
    (return-from bshow nil))
  (with-in-module ((abst-bterm-module *abst-bterm*))
    (if (equal tree? "tree")
        (print-term-horizontal *abst-bterm-representation* *current-module*)
      (if (equal tree? "grind")
          (print-abst-bterm *abst-bterm* :mode :grind)
        (if (equal tree? ".")
            (term-print *abst-bterm-representation*)
          (with-output-chaos-error ('invalid-parameter)
            (format t "Unknown option ~s" tree?)))))
    (unless (equal tree? "grind")
      (print-bterm-substitution *abst-bterm* *abst-bterm-representation*))))

;;; EOF
