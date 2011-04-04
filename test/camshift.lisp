;; (defpackage :cv-test
;;   (:use :cl :opencv-verrazano)
;;   (:import-from :cffi #:foreign-slot-value
;;                       #:null-pointer
;;                       #:defcallback)
;;   (:export #:test-tracking
;;            #:show-camera))

;; (in-package :cv-test)

(in-package :opencv-verrazano)

;; TODO
; Finish testing and fixing bugs.
; Start using the cv-test package.

(defclass camshift-state ()
  ((drag-start :accessor drag-start
               :initform nil)
   (track-window :accessor track-window
                 :initform nil)
   (selection :accessor selection
              :initform nil)
   (hue :accessor hue
        :initform (null-pointer))
   (comp :accessor comp
         :initform (foreign-alloc 'connected-comp))
   (track-box :accessor track-box
              :initform (foreign-alloc 'box-2d))))

(defparameter *camshift-state* (make-instance 'camshift-state))

(defparameter *hist* (create-hist 1 180 +hist-array+))

(defcallback on-mouse :void ((event :int) (x :int) (y :int)
                             (flags :int) (param :pointer))
  (declare (ignore flags param))
  (when (= event +event-lbuttondown+)
    (setf (drag-start *camshift-state*) (list x y)))
  (when (= event +event-lbuttonup+)
    (setf (drag-start *camshift-state*) nil
          (track-window *camshift-state*) (selection *camshift-state*)))
  (when (drag-start *camshift-state*)
    (let ((xmin (min x (first (drag-start *camshift-state*))))
          (ymin (min y (second (drag-start *camshift-state*))))
          (xmax (max x (first (drag-start *camshift-state*))))
          (ymax (max y (second (drag-start *camshift-state*)))))
      (setf (selection *camshift-state*)
            (list xmin ymin (- xmax xmin) (- ymax ymin))))))

(defun is-rect-nonzero (rect)
  (and (plusp (third rect))
       (plusp (fourth rect))))

(defun hue-histogram-as-image (hist &key (size '(320 200)))
  ;; Unused right now. I suspect it's unnecessary if we don't want
  ;; visual feedback via histogram for the user during target selection.
  (let* ((hist-hsv (create-image size 8 3))
         (result (create-image size 8 3))
         (temp-bins (clone-mat-nd
                     (foreign-slot-value hist 'histogram 'bins)))
         (max (second (min-max-loc temp-bins))))
    (convert-scale temp-bins temp-bins (/ 255.0 max))
    (destructuring-bind (width height) (get-size hist-hsv)
      (let ((hdims (get-dims temp-bins)))
        (loop for x from 1 to width do
             (let ((xh (/ (* 180 x) (1- width)))
                   ;; This mem-aref is probably wrong...
                   ;; we likely need the array temp-bins points to.
                   ;; What type is it?
                   (val (/ (* height (mem-aref temp-bins :int
                                               (round (/ (* hdims x)
                                                         width))))
                           255)))
               ;; The scalars (fourth arg) need to be RGB calls.
               (rectangle hist-hsv (list x 0) (list x (- height val))
                          (list xh 255 64) -1)
               (rectangle hist-hsv (list x (- height val)) (list x height)
                          (list xh 255 255) -1)))))
    (cvt-color hist-hsv result +hsv-to-bgr+)
    result))

(defun camshift-loop (&key window-name capture-src)
  (let (frame hsv backproject crit save)

    ;; Get a frame, then Convert to HSV but keep the hue
    (setf frame (query-frame capture-src))
    (setf hsv (create-image (get-size frame) 8 3))
    (cvt-color frame hsv +bgr-to-hsv+)
    (setf (hue *camshift-state*) (create-image (get-size frame) 8 1))
    (split hsv (hue *camshift-state*))

    ;; Compute back projection and run the camshift
    (setf backproject (create-image (get-size frame) 8 1))
    (calc-arr-back-project (hue *camshift-state*) backproject *hist*)
    (when (and (track-window *camshift-state*)
               (is-rect-nonzero (track-window *camshift-state*)))
      (setf crit `(,(+ +termcrit-iter+ +termcrit-eps+) 10 1.0d0))
      (with-accessors ((comp comp) (track-box track-box)) *camshift-state*
        (camshift backproject (track-window *camshift-state*) crit comp track-box)
        (setf (track-window *camshift-state*)
              (fsbv:object (foreign-slot-value comp 'connected-comp 'rect)
                           'rect))))

    ;; Handle mouse input
    (if (and (drag-start *camshift-state*)
             (is-rect-nonzero (selection *camshift-state*)))

        ;; Highlight the selected area, recompute histogram
        (with-foreign-objects ((sub 'mat)
                               (sel 'mat))
          (setf sub (get-sub-rect frame sub (selection *camshift-state*)))
          (setf save (clone-mat sub))
          (convert-scale frame frame 0.5d0)
          (copy save sub)
          (destructuring-bind (x y w h) (selection *camshift-state*)
            (rectangle frame (list x y) (list (+ x w) (+ y h))
                       '(255.0d0 255.0d0 255.0d0 0.0d0)))
          (setf sel (get-sub-rect (hue *camshift-state*) sel
                                  (selection *camshift-state*)))
          (calc-arr-hist sel *hist* 0)
          (with-foreign-objects ((min-val :float)
                                 (max-val :float))
            (%get-min-max-hist-value *hist* min-val max-val (null-pointer) (null-pointer))
            (let ((max (mem-ref max-val :float)))
              (unless (zerop max)
                (convert-scale (foreign-slot-value *hist* 'histogram 'bins)
                               (foreign-slot-value *hist* 'histogram 'bins)
                               (/ 255.0d0 max))))))

        ;; Draw the damn box and show it to the user already!
        (when (and (track-window *camshift-state*)
                   (is-rect-nonzero (track-window *camshift-state*)))
          (ellipse-box frame (track-box *camshift-state*)
                       '(255.0d0 0.0d0 0.0d0 0.0d0) 3 +aa+ 0)))
    (show-image window-name frame)))

(defun test-tracking (&key (source 0) (quit-char #\q)
                      (window-name "Camshift Demo"))
  (with-window (window-name +window-autosize+)
    (with-video (video source)
      (format t "~%Keys:~%  To quit, press ~C. ~
Click and drag with the mouse to select the object to track.~%"
              quit-char)
      ;; wait-key only works when a named-window exists.
      (set-mouse-callback window-name (callback on-mouse) (null-pointer))
      (unwind-protect
           (loop until (char= quit-char
                              (code-char (mod (wait-key 33) 256)))
              do (camshift-loop :window-name window-name :capture-src video))
        (with-accessors ((comp comp) (track-box track-box)) *camshift-state*
          (foreign-free comp)
          (foreign-free track-box)))
      (setf *camshift-state* (make-instance 'camshift-state)))))

(defun show-video (&key (source 0) (quit-char #\q)
                   (window-name "OpenCV Demo"))
  (with-window (window-name +window-autosize+)
    (with-video (video source)
      (format t "~%Keys:~%  To quit, press ~C.~%" quit-char)
      ;; wait-key appears to only work when a named-window is around.
      (loop until (char= quit-char (code-char (mod (wait-key 33) 256)))
         do (show-image window-name (query-frame video))))))
