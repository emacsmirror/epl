;;; epl.el --- Emacs Package Library -*- lexical-binding: t; -*-

;; Copyright (C) 2013 Sebastian Wiesner

;; Author: Sebastian Wiesner <lunaryorn@gmail.com>
;; Maintainer: Johan Andersson <johan.rejeep@gmail.com>
;; Version: 0.0.1
;; Package-Requires: ((cl-lib "0.3"))
;; Keywords: convenience
;; URL: http://github.com/cask/epl

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A package management library for Emacs, based on package.el.

;; The purpose of this library is to wrap all the quirks and hassle of
;; package.el into a sane API.

;; The following functions comprise the public interface of this library:

;; `epl-package-p' determines whether an object is a package object.

;; `epl-package-name' gets the package name from a package object.

;; `epl-package-summary' gets the package summary from a package object.

;; `epl-package-version' gets the package version from a package object.

;; `epl-package-version-string' gets the package version as string from a
;; package object.

;; `epl-package-requirements' gets the requirements of a package.

;; `epl-package-installed-p' determines whether a package is installed.

;; `epl-initialize' initializes the package system and activates all
;; packages.

;; `epl-reset' resets the package system.

;; `epl-refresh' refreshes all package archives.

;; `epl-package-dir' gets the directory of packages.

;; `epl-default-package-dir' gets the default package directory.

;; `epl-change-package-dir' changes the directory of packages.

;; `epl-add-archive' adds a new package archive.

;; `epl-installed-packages' and `epl-available-packages' get all packages
;; installed and available for installation respectively.

;; `epl-find-installed-package' and `epl-find-available-packages' find installed
;; and available packages by name.

;; `epl-find-upgrades' finds all upgradable packages.

;; `epl-package-install' installs a package.

;; `epl-package-delete' deletes a package.

;; `epl-upgrade' upgrades packages.

;;; Code:

(require 'cl-lib)
(require 'package)

(setq package-archives nil)             ; Clear the default list of archives to
                                        ; let the user have exact control over
                                        ; all archives

(defun epl--package-desc-p (package)
  "Whether PACKAGE is a `package-desc' object.

Like `package-desc-p', but return nil, if `package-desc-p' is not
defined as function."
  (and (fbound 'package-desc-p) (package-desc-p package)))


;;;; Package directory
(defun epl-package-dir ()
  "Get the directory of packages."
  package-user-dir)

(defun epl-default-package-dir ()
  "Get the default directory of packages."
  (eval (car (get 'package-user-dir 'standard-value))))

(defun epl-change-package-dir (directory)
  "Change the directory of packages to DIRECTORY."
  (setq package-user-dir directory)
  (epl-initialize))


;;;; Package system management
(defvar epl--load-path-before-initialize nil
  "Remember the load path for `epl-reset'.")

(defun epl-initialize (&optional no-activate)
  "Load Emacs Lisp packages and activate them.

With NO-ACTIVATE non-nil, do not activate packages."
  (setq epl--load-path-before-initialize load-path)
  (package-initialize no-activate))

(defalias 'epl-refresh 'package-refresh-contents)

(defun epl-add-archive (name url)
  "Add a package archive with NAME and URL."
  (add-to-list 'package-archives (cons name url)))

(defun epl-reset ()
  "Reset the package system.

Clear the list of installed and available packages, the list of
package archives and reset the package directory."
  (setq package-alist nil
        package-archives nil
        package-archive-contents nil
        load-path epl--load-path-before-initialize)
  (when (boundp 'package-obsolete-alist) ; Legacy package.el
    (setq package-obsolete-alist nil))
  (epl-change-package-dir (epl-default-package-dir)))


;;;; Package structures
(cl-defstruct (epl-requirement
               (:constructor epl-requirement-create))
  "Structure describing a requirement.

Slots:

`name' The name of the required package, as symbol.

`version' The version of the required package, as version list."
  name
  version)

(defun epl-requirement-version-string (requirement)
  "The version of a REQUIREMENT, as string."
  (package-version-join (epl-requirement-version requirement)))

(cl-defstruct (epl-package (:constructor epl-package-create))
  "Structure representing a package.

Slots:

`name' The package name, as symbol.

`description' The package description.

The format package description varies between package.el
variants.  For `package-desc' variants, it is simply the
corresponding `package-desc' object.  For legacy variants, it is
a vector `[VERSION REQS DOCSTRING]'.

Do not access `description' directly, but instead use the
`epl-package' accessors."
  name
  description)

(defmacro epl-package-as-description (var &rest body)
  "Cast VAR to a package description in BODY.

VAR is a symbol, bound to an `epl-package' object.  This macro
casts this object to the `description' object, and binds the
description to VAR in BODY."
  (declare (indent 1))
  (unless (symbolp var)
    (signal 'wrong-type-argument (list #'symbolp var)))
  `(if (epl-package-p ,var)
       (let ((,var (epl-package-description ,var)))
         ,@body)
     (signal 'wrong-type-argument (list #'epl-package-p ,var))))

(defun epl-package--package-desc-p (package)
  "Whether the description of PACKAGE is a `package-desc'."
  (epl--package-desc-p (epl-package-description package)))

(defun epl-package-version (package)
  "Get the version of PACKAGE, as version list."
  (epl-package-as-description package
    (cond
     ((fboundp 'package-desc-version) (package-desc-version package))
     ;; Legacy
     ((fboundp 'package-desc-vers)
      (let ((version (package-desc-vers package)))
        (if (listp version) version (version-to-list version))))
     (:else (error "Cannot get version from %S" package)))))

(defun epl-package-version-string (package)
  "Get the version from a PACKAGE, as string."
  (package-version-join (epl-package-version package)))

(defun epl-package-summary (package)
  "Get the summary of PACKAGE, as string."
  (epl-package-as-description package
    (cond
     ((fboundp 'package-desc-summary) (package-desc-summary package))
     ((fboundp 'package-desc-doc) (package-desc-doc package)) ; Legacy
     (:else (error "Cannot get summary from %S" package)))))

(defun epl-requirement--from-req (req)
  "Create a `epl-requirement' from a `package-desc' REQ."
  (cl-destructuring-bind (name version) req
    (epl-requirement-create :name name
                            :version (if (listp version) version
                                       (version-to-list version)))))

(defun epl-package-requirements (package)
  "Get the requirements of PACKAGE.

The requirements are a list of `epl-requirement' objects."
  (epl-package-as-description package
    (mapcar #'epl-requirement--from-req (package-desc-reqs package))))

(defun epl-package-->= (pkg1 pkg2)
  "Determine whether PKG1 is before PKG2 by version."
  (not (version-list-< (epl-package-version pkg1)
                       (epl-package-version pkg2))))

(defun epl-package--from-package-desc (package-desc)
  "Create an `epl-package' from a PACKAGE-DESC.

PACKAGE-DESC is a `package-desc' object, from recent package.el
variants."
  (epl-package-create :name (package-desc-name package-desc)
                      :description package-desc))

(defun epl-package-from-buffer (&optional buffer)
  "Create an `epl-package' object from BUFFER.

BUFFER defaults to the current buffer."
  (let ((info (with-current-buffer (or buffer (current-buffer))
                (package-buffer-info))))
    (if (epl--package-desc-p info)
        (epl-package--from-package-desc info)
      ;; For legacy package.el, info is a vector [NAME REQUIRES DESCRIPTION
      ;; VERSION COMMENTARY].  We need to re-shape this vector into the
      ;; `package-alist' format [VERSION REQUIRES DESCRIPTION] to attach it to
      ;; the new `epl-package'.
      (let ((name (intern (aref info 0)))
            (info (vector (aref info 3) (aref info 1) (aref info 2))))
        (epl-package-create :name name :description info)))))

(defun epl-package-from-file (file-name)
  "Parse the package headers the file at FILE-NAME.

Return an `epl-package' object with the header metadata."
  (with-temp-buffer
    (insert-file-contents file-name)
    (epl-package-from-buffer (current-buffer))))


;;;; Package database access
(defun epl-package-installed-p (package)
  "Determine whether a PACKAGE is installed.

PACKAGE is either a package name as symbol, or a package object."
  (let ((name (if (epl-package-p package)
                  (epl-package-name package)
                package))
        (version (when (epl-package-p package)
                   (epl-package-version package))))
    (package-installed-p name version)))

(defun epl--parse-package-list-entry (entry)
  "Parse a list of packages from ENTRY.

ENTRY is a single entry in a package list, e.g. `package-alist',
`package-archive-contents', etc.  Typically it is a cons cell,
but the exact format varies between package.el versions.  This
function tries to parse all known variants.

Return a list of `epl-package' objects parsed from ENTRY."
  (let ((descriptions (cdr entry)))
    (cond
     ((listp descriptions)
      (sort (mapcar #'epl-package--from-package-desc descriptions)
            #'epl-package-->=))
     ;; Legacy package.el has just a single package in an entry, which is a
     ;; standard description vector
     ((vectorp descriptions)
      (list (epl-package-create :name (car entry)
                                :description descriptions)))
     (:else (error "Cannot parse entry %S" entry)))))

(defun epl-installed-packages ()
  "Get all installed packages.

Return a list of package objects."
  (apply #'append (mapcar #'epl--parse-package-list-entry package-alist)))

(defun epl--find-package-in-list (name list)
  "Find a package by NAME in a package LIST.

Return a list of corresponding `epl-package' objects."
  (let ((entry (assq name list)))
    (when entry
      (epl--parse-package-list-entry entry))))

(defun epl-find-installed-package (name)
  "Find an installed package by NAME.

NAME is a package name, as symbol.

Return the installed package as `epl-package' object, or nil, if
no package with NAME is installed."
  ;; FIXME: We must return *all* installed packages here
  (car (epl--find-package-in-list name package-alist)))

(defun epl-available-packages ()
  "Get all packages available for installed.

Return a list of package objects."
  (apply #'append (mapcar #'epl--parse-package-list-entry
                          package-archive-contents)))

(defun epl-find-available-packages (name)
  "Find available packages for NAME.

NAME is a package name, as symbol.

Return a list of available packages for NAME, sorted by version
number in descending order.  Return nil, if there are no packages
for NAME."
  (epl--find-package-in-list name package-archive-contents))

(cl-defstruct (epl-upgrade
               (:constructor epl-upgrade-create))
  "Structure describing an upgradable package.
Slots:

`installed' The installed package

`available' The package available for installation."
  installed
  available)

(defun epl-find-upgrades (&optional packages)
  "Find all upgradable PACKAGES.

PACKAGES is a list of package objects to upgrade, defaulting to
all installed packages.

Return a list of `epl-upgrade' objects describing all upgradable
packages."
  (let ((packages (or packages (epl-installed-packages)))
        upgrades)
    (dolist (pkg packages)
      (let* ((version (epl-package-version pkg))
             (name (epl-package-name pkg))
             ;; Find the latest available package for NAME
             (available-pkg (car (epl-find-available-packages name)))
             (available-version (when available-pkg
                                  (epl-package-version available-pkg))))
        (when (and available-version (version-list-< version available-version))
          (push (epl-upgrade-create :installed pkg
                                    :available available-pkg)
                upgrades))))
    (nreverse upgrades)))


;;;; Package operations

(defun epl-package-install (package &optional force)
  "Install a PACKAGE.

PACKAGE is a `epl-package' object.  If FORCE is given and
non-nil, install PACKAGE, even if it is already installed."
  (when (or force (not (epl-package-installed-p package)))
    (if (epl-package--package-desc-p package)
        (package-install (epl-package-description package))
      ;; The legacy API installs by name.  We have no control over versioning,
      ;; etc.
      (package-install (epl-package-name package)))))

(defun epl-package-delete (package)
  "Delete a PACKAGE.

PACKAGE is a `epl-package' object to delete."
  ;; package-delete allows for packages being trashed instead of fully deleted.
  ;; Let's prevent his silly behavior
  (let ((delete-by-moving-to-trash nil))
    ;; The byte compiler will warn us that we are calling `package-delete' with
    ;; the wrong number of arguments, since it can't infer that we guarantee to
    ;; always call the correct version.  Thus we suppress all warnings when
    ;; calling `package-delete'.  I wish there was a more granular way to
    ;; disable just that specific warning, but it is what it is.
    (if (epl-package--package-desc-p package)
        (with-no-warnings
          (package-delete (epl-package-description package)))
      ;; The legacy API deletes by name (as string!) and version instead by
      ;; descriptor.  Hence `package-delete' takes two arguments.  For some
      ;; insane reason, the arguments are strings here!
      (let ((name (symbol-name (epl-package-name package)))
            (version (epl-package-version-string package)))
        (with-no-warnings
          (package-delete name version))))))

(defun epl-upgrade (&optional packages preserve-obsolete)
  "Upgrade PACKAGES.

PACKAGES is a list of package objects to upgrade, defaulting to
all installed packages.

The old versions of the updated packages are deleted, unless
PRESERVE-OBSOLETE is non-nil.

Return a list of all performed upgrades, as a list of
`epl-upgrade' objects."
  (let ((upgrades (epl-find-upgrades packages)))
    (dolist (upgrade upgrades)
      (epl-package-install (epl-upgrade-available upgrade))
      (unless preserve-obsolete
        (epl-package-delete (epl-upgrade-installed upgrade))))
    upgrades))

(provide 'epl)

;;; epl.el ends here
