;;; ms-python.el --- A lsp client for microsoft python language server.

;; Filename: ms-python.el
;; Description: A lsp client for microsoft python language server.
;; Package-Requires: ((emacs "26.1") (lsp-mode "5.0"))
;; Author: Yong Cheng <xhcoding@163.com>
;; Created: 2018-11-22 08:16:00
;; Version: 1.0
;; Last-Update: 2018-12-06 19:00
;; URL: https://github.com/xhcoding/ms-python
;; Keywords: tools
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
;; Please read README.org

;;; Require:

(require 'lsp)
(require 'cl-lib)
;;; Code:
;;

(defgroup ms-python nil
  "Microsoft python language server adapter for LSP mode."
  :prefix "ms-python-"
  :group 'applications
  :link '(url-link :tag "GitHub" "https://github.com/xhcoding/ms-python"))

;;; Custom:
(defcustom ms-python-server-install-dir
  (locate-user-emacs-file "ms-pyls/server/")
  "Install directory for microsoft python language server."
  :group 'ms-python
  :risky t
  :type 'directory)

(defcustom ms-python-dotnet-install-dir
  (locate-user-emacs-file "ms-pyls/dotnet/")
  "Install directory for dotnet."
  :group 'ms-python
  :risky t
  :type 'directory)

(defcustom ms-python-database-dir
  "DefaultDB"
  "Cache data storge directory.
It is relative to `ms-python-server-install-dir',You can set a absolute path."
  :group 'ms-python
  :risky t
  :type 'directory)


;;; Function:

(defun ms-python--locate-server-path()
  "Return Microsoft.Python.LanguageServer.dll's path, it is server entry.
If not found, ask the user whether to install."
  (let* ((server-dir ms-python-server-install-dir)
         (server-entry (expand-file-name "Microsoft.Python.LanguageServer.dll" server-dir)))
    (unless (file-exists-p server-entry)
      (if (yes-or-no-p "Microsoft Python Language Server is not installed. Do you want to install it?")
          (ms-python--ensure-server)
        (error "Cannot start microsoft python language server without server be installed!")))
    server-entry))

(defun ms-python--locate-dotnet()
  "Return dotnet's path.If not found, ask the user whether to install."
  (let ((dotnet-exe (or
                     (and (file-directory-p ms-python-dotnet-install-dir)
                          (car (directory-files ms-python-dotnet-install-dir t "^dotnet\\(\\.exe\\)?$"))) ;; Specified installation path
                     (executable-find "dotnet"))))                               ;; System path
    (unless (and dotnet-exe
                 (not (string-empty-p (shell-command-to-string (concat dotnet-exe " --list-runtimes"))))
                 (not (string-empty-p (shell-command-to-string (concat dotnet-exe " --list-sdks")))))
      (if (yes-or-no-p "Dotnet is not installed. Do you want to install it?")
          (ms-python--ensure-dotnet)
        (error "Cannot install server without dotnet!"))
      (setq dotnet-exe (car (directory-files ms-python-dotnet-install-dir t "^dotnet$"))))
    dotnet-exe))

(defun ms-python--ensure-server()
  "Ensure Microsoft Python Language Server."
  (let* ((dotnet (ms-python--locate-dotnet))
         (default-directory ms-python-server-install-dir)
         (command)
         (log))
    (when (file-directory-p default-directory)
      (delete-directory default-directory t))
    (mkdir default-directory t)
    (setq command (concat "git clone --depth 1 https://github.com/Microsoft/python-language-server.git"))
    (message "Clone server...")
    (shell-command command)
    (setq command (concat dotnet " build -c Release -o " default-directory " python-language-server/src/LanguageServer/Impl"))
    (message "Building server...")
    (setq log (shell-command-to-string command))
    (with-temp-buffer
      (insert log)
      (goto-char (point-min))
      (unless (search-forward-regexp "Build succeeded." nil t)
        (message "%s" log)
        (error "Build server failed!You can check log message in *MESSAGE* buffer!"))
      (message "Build server finished.")
      )))

(defun ms-python--ensure-dotnet()
  "Ensure dotnet sdk and runtime."
  (let* ((default-directory ms-python-dotnet-install-dir)
         (url-list (ms-python--dotnet-url))
         (sdk-url (cdr (assoc 'sdk-url url-list)))
         (sdk-filename (cdr (assoc 'sdk-filename url-list)))
         (sdk-sha-filename (cdr (assoc 'sdk-sha-filename url-list)))
         )
    (when (file-directory-p default-directory)
      (delete-directory default-directory t))
    (mkdir default-directory t)
    ;; download sdk
    (url-copy-file  sdk-url sdk-filename t)
    ;;  checksum
    (url-copy-file (cdr (assoc 'sdk-sha-url url-list)) sdk-sha-filename)
    (unless (and (and (file-exists-p sdk-filename) (file-exists-p sdk-sha-filename))
                 (string=
                  (with-temp-buffer (insert-file-contents sdk-sha-filename)
                                    (search-forward-regexp sdk-filename)
                                    (car (split-string (buffer-substring (line-beginning-position) (line-end-position)))))
                  (with-temp-buffer (insert-file-contents-literally sdk-filename)
                                    (upcase (secure-hash 'sha512 (current-buffer)))))))
    (error "Download file failed.You can manually download %s, then decompress it to %s!"  sdk-filename default-directory)
    ;; decompress
    (if (eq system-type 'windows-nt)
        (unless (eq 0 (shell-command (concat "expand " sdk-filename " " default-directory)))
          (error "Decompress %s failed. you can manually decompress it to %s!" sdk-filename default-directory))
      (unless (eq 0 (shell-command (concat "tar -zxvf " sdk-filename " " dotnet-dir)))
        (error "Decompress %s failed. you can manually decompress it to %s!" sdk-filename default-directory)))))

(defun ms-python--dotnet-url()
  "Return url alist."
  (let* ((root-url "https://dotnet.microsoft.com/download/thank-you")
         (sdk-version "2.2.100")
         (arch "x64")
         (system (case system-type
                   ('gnu/linux "linux")
                   ('darwin "macos")
                   ('windows-nt "windows")))
         (suffix (if (string= system "windows")
                     ".zip"
                   ".tar.gz")))
    `(
      (sdk-url . ,(format "%s/dotnet-sdk-%s-%s-%s-binaries" root-url sdk-version system arch))
      (sdk-sha-url . ,(format "https://dotnetcli.blob.core.windows.net/dotnet/checksums/%s-sdk-sha.txt" sdk-version))
      (sdk-filename .,(format "dotnet-sdk-%s-%s-%s%s" sdk-version system arch suffix))
      (sdk-sha-filename . ,(format "sdk-sha-%s.txt" sdk-version))
      )))

(defun ms-python--ls-command()
  "LS startup command."
  (let ((dotnet (ms-python--locate-dotnet))
        (server (ms-python--locate-server-path)))
    `(,dotnet
      ,server)))

(defun ms-python--publish-server-started(_workspace _params)
  "Publish server started."
  (message "Microsoft python language server started!"))

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
                                 :DatabasePath ,(file-name-as-directory (expand-file-name ms-python-database-dir ms-python-server-install-dir))
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

(defun ms-python--doc-filter (doc)
  "Filter some entities from DOC."
  (let ((pairs [["&nbsp;" " "] ["" ""] ]))
    (with-temp-buffer
      (insert doc)
      (mapc
       (lambda (pair)
         (goto-char (point-min))
         (while (search-forward-regexp (elt pair 0) nil "noerrro")
           (replace-match (elt pair 1))))
       pairs)
      (buffer-string))))

;; lsp-ui-doc--extract gets called when hover docs are requested
;; as always, we have to remove Microsoft's unnecessary some entities
(advice-add 'lsp-ui-doc--extract
            :filter-return #'ms-python--doc-filter)

;; lsp-ui-sideline--format-info gets called when lsp-ui wants to show hover info in the sideline
;; again some entities has to be removed
(advice-add 'lsp-ui-sideline--format-info
            :filter-return #'ms-python--doc-filter)

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection #'ms-python--ls-command)
  :major-modes '(python-mode)
  :server-id 'ms-python
  :notification-handlers
  (lsp-ht ("python/languageServerStarted" #'ms-python--publish-server-started))
  :initialization-options #'ms-python--initialization-options))


(provide 'ms-python)
;;; ms-python.el ends here
