(load "sysdef.asd")
(load "cl-ppcre/cl-ppcre.asd")
(push :chaos-debug *features*)
(asdf:oos 'asdf:load-op :cl-ppcre)
(asdf:oos 'asdf:load-op 'chaosx)
(in-package :chaos)
(set-cafeobj-libpath "/usr/local/share/cafeobj-1.5")