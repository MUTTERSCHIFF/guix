;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2015 Alex Kost <alezost@gmail.com>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (gnu packages tv)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages xorg)
  #:use-module (gnu packages image)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages xml)
  #:use-module (gnu packages fontutils))

(define-public tvtime
  (package
    (name "tvtime")
    (version "1.0.2")
    (source (origin
              (method url-fetch)
              (uri (string-append "mirror://sourceforge/tvtime/tvtime-"
                                  version ".tar.gz"))
              (sha256
               (base32
                "08q5gzbyz0lxb730rz6d6amkzimlc7nanv6n50j2bpw4n2xa9wmf"))
              (patches (list (search-patch "tvtime-videodev2.patch")
                             (search-patch "tvtime-pngoutput.patch")
                             (search-patch "tvtime-xmltv.patch")
                             (search-patch "tvtime-gcc41.patch")))))
    (build-system gnu-build-system)
    (inputs
     `(("libx11" ,libx11)
       ("libxext" ,libxext)
       ("libxt" ,libxt)
       ("libxtst" ,libxtst)
       ("libxinerama" ,libxinerama)
       ("libxv" ,libxv)
       ("libxxf86vm" ,libxxf86vm)
       ("libpng" ,libpng)
       ("libxml2" ,libxml2)
       ("freetype" ,freetype)
       ("zlib" ,zlib)))
    (home-page "http://tvtime.sourceforge.net")
    (synopsis "Television viewer")
    (description
     "Tvtime processes the input from your video capture card and
displays it on a monitor.  It focuses on a high visual quality.")
    (license license:gpl2+)))
