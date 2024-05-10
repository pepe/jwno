(use jw32/_winuser)
(use jw32/_libloaderapi)
(use jw32/_combaseapi)
(use jw32/_uiautomation)

(use ./key)
(use ./cmd)
(use ./win)
(use ./hook)
(use ./ui)
(use ./uia)
(use ./config)
(use ./util)

(import ./repl)
(import ./const)
(import ./log)


(defn main-loop [cli-args context]
  (forever
   (def event (ev/select ;(in context :event-sources)))

   (match event
     [:take chan msg]
     (match msg
       [:ui/initialized thread-id msg-hwnd]
       (do
         (:initialized (in context :ui-manager) thread-id msg-hwnd)
         (def config-env (load-config-file [(in cli-args "config")] context))
         (log/debug "config-env = %n" config-env))

       :ui/exit
       (break)

       [:uia/window-opened hwnd]
       (:window-opened (in context :window-manager) hwnd)

       :uia/focus-changed
       (:focus-changed (in context :window-manager))

       [:key/command cmd]
       (:dispatch-command (in context :command-manager) cmd)

       _
       (log/warning "Unknown message: %n" msg))
     _
     (log/warning "Unhandled ev/select event: %n" event))))


(defn main [& args]
  (def cli-args (parse-command-line))
  (when (nil? cli-args)
    (os/exit 1))

  (let [log-path (in cli-args "log-file")
        loggers (if (nil? log-path)
                  [log/print-logger]
                  [log/print-logger (fn [] (log/file-logger log-path))])]
    (try
      (log/init (in cli-args "log-level") ;loggers)
      ((err fib)
       (show-error-and-exit err 1))))

  (log/debug "in main")
  (log/debug "cli-args = %n" cli-args)

  (def context @{}) # Forward declaration

  (def hook-man (hook-manager))

  (def command-man (command-manager))

  (def ui-man (ui-manager (GetModuleHandle nil) (in args 0) @{}))

  (def uia-man
    (try
      (uia-manager)
      ((err fib)
       (show-error-and-exit err 1))))

  (def key-man (key-manager ui-man))

  (def window-man
    (try
      (window-manager uia-man hook-man)
      ((err fib)
       (show-error-and-exit err 1))))

  # context will only get referenced after the main-loop is running
  # and when the first REPL client connects.
  (def repl-server (repl/start-server context))

  (put context :hook-manager hook-man)
  (put context :command-manager command-man)
  (put context :ui-manager ui-man)
  (put context :uia-manager uia-man)
  (put context :event-sources [(in uia-man :chan) (in ui-man :chan)])
  (put context :key-manager key-man)
  (put context :window-manager window-man)
  (put context :repl repl-server)

  (add-default-commands command-man context)

  (main-loop cli-args context)

  (repl/stop-server repl-server)
  (:destroy uia-man)
  (log/deinit))
