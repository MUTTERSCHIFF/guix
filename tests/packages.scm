;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2012, 2013, 2014 Ludovic Courtès <ludo@gnu.org>
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

(define-module (test-packages)
  #:use-module (guix tests)
  #:use-module (guix store)
  #:use-module ((guix utils)
                ;; Rename the 'location' binding to allow proper syntax
                ;; matching when setting the 'location' field of a package.
                #:renamer (lambda (name)
                            (cond ((eq? name 'location) 'make-location)
                                  (else name))))
  #:use-module (guix hash)
  #:use-module (guix derivations)
  #:use-module (guix packages)
  #:use-module (guix build-system)
  #:use-module (guix build-system trivial)
  #:use-module (guix build-system gnu)
  #:use-module (gnu packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages bootstrap)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-34)
  #:use-module (srfi srfi-64)
  #:use-module (rnrs io ports)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 match))

;; Test the high-level packaging layer.

(define %store
  (open-connection-for-tests))

(define-syntax-rule (dummy-package name* extra-fields ...)
  (package (name name*) (version "0") (source #f)
           (build-system gnu-build-system)
           (synopsis #f) (description #f)
           (home-page #f) (license #f)
           extra-fields ...))


(test-begin "packages")

(test-assert "printer with location"
  (string-match "^#<package foo-0 foo.scm:42 [[:xdigit:]]+>$"
                (with-output-to-string
                  (lambda ()
                    (write
                     (dummy-package "foo"
                       (location (make-location "foo.scm" 42 7))))))))

(test-assert "printer without location"
  (string-match "^#<package foo-0 [[:xdigit:]]+>$"
                (with-output-to-string
                  (lambda ()
                    (write
                     (dummy-package "foo" (location #f)))))))

(test-assert "package-field-location"
  (let ()
    (define (goto port line column)
      (unless (and (= (port-column port) (- column 1))
                   (= (port-line port) (- line 1)))
        (unless (eof-object? (get-char port))
          (goto port line column))))

    (define read-at
      (match-lambda
       (($ <location> file line column)
        (call-with-input-file (search-path %load-path file)
          (lambda (port)
            (goto port line column)
            (read port))))))

    ;; Until Guile 2.0.6 included, source properties were added only to pairs.
    ;; Thus, check against both VALUE and (FIELD VALUE).
    (and (member (read-at (package-field-location %bootstrap-guile 'name))
                 (let ((name (package-name %bootstrap-guile)))
                   (list name `(name ,name))))
         (member (read-at (package-field-location %bootstrap-guile 'version))
                 (let ((version (package-version %bootstrap-guile)))
                   (list version `(version ,version))))
         (not (package-field-location %bootstrap-guile 'does-not-exist)))))

;; Make sure we don't change the file name to an absolute file name.
(test-equal "package-field-location, relative file name"
  (location-file (package-location %bootstrap-guile))
  (with-fluids ((%file-port-name-canonicalization 'absolute))
    (location-file (package-field-location %bootstrap-guile 'version))))

(test-assert "package-transitive-inputs"
  (let* ((a (dummy-package "a"))
         (b (dummy-package "b"
              (propagated-inputs `(("a" ,a)))))
         (c (dummy-package "c"
              (inputs `(("a" ,a)))))
         (d (dummy-package "d"
              (propagated-inputs `(("x" "something.drv")))))
         (e (dummy-package "e"
              (inputs `(("b" ,b) ("c" ,c) ("d" ,d))))))
    (and (null? (package-transitive-inputs a))
         (equal? `(("a" ,a)) (package-transitive-inputs b))
         (equal? `(("a" ,a)) (package-transitive-inputs c))
         (equal? (package-propagated-inputs d)
                 (package-transitive-inputs d))
         (equal? `(("b" ,b) ("b/a" ,a) ("c" ,c)
                   ("d" ,d) ("d/x" "something.drv"))
                 (pk 'x (package-transitive-inputs e))))))

(test-equal "package-transitive-supported-systems"
  '(("x" "y" "z")                                 ;a
    ("x" "y")                                     ;b
    ("y")                                         ;c
    ("y")                                         ;d
    ("y"))                                        ;e
  (let* ((a (dummy-package "a" (supported-systems '("x" "y" "z"))))
         (b (dummy-package "b" (supported-systems '("x" "y"))
               (inputs `(("a" ,a)))))
         (c (dummy-package "c" (supported-systems '("y" "z"))
               (inputs `(("b" ,b)))))
         (d (dummy-package "d" (supported-systems '("x" "y" "z"))
               (inputs `(("b" ,b) ("c" ,c)))))
         (e (dummy-package "e" (supported-systems '("x" "y" "z"))
               (inputs `(("d" ,d))))))
    (list (package-transitive-supported-systems a)
          (package-transitive-supported-systems b)
          (package-transitive-supported-systems c)
          (package-transitive-supported-systems d)
          (package-transitive-supported-systems e))))

(test-skip (if (not %store) 8 0))

(test-assert "package-source-derivation, file"
  (let* ((file    (search-path %load-path "guix.scm"))
         (package (package (inherit (dummy-package "p"))
                    (source file)))
         (source  (package-source-derivation %store
                                             (package-source package))))
    (and (store-path? source)
         (valid-path? %store source)
         (equal? (call-with-input-file source get-bytevector-all)
                 (call-with-input-file file get-bytevector-all)))))

(test-assert "package-source-derivation, store path"
  (let* ((file    (add-to-store %store "guix.scm" #t "sha256"
                                (search-path %load-path "guix.scm")))
         (package (package (inherit (dummy-package "p"))
                    (source file)))
         (source  (package-source-derivation %store
                                             (package-source package))))
    (string=? file source)))

(test-assert "package-source-derivation, indirect store path"
  (let* ((dir     (add-to-store %store "guix-build" #t "sha256"
                                (dirname (search-path %load-path
                                                      "guix/build/utils.scm"))))
         (package (package (inherit (dummy-package "p"))
                    (source (string-append dir "/utils.scm"))))
         (source  (package-source-derivation %store
                                             (package-source package))))
    (and (direct-store-path? source)
         (string-suffix? "utils.scm" source))))

(unless (false-if-exception (getaddrinfo "www.gnu.org" "80" AI_NUMERICSERV))
  (test-skip 1))
(test-equal "package-source-derivation, snippet"
  "OK"
  (let* ((file   (search-bootstrap-binary "guile-2.0.9.tar.xz"
                                          (%current-system)))
         (sha256 (call-with-input-file file port-sha256))
         (fetch  (lambda* (store url hash-algo hash
                           #:optional name #:key system)
                   (pk 'fetch url hash-algo hash name system)
                   (add-to-store store (basename url) #f "sha256" url)))
         (source (bootstrap-origin
                  (origin
                    (method fetch)
                    (uri file)
                    (sha256 sha256)
                    (patch-inputs
                     `(("tar" ,%bootstrap-coreutils&co)
                       ("xz" ,%bootstrap-coreutils&co)
                       ("patch" ,%bootstrap-coreutils&co)))
                    (patch-guile %bootstrap-guile)
                    (modules '((guix build utils)))
                    (imported-modules modules)
                    (snippet '(begin
                                ;; We end up in 'bin', because it's the first
                                ;; directory, alphabetically.  Not a very good
                                ;; example but hey.
                                (chmod "." #o777)
                                (symlink "guile" "guile-rocks")
                                (copy-recursively "../share/guile/2.0/scripts"
                                                  "scripts")

                                ;; These variables must exist.
                                (pk %build-inputs %outputs))))))
         (package (package (inherit (dummy-package "with-snippet"))
                    (source source)
                    (build-system trivial-build-system)
                    (inputs
                     `(("tar" ,(search-bootstrap-binary "tar"
                                                        (%current-system)))
                       ("xz"  ,(search-bootstrap-binary "xz"
                                                        (%current-system)))))
                    (arguments
                     `(#:guile ,%bootstrap-guile
                       #:builder
                       (let ((tar    (assoc-ref %build-inputs "tar"))
                             (xz     (assoc-ref %build-inputs "xz"))
                             (source (assoc-ref %build-inputs "source")))
                         (and (zero? (system* tar "xvf" source
                                              "--use-compress-program" xz))
                              (string=? "guile" (readlink "bin/guile-rocks"))
                              (file-exists? "bin/scripts/compile.scm")
                              (let ((out (assoc-ref %outputs "out")))
                                (call-with-output-file out
                                  (lambda (p)
                                    (display "OK" p))))))))))
         (drv    (package-derivation %store package))
         (out    (derivation->output-path drv)))
    (and (build-derivations %store (list (pk 'snippet-drv drv)))
         (call-with-input-file out get-string-all))))

(test-assert "return value"
  (let ((drv (package-derivation %store (dummy-package "p"))))
    (and (derivation? drv)
         (file-exists? (derivation-file-name drv)))))

(test-assert "package-output"
  (let* ((package  (dummy-package "p"))
         (drv      (package-derivation %store package)))
    (and (derivation? drv)
         (string=? (derivation->output-path drv)
                   (package-output %store package "out")))))

(test-assert "trivial"
  (let* ((p (package (inherit (dummy-package "trivial"))
              (build-system trivial-build-system)
              (source #f)
              (arguments
               `(#:guile ,%bootstrap-guile
                 #:builder
                 (begin
                   (mkdir %output)
                   (call-with-output-file (string-append %output "/test")
                     (lambda (p)
                       (display '(hello guix) p))))))))
         (d (package-derivation %store p)))
    (and (build-derivations %store (list d))
         (let ((p (pk 'drv d (derivation->output-path d))))
           (equal? '(hello guix)
                   (call-with-input-file (string-append p "/test") read))))))

(test-assert "trivial with local file as input"
  (let* ((i (search-path %load-path "ice-9/boot-9.scm"))
         (p (package (inherit (dummy-package "trivial-with-input-file"))
              (build-system trivial-build-system)
              (source #f)
              (arguments
               `(#:guile ,%bootstrap-guile
                 #:builder (copy-file (assoc-ref %build-inputs "input")
                                      %output)))
              (inputs `(("input" ,i)))))
         (d (package-derivation %store p)))
    (and (build-derivations %store (list d))
         (let ((p (pk 'drv d (derivation->output-path d))))
           (equal? (call-with-input-file p get-bytevector-all)
                   (call-with-input-file i get-bytevector-all))))))

(test-assert "trivial with source"
  (let* ((i (search-path %load-path "ice-9/boot-9.scm"))
         (p (package (inherit (dummy-package "trivial-with-source"))
              (build-system trivial-build-system)
              (source i)
              (arguments
               `(#:guile ,%bootstrap-guile
                 #:builder (copy-file (assoc-ref %build-inputs "source")
                                      %output)))))
         (d (package-derivation %store p)))
    (and (build-derivations %store (list d))
         (let ((p (derivation->output-path d)))
           (equal? (call-with-input-file p get-bytevector-all)
                   (call-with-input-file i get-bytevector-all))))))

(test-assert "trivial with system-dependent input"
  (let* ((p (package (inherit (dummy-package "trivial-system-dependent-input"))
              (build-system trivial-build-system)
              (source #f)
              (arguments
               `(#:guile ,%bootstrap-guile
                 #:builder
                 (let ((out  (assoc-ref %outputs "out"))
                       (bash (assoc-ref %build-inputs "bash")))
                   (zero? (system* bash "-c"
                                   (format #f "echo hello > ~a" out))))))
              (inputs `(("bash" ,(search-bootstrap-binary "bash"
                                                          (%current-system)))))))
         (d (package-derivation %store p)))
    (and (build-derivations %store (list d))
         (let ((p (pk 'drv d (derivation->output-path d))))
           (eq? 'hello (call-with-input-file p read))))))

(test-assert "search paths"
  (let* ((p (make-prompt-tag "return-search-paths"))
         (s (build-system
             (name 'raw)
             (description "Raw build system with direct store access")
             (lower (lambda* (name #:key source inputs system target
                                   #:allow-other-keys)
                      (bag
                        (name name)
                        (system system) (target target)
                        (build-inputs inputs)
                        (build
                         (lambda* (store name inputs
                                         #:key outputs system search-paths)
                           search-paths)))))))
         (x (list (search-path-specification
                   (variable "GUILE_LOAD_PATH")
                   (files '("share/guile/site/2.0")))
                  (search-path-specification
                   (variable "GUILE_LOAD_COMPILED_PATH")
                   (files '("share/guile/site/2.0")))))
         (a (package (inherit (dummy-package "guile"))
              (build-system s)
              (native-search-paths x)))
         (b (package (inherit (dummy-package "guile-foo"))
              (build-system s)
              (inputs `(("guile" ,a)))))
         (c (package (inherit (dummy-package "guile-bar"))
              (build-system s)
              (inputs `(("guile" ,a)
                        ("guile-foo" ,b))))))
    (let-syntax ((collect (syntax-rules ()
                            ((_ body ...)
                             (call-with-prompt p
                               (lambda ()
                                 body ...)
                               (lambda (k search-paths)
                                 search-paths))))))
      (and (null? (collect (package-derivation %store a)))
           (equal? x (collect (package-derivation %store b)))
           (equal? x (collect (package-derivation %store c)))))))

(test-assert "package-cross-derivation"
  (let ((drv (package-cross-derivation %store (dummy-package "p")
                                       "mips64el-linux-gnu")))
    (and (derivation? drv)
         (file-exists? (derivation-file-name drv)))))

(test-assert "package-cross-derivation, trivial-build-system"
  (let ((p (package (inherit (dummy-package "p"))
             (build-system trivial-build-system)
             (arguments '(#:builder (exit 1))))))
    (let ((drv (package-cross-derivation %store p "mips64el-linux-gnu")))
      (derivation? drv))))

(test-assert "package-cross-derivation, no cross builder"
  (let* ((b (build-system (inherit trivial-build-system)
              (lower (const #f))))
         (p (package (inherit (dummy-package "p"))
              (build-system b))))
    (guard (c ((package-cross-build-system-error? c)
               (eq? (package-error-package c) p)))
      (package-cross-derivation %store p "mips64el-linux-gnu")
      #f)))

(test-equal "package-derivation, direct graft"
  (package-derivation %store gnu-make)
  (let ((p (package (inherit coreutils)
             (replacement gnu-make))))
    (package-derivation %store p)))

(test-equal "package-cross-derivation, direct graft"
  (package-cross-derivation %store gnu-make "mips64el-linux-gnu")
  (let ((p (package (inherit coreutils)
             (replacement gnu-make))))
    (package-cross-derivation %store p "mips64el-linux-gnu")))

(test-assert "package-grafts, indirect grafts"
  (let* ((new   (dummy-package "dep"
                  (arguments '(#:implicit-inputs? #f))))
         (dep   (package (inherit new) (version "0.0")))
         (dep*  (package (inherit dep) (replacement new)))
         (dummy (dummy-package "dummy"
                  (arguments '(#:implicit-inputs? #f))
                  (inputs `(("dep" ,dep*))))))
    (equal? (package-grafts %store dummy)
            (list (graft
                    (origin (package-derivation %store dep))
                    (replacement (package-derivation %store new)))))))

(test-assert "package-grafts, indirect grafts, cross"
  (let* ((new    (dummy-package "dep"
                   (arguments '(#:implicit-inputs? #f))))
         (dep    (package (inherit new) (version "0.0")))
         (dep*   (package (inherit dep) (replacement new)))
         (dummy  (dummy-package "dummy"
                   (arguments '(#:implicit-inputs? #f))
                   (inputs `(("dep" ,dep*)))))
         (target "mips64el-linux-gnu"))
    (equal? (package-grafts %store dummy #:target target)
            (list (graft
                    (origin (package-cross-derivation %store dep target))
                    (replacement
                     (package-cross-derivation %store new target)))))))

(test-assert "package-grafts, indirect grafts, propagated inputs"
  (let* ((new   (dummy-package "dep"
                  (arguments '(#:implicit-inputs? #f))))
         (dep   (package (inherit new) (version "0.0")))
         (dep*  (package (inherit dep) (replacement new)))
         (prop  (dummy-package "propagated"
                  (propagated-inputs `(("dep" ,dep*)))
                  (arguments '(#:implicit-inputs? #f))))
         (dummy (dummy-package "dummy"
                  (arguments '(#:implicit-inputs? #f))
                  (inputs `(("prop" ,prop))))))
    (equal? (package-grafts %store dummy)
            (list (graft
                    (origin (package-derivation %store dep))
                    (replacement (package-derivation %store new)))))))

(test-assert "package-derivation, indirect grafts"
  (let* ((new   (dummy-package "dep"
                  (arguments '(#:implicit-inputs? #f))))
         (dep   (package (inherit new) (version "0.0")))
         (dep*  (package (inherit dep) (replacement new)))
         (dummy (dummy-package "dummy"
                  (arguments '(#:implicit-inputs? #f))
                  (inputs `(("dep" ,dep*)))))
         (guile (package-derivation %store (canonical-package guile-2.0)
                                    #:graft? #f)))
    (equal? (package-derivation %store dummy)
            (graft-derivation %store "dummy-0"
                              (package-derivation %store dummy #:graft? #f)
                              (package-grafts %store dummy)

                              ;; Use the same Guile as 'package-derivation'.
                              #:guile guile))))

(test-equal "package->bag"
  `("foo86-hurd" #f (,(package-source gnu-make))
    (,(canonical-package glibc)) (,(canonical-package coreutils)))
  (let ((bag (package->bag gnu-make "foo86-hurd")))
    (list (bag-system bag) (bag-target bag)
          (assoc-ref (bag-build-inputs bag) "source")
          (assoc-ref (bag-build-inputs bag) "libc")
          (assoc-ref (bag-build-inputs bag) "coreutils"))))

(test-equal "package->bag, cross-compilation"
  `(,(%current-system) "foo86-hurd"
    (,(package-source gnu-make))
    (,(canonical-package glibc)) (,(canonical-package coreutils)))
  (let ((bag (package->bag gnu-make (%current-system) "foo86-hurd")))
    (list (bag-system bag) (bag-target bag)
          (assoc-ref (bag-build-inputs bag) "source")
          (assoc-ref (bag-build-inputs bag) "libc")
          (assoc-ref (bag-build-inputs bag) "coreutils"))))

(test-assert "package->bag, propagated inputs"
  (let* ((dep    (dummy-package "dep"))
         (prop   (dummy-package "prop"
                   (propagated-inputs `(("dep" ,dep)))))
         (dummy  (dummy-package "dummy"
                   (inputs `(("prop" ,prop)))))
         (inputs (bag-transitive-inputs (package->bag dummy #:graft? #f))))
    (match (assoc "prop/dep" inputs)
      (("prop/dep" package)
       (eq? package dep)))))

(test-assert "bag->derivation"
  (parameterize ((%graft? #f))
    (let ((bag (package->bag gnu-make))
          (drv (package-derivation %store gnu-make)))
      (parameterize ((%current-system "foox86-hurd")) ;should have no effect
        (equal? drv (bag->derivation %store bag))))))

(test-assert "bag->derivation, cross-compilation"
  (parameterize ((%graft? #f))
    (let* ((target "mips64el-linux-gnu")
           (bag    (package->bag gnu-make (%current-system) target))
           (drv    (package-cross-derivation %store gnu-make target)))
      (parameterize ((%current-system "foox86-hurd") ;should have no effect
                     (%current-target-system "foo64-linux-gnu"))
        (equal? drv (bag->derivation %store bag))))))

(unless (false-if-exception (getaddrinfo "www.gnu.org" "80" AI_NUMERICSERV))
  (test-skip 1))
(test-assert "GNU Make, bootstrap"
  ;; GNU Make is the first program built during bootstrap; we choose it
  ;; here so that the test doesn't last for too long.
  (let ((gnu-make (@@ (gnu packages commencement) gnu-make-boot0)))
    (and (package? gnu-make)
         (or (location? (package-location gnu-make))
             (not (package-location gnu-make)))
         (let* ((drv (package-derivation %store gnu-make))
                (out (derivation->output-path drv)))
           (and (build-derivations %store (list drv))
                (file-exists? (string-append out "/bin/make")))))))

(test-eq "fold-packages" hello
  (fold-packages (lambda (p r)
                   (if (string=? (package-name p) "hello")
                       p
                       r))
                 #f))

(test-assert "find-packages-by-name"
  (match (find-packages-by-name "hello")
    (((? (cut eq? hello <>))) #t)
    (wrong (pk 'find-packages-by-name wrong #f))))

(test-assert "find-packages-by-name with version"
  (match (find-packages-by-name "hello" (package-version hello))
    (((? (cut eq? hello <>))) #t)
    (wrong (pk 'find-packages-by-name wrong #f))))

(test-end "packages")


(exit (= (test-runner-fail-count (test-runner-current)) 0))

;;; Local Variables:
;;; eval: (put 'dummy-package 'scheme-indent-function 1)
;;; End:
