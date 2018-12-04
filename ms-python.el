;;; ms-python.el --- A lsp client for microsoft python language server.

;; Filename: ms-python.el
;; Description: A lsp client for microsoft python language server.
;; Author: Yong Cheng <xhcoding@163.com>
;; Copyright (C) 2018, Yong Cheng, all right reserved
;; Created: 2018-11-22 08:16:00
;; Version: 0.1
;; Last-Update:
;; URL: https://github.com/xhcoding/ms-python
;; Keywords: python
;; Compatibility: GNU Emacs 26.1

;;; This file is NOT part of GNU Emacs

;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:

;;; Require
(require 'lsp)

;;; Code:
;;


;;; Custom
(defcustom ms-python-dir
  ""
  "Dir containing Microsoft.Python.LanguageServer.dll."
  :type 'directory
  :group 'ms-python)


;;; Functions

(defun ms-python--get-python-env()
  "Return list with pyver-string and json-encoded list of python search paths."
  (let ((python (executable-find python-shell-interpreter))
        (ver "import sys; print(f\"{sys.version_info[0]}.{sys.version_info[1]}\");")
        (sp (concat "import json; sys.path.insert(0, '" default-directory "'); print(json.dumps(sys.path))")))
    (with-temp-buffer
      (call-process python nil t nil "-c" (concat ver sp))
      (subseq (split-string (buffer-string) "\n") 0 2))))

;; I based most of this on the vs.code implementation:
;; https://github.com/Microsoft/vscode-python/blob/master/src/client/activation/languageServer/languageServer.ts#L219
;; (it still took quite a while to get right, but here we are!)
(defun ms-python--initialization-options ()
  "Return initialization-options for LP startup."
  (destructuring-bind (pyver pysyspath) (ms-python--get-python-env)
    `(:interpreter (
                    :properties (
                                 :InterpreterPath ,(executable-find python-shell-interpreter)
                                 :DatabasePath ,(file-name-as-directory (expand-file-name "db/" ms-python-dir))
                                 :Version ,pyver))
                   ;; preferredFormat "markdown" or "plaintext"
                   ;; experiment to find what works best -- over here mostly plaintext
                   :displayOptions (
                                    :preferredFormat "plaintext"
                                    :trimDocumentationLines :json-false
                                    :maxDocumentationLineLength 0
                                    :trimDocumentationText :json-false
                                    :maxDocumentationTextLength 0)
                   :searchPaths ,(json-read-from-string pysyspath))))


(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection
                   (lambda() `("dotnet" ,(concat ms-python-dir "Microsoft.Python.LanguageServer.dll"))))
  :major-modes '(python-mode)
  :server-id 'ms-python
  :initialization-options #'ms-python--initialization-options))

(provide 'ms-python)
;;; ms-python.el ends here
