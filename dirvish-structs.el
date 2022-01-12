;;; dirvish-structs.el --- Dirvish data structures -*- lexical-binding: t -*-

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;;; This library contains data structures for Dirvish.

;;; Code:

(declare-function dirvish--add-advices "dirvish-advices")
(declare-function dirvish--clean-advices "dirvish-advices")
(require 'dirvish-options)
(require 'recentf)

(defun dirvish-curr (&optional frame)
  "Get current dirvish instance in FRAME.

FRAME defaults to current frame."
  (frame-parameter frame 'dirvish--curr))

(defun dirvish-drop (&optional frame)
  "Drop current dirvish instance in FRAME.

FRAME defaults to current frame."
  (set-frame-parameter frame 'dirvish--curr nil))

(defun dirvish-reclaim (&optional frame-or-window)
  "Reclaim current dirvish in FRAME-OR-WINDOW."
  (with-selected-window (frame-selected-window frame-or-window)
    (when-let ((dv-name (buffer-local-value 'dirvish--curr-name (current-buffer))))
      (set-frame-parameter nil 'dirvish--curr (gethash dv-name (dirvish-hash)))
      t)))

(defmacro dirvish--get-buffer (type &rest body)
  "Return dirvish buffer with TYPE.
If BODY is non-nil, create the buffer and execute BODY in it."
  (declare (indent 1))
  `(progn
     (let* ((id (frame-parameter nil 'window-id))
            (h-name (format " *Dirvish %s-%s*" ,type id))
            (buf (get-buffer-create h-name)))
       (with-current-buffer buf ,@body buf))))

(defun dirvish-init-frame (&optional frame)
  "Initialize the dirvishs system in FRAME.
By default, this uses the current frame."
  (setq tab-bar-new-tab-choice "*scratch*")
  (unless (frame-parameter frame 'dirvish--hash)
    (with-selected-frame (or frame (selected-frame))
      (set-frame-parameter frame 'dirvish--hash (make-hash-table :test 'equal))
      (dirvish--get-buffer "preview"
        (setq-local mode-line-format nil))
      (dirvish--get-buffer "header"
        (setq-local header-line-format nil)
        (setq-local window-size-fixed 'height)
        (setq-local face-font-rescale-alist nil)
        (setq-local mode-line-format (and dirvish-header-line-format
                                          '((:eval (dirvish-format-header-line)))))
        (set (make-local-variable 'face-remapping-alist)
             dirvish-header-face-remap-alist))
      (dirvish--get-buffer "footer"
        (setq-local header-line-format nil)
        (setq-local window-size-fixed 'height)
        (setq-local face-font-rescale-alist nil)
        (setq-local mode-line-format '((:eval (dirvish-format-mode-line))))
        (set (make-local-variable 'face-remapping-alist)
             '((mode-line-inactive mode-line-active)))))))

(defun dirvish-hash (&optional frame)
  "Return a hash containing all dirvish instance in FRAME.

The keys are the dirvish's names automatically generated by
`cl-gensym'.  The values are dirvish structs created by
`make-dirvish'.

FRAME defaults to the currently selected frame."
  ;; XXX: This must return a non-nil value to avoid breaking frames initialized
  ;; with after-make-frame-functions bound to nil.
  (or (frame-parameter frame 'dirvish--hash)
      (make-hash-table)))

(defun dirvish-all-names ()
  "Return a list of the dirvish names for all frames."
  (cl-reduce #'cl-union (mapcar
                         (lambda (fr)
                           (with-selected-frame fr
                             (mapcar #'dv-name (hash-table-values (dirvish-hash)))))
                         (frame-list))))

(defun dirvish-all-root-windows ()
  "Return a list of dirvish root windows for all frames."
  (cl-reduce #'cl-union (mapcar
                         (lambda (fr)
                           (with-selected-frame fr
                             (mapcar #'dv-root-window (hash-table-values (dirvish-hash)))))
                         (frame-list))))

(defun dirvish-all-parent-buffers ()
  "Return a list of dirvish parent buffers for all frames."
  (delete-dups
   (flatten-tree (mapcar
                  (lambda (fr)
                    (with-selected-frame fr
                      (mapcar #'dv-parent-buffers (hash-table-values (dirvish-hash)))))
                  (frame-list)))))

(cl-defstruct (dirvish (:conc-name dv-))
  "Define dirvish data type."
  (name
   (cl-gensym)
   :documentation "is a symbol that is unique for every instance.")
  (depth
   dirvish-depth
   :documentation "TODO.")
  (actual-depth
   dirvish-depth
   :documentation "TODO.")
  (header-window
   nil
   :documentation "is the window to place `dv-header-buffer'.")
  (header-buffer
   (dirvish--get-buffer "header")
   :documentation "is the buffer contains dirvish header text.")
  (footer-window
   nil
   :documentation "is the window to place `dv-footer-buffer'.")
  (footer-buffer
   (dirvish--get-buffer "footer")
   :documentation "is the buffer contains dirvish footer text.")
  (parent-buffers
   ()
   :documentation "holds all `dirvish-mode' buffers in this instance.")
  (parent-windows
   ()
   :documentation "holds all `dirvish-mode' windows in this instance.")
  (preview-window
   nil
   :documentation "is the window to display `dv-preview-buffer'.")
  (preview-buffer
   (dirvish--get-buffer "preview")
   :documentation "is the buffer for dirvish preview content.")
  (preview-buffers
   ()
   :documentation "holds all file preview buffers in this instance.")
  (preview-pixel-width
   nil
   :documentation "is the pixelwise width of preview window.")
  (saved-recentf
   recentf-list
   :documentation "is the backup of original `recentf-list'.")
  (window-conf
   (current-window-configuration)
   :documentation "is the window configuration given by `current-window-configuration'.")
  (root-window
   (progn
     (when (window-parameter nil 'window-side) (delete-window))
     (frame-selected-window))
   :documentation "is the main dirvish window.")
  (index-path
   nil
   :documentation "is the file path under cursor in ROOT-WINDOW.")
  (ls-switches
   dired-listing-switches
   :documentation "is the list switches passed to `ls' command.")
  (sort-criteria
   (cons "default" "")
   :documentation "is the addtional sorting flag added to `dired-list-switches'."))

(defmacro dirvish-new (&rest args)
  "Create a new dirvish struct and put it into `dirvish-hash'.

ARGS is a list of keyword arguments followed by an optional BODY.
The keyword arguments set the fields of the dirvish struct.
If BODY is given, it is executed to set the window configuration
for the dirvish.

Save point, and current buffer before executing BODY, and then
restore them after."
  (declare (indent defun))
  (let ((keywords))
    (while (keywordp (car args))
      (dotimes (_ 2) (push (pop args) keywords)))
    (setq keywords (reverse keywords))
    `(let ((dv (make-dirvish ,@keywords)))
       (puthash (dv-name dv) dv (dirvish-hash))
       ,(when args `(save-excursion ,@args)) ; Body form given
       dv)))

(defmacro dirvish-kill (&optional dv &rest body)
  "Kill a dirvish instance DV and remove it from `dirvish-hash'.

DV defaults to current dirvish instance if not given.  If BODY is
given, it is executed to unset the window configuration brought
by this instance."
  (declare (indent defun))
  `(when-let ((kill-dv (or ,dv (dirvish-curr))))
    (setq recentf-list (dv-saved-recentf kill-dv))
    (unless (dirvish-dired-p kill-dv)
      (set-window-configuration (dv-window-conf kill-dv)))
    (mapc #'kill-buffer (dv-parent-buffers kill-dv))
    (mapc #'kill-buffer (dv-preview-buffers kill-dv))
    (remhash (dv-name kill-dv) (dirvish-hash))
    ,@body))

(defun dirvish-activate (&optional depth)
  "Save previous window config and initialize dirvish.
TODO
If DEPTH, initialize dirvish in current window rather than
the whole frame."
  (dirvish-init-frame)
  (when (eq major-mode 'dirvish-mode) (dirvish-deactivate))
  (let ((dv-new (dirvish-new :depth (or depth dirvish-depth))))
    (set-frame-parameter nil 'dirvish--curr dv-new)
    (dirvish--add-advices t)
    (run-hooks 'dirvish-activation-hook)
    dv-new))

(defun dirvish-deactivate (&optional dv)
  "Deactivate dirvish instance DV.
If DV is not given, default to current dirvish instance."
  (dirvish-kill dv
    (unless (dirvish-all-names)
      (dirvish--clean-advices)
      (setq tab-bar-new-tab-choice dirvish-saved-new-tab-choice)
      (dolist (tm dirvish-repeat-timers) (cancel-timer (symbol-value tm))))
    (unless (or (dirvish-reclaim) (window-minibuffer-p))
      (set-frame-parameter nil 'dirvish--curr nil)))
  (and dirvish-debug-p (message "leftover: %s" (dirvish-all-names))))

(defun dirvish-dired-p (&optional dv)
  "Return t if DV only occupies 1 window.
DV defaults to the current dirvish instance if not provided."
  (when-let ((dv (or dv (dirvish-curr)))) (eq (dv-depth dv) 0)))

;;;###autoload
(defun dirvish-live-p (&optional win)
  "Return t if WIN is occupied by a dirvish instance.
WIN defaults to `selected-window' if not provided."
  (when-let ((dv (dirvish-curr)))
   (memq (or win (selected-window)) (dv-parent-windows dv))))

(provide 'dirvish-structs)
;;; dirvish-structs.el ends here
