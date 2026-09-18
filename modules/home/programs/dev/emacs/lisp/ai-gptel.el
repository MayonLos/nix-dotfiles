;;; ai-gptel.el --- LLM client  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/ai/.  codecompanion there, gptel here, against
;; the same DeepSeek key.

;;; Code:

;; The API key is the sops secret at /run/secrets/deepseek-api-key. It is read
;; lazily through a lambda so the token never sits in a variable that
;; `describe-variable' or a backtrace could print.
(use-package gptel
  :commands (gptel gptel-send gptel-menu gptel-rewrite gptel-add)
  :config
  (setq gptel-default-mode #'org-mode)
  (let ((deepseek
         (gptel-make-openai "DeepSeek"
           :host "api.deepseek.com"
           :endpoint "/chat/completions"
           :stream t
           :key (lambda () (my/read-secret "deepseek-api-key"))
           ;; These are the slugs codex/models.json pins. If the chat endpoint
           ;; rejects them, `gptel-menu' switches model at runtime — no rebuild.
           :models '(deepseek-v4-flash deepseek-v4-pro))))
    (setq gptel-backend deepseek
          gptel-model 'deepseek-v4-flash)))

(provide 'ai-gptel)
;;; ai-gptel.el ends here
