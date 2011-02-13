(in-package #:cl-opencv-test)

;;various settings that depend on the camera in use
(defvar *default-width* 352)
(defvar *default-height* 288)
(defvar *frames-per-second* 10)

(defvar *millis-per-frame* (round (/ 1000 *frames-per-second*)))

(defun display (filename)
  "Open the image FILENAME and show it in a window."
  (let ((image (cl-opencv:load-image filename 1)))
    (cl-opencv:named-window "Display" 1)
    (cl-opencv:show-image "Display" image)
    (loop while
	 (not (= (cl-opencv:wait-key 0) 27)))
    (cl-opencv:release-image image)
    (cl-opencv:destroy-window "Display")))

(defun show-camera (&optional (camera-index 0) (width *default-width*)
		    (height *default-height*))
  "Show the output from the camera CAMERA-INDEX."
  (cl-opencv:with-capture (capture (cl-opencv:create-camera-capture camera-index))
    (let ((window-name "Camera"))
      (cl-opencv:set-capture-property capture +cap-prop-frame-width+ width)
      (cl-opencv:set-capture-property capture +cap-prop-frame-height+ height)
      (cl-opencv:named-window window-name)
      (do ((frame (cl-opencv:query-frame capture) 
	     (cl-opencv:query-frame capture)))
	  ((plusp (cl-opencv:wait-key *millis-per-frame*)) nil)
	(cl-opencv:show-image window-name frame))
      (cl-opencv:destroy-window window-name))))

(defun show-camera-threshold (&optional (camera-index 0)
			      (width *default-width*) (height *default-height*))
  "Show the camera output and a thresholded version in a single window."
  (cl-opencv:with-capture (capture (cl-opencv:create-camera-capture camera-index))
    (let* ((img-size (make-cv-size :width width :height height))	 
	   (window-name "Camera/Threshold")
	   (grayscale (cl-opencv:create-image img-size +ipl-depth-8u+ 1))
	   (threshold (cl-opencv:create-image img-size +ipl-depth-8u+ 1))
	   (threshold3 (cl-opencv:create-image img-size +ipl-depth-8u+ 3))
	   (window (cl-opencv:create-image (make-cv-size 
					    :width (* 2 (cv-size-width img-size))
					    :height (cv-size-height img-size))
					   +ipl-depth-8u+ 3))
	   (cam-roi (make-cv-rect :x 0 :y 0 :width width :height height))
	   (bw-roi (make-cv-rect :x width :y 0 :width width :height height)))
      (cl-opencv:set-capture-property capture +cap-prop-frame-width+ 
				      (cv-size-width img-size))
      (cl-opencv:set-capture-property capture +cap-prop-frame-height+ 
				      (cv-size-height img-size))
      (cl-opencv:named-window window-name)
      (do ((frame (cl-opencv:query-frame capture) 
	     (cl-opencv:query-frame capture)))
	  ((plusp (cl-opencv:wait-key *millis-per-frame*)) nil)
	(cl-opencv:set-image-roi window cam-roi)
	(cl-opencv:copy frame window)
	(cl-opencv:convert-image frame grayscale)
	(cl-opencv:threshold grayscale threshold 128 255 +thresh-binary+)
	(cl-opencv:convert-image threshold threshold3)
	(cl-opencv:set-image-roi window bw-roi)
	(cl-opencv:copy threshold3 window)
	(cl-opencv:reset-image-roi window)
	(cl-opencv:show-image window-name window))
      (cl-opencv:destroy-window window-name)
      (cl-opencv:release-image window)
      (cl-opencv:release-image threshold3)
      (cl-opencv:release-image threshold)
      (cl-opencv:release-image grayscale))))
  
	