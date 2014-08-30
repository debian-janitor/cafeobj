;;;-*- Mode:LISP; Package:CHAOS; Base:10; Syntax:Common-lisp -*-
;;;
;;; Copyright (c) 2000-2014, Toshimi Sawada. All rights reserved.
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
#|==============================================================================
				 System: Chaos
			       Module: primitives
			       File: context.lisp
==============================================================================|#
#-:chaos-debug
(declaim (optimize (speed 3) (safety 0) #-GCL (debug 0)))
#+:chaos-debug
(declaim (optimize (speed 1) (safety 3) #-GCL (debug 3)))

;;; DESCRIPTION 
;;; all the functions which handle module's context.
;;; 

;;; INSTANCE DB ****************************************************************
;;; instance db stores all the instances of class sort.
;;; made for persistent object
;;; we store term-body of an instance in the instance db.
;;; retrieving the instance always creates new term.
;;; this is for avoiding destructive replacement of term body.
;;;

;;; (defvar *instance-db* (make-hash-table :test #'equal))
;;; (defun clear-instance-db () (clrhash *instance-db*))

(defmacro make-id-key (___id)
  (once-only (___id)
    ` (cond ((term-is-builtin-constant? ,___id)
	     (term-builtin-value ,___id))
	    (t (method-symbol (term-method ,___id))))))
	   
(defun find-instance (id &optional class (module *current-module*))
  (or (find-instance-aux id module class)
      (dolist (sub (module-all-submodules module) nil)
	(when (not (eq (cdr sub) :using))
	  (let ((inst (find-instance-aux id (car sub) class)))
	    (if inst (return-from find-instance inst)))))))

(defun find-instance-aux (id module &optional class)
  (let ((db (module-instance-db module)))
    (unless db (return-from find-instance-aux nil))
    (let ((body (gethash (make-id-key id) db)))
      (if body
	  (progn
	    (term$unset-reduced-flag body)
	    (when class
	      (unless (sort<= (term$sort body) class (module-sort-order module))
		(return-from find-instance-aux nil)))
	    (list body))
	  nil))))

(defun register-instance (object)
  (unless (term-eq *void-object* object)
    (let ((module (sort-module (term-sort object)))
	  (id (term-arg-1 object)))
      (let ((db (module-instance-db module)))
	(unless db
	  (initialize-module-instance-db module)
	  (setq db (module-instance-db module)))
	(setf (gethash (make-id-key id) db) (term-body object))))))

(defun delete-instance (object)
  (unless (term-eq *void-object* object)
    (let ((module (sort-module (term-sort object))))
      (let ((db (module-instance-db module)))
	(unless db
	  (return-from delete-instance nil))
	(remhash (make-id-key (term-arg-1 object)) db)))))

;;; BINDINGS *******************************************************************

;;; GET BOUND VALUES
(defun is-special-let-variable? (name)
  (declare (values (or null t)))
  (and (>= (length (the simple-string name)) 3)
       (equal "$$" (subseq (the simple-string name) 0 2))))

(defun check-$$term-context (mod)
  (or (eq $$term-context mod)
      (member $$term-context
	      (module-all-submodules mod)
	      :test #'(lambda (x y)
			(eq x (car y))))))

(defun get-bound-value (let-sym &optional (mod *current-module*))
  (or (cdr (assoc let-sym (module-bindings mod) :test #'equal))
      (when *allow-$$term*
	(cond ((equal let-sym "$$term")
	       (when (or (null $$term) (eq 'void $$term))
		 (with-output-simple-msg ()
		   (princ "[Error] $$term has no proper value.")
		   (throw 'term-context-error nil)))
	       (unless (check-$$term-context mod)
		 (with-output-simple-msg ()
		   (princ "[Error] $$term is not proper in the current module.")
		   (throw 'term-context-error nil)))
	       $$term)
	      ((equal let-sym "$$subterm")
	       (unless $$subterm
		 (with-output-simple-msg ()
		   (princ "[Error] $$subterm has no proper vlaue.")
		   (throw 'term-context-error nil)))
	       (unless (check-$$term-context mod)
		 (with-output-simple-msg ()
		   (princ "[Error] $$subterm is not proper in the current module.")
		   (throw 'term-context-error nil)))
	       $$subterm)
	      ((is-special-let-variable? let-sym)
	       (cdr (assoc let-sym (module-bindings mod) :test #'equal)))
	      (t nil)))))

(defun set-bound-value (let-sym value &optional (mod *current-module*))
  (when (or (equal let-sym "$$term")
	    (equal let-sym "$$subterm"))
    (with-output-chaos-error ('misc-error)
      (princ "sorry, but you cannot use \"$$term\" or \"$$subterm\" as let variable.")
      ))
  ;;
  (let* ((special nil)
	 (bindings (if (is-special-let-variable? let-sym)
		       (progn (setq special t) (module-special-bindings mod))
		       (module-bindings mod))))
    (let ((binding (assoc let-sym bindings :test #'equal)))
      (if binding
	  (progn
	    (with-output-chaos-warning ()
	      (format t "resetting bound value of ~a to " let-sym)
	      (print-chaos-object value))
	    (setf (cdr binding) value))
	  (if special
	      (setf (module-special-bindings mod)
		    (acons let-sym value (module-special-bindings mod)))
	      (setf (module-bindings mod)
		    (acons let-sym value (module-bindings mod))))))))

;;; CHANGING CONTEXT
;;;-----------------------------------------------------------------------------

;;; change-context
;;; we must specially treat $$term, $$subterm, $$selection-stack, $$action-stack.
;;; these are also bound to global variables.
;;;
(defun save-context (mod)
  (when (and mod (module-name mod))
    (let ((context (module-context mod)))
      (setf (module-context-$$term context) $$term
	    (module-context-$$subterm context) $$subterm
	    (module-context-$$action-stack context) $$action-stack
	    (module-context-$$selection-stack context) $$selection-stack
	    (module-context-$$stop-pattern context) *rewrite-stop-pattern*
	    ;; (module-context-$$ptree context) *proof-tree*
	    ))))

(defun new-context (mod)
  (unless mod
    (setf $$term nil
	  $$subterm nil
	  $$action-stack nil
	  $$selection-stack nil
	  $$term-context nil
	  *last-module* nil
	  ;; !!!
	  *current-module* nil
	  *rewrite-stop-pattern* nil
	  ;; *proof-tree* nil
	  )
    (return-from new-context nil))
  ;;
  (let ((context (module-context mod)))
    (setf $$term (module-context-$$term context)
	  $$subterm (module-context-$$subterm context)
	  $$action-stack (module-context-$$action-stack context)
	  $$selection-stack (module-context-$$selection-stack context)
	  *rewrite-stop-pattern* (module-context-$$stop-pattern context)
	  ;;*proof-tree* (module-context-$$ptree context)
	  )
    (setf $$term-context mod)
    (setq *last-module* mod)
    ;; !!!!!
    (setq *current-module* mod)
    ;; !!!!!
    (clear-method-info-hash)
    t))

(defun change-context (from to)
  (when (and to (module-is-inconsistent to))
    (with-output-chaos-warning ()
      (format t "specified module ~a is inconsistent" (module-name to))
      (print-next)
      (princ "due to some changes in its sub-module(s).")
      (print-next)
      (princ "context change is not performed."))
    (return-from change-context nil))
  ;; save current context
  (save-context from)
  ;; restore new context
  (new-context to)
  )

(defun reset-target-term (term old-mod mod)
  (if (eq mod old-mod)
      (progn
	(setq $$term term
	      $$subterm term
	      $$selection-stack nil)
	(save-context mod)
	(new-context mod))
      ;; we do not change globals, instead set in context of mod.
      (save-context mod)))
;;;
(defun context-push (mod)
  (push mod *old-context*))

(defun context-pop ()
  (pop *old-context*))

(defun context-push-and-move (old new)
  (context-push old)
  (change-context old new))

(defun context-pop-and-recover ()
  (when (or *last-module* *current-module*)
    (let ((old (context-pop)))
      (unless (member old (list *last-module* *current-module*))
	;; eval-mod may change the current context implicitly.
	;; in this case we do not recover context.
	(change-context *last-module* old)))))

;;; EOF
