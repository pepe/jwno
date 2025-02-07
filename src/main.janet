(import spork/netrepl)

(use jw32/_winuser)
(use jw32/_libloaderapi)
(use jw32/_combaseapi)
(use jw32/_util)

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
       (let [default-config-file-path (string (get-exe-dir) const/DEFAULT-CONFIG-FILE-NAME)
             paths (in cli-args "config")
             config-file-paths (if (or (nil? paths) (empty? paths))
                                 [default-config-file-path]
                                 paths)
             ui-man (in context :ui-manager)]
         (:initialized ui-man thread-id msg-hwnd)
         (def config-env
           (try
             (load-config-file config-file-paths context)
             ((err fib)
              (:show-error-and-exit
                 ui-man
                 (string/format "Failed to load config file: %n\n\n%s\n%s"
                                config-file-paths
                                err
                                (get-stack-trace fib)))
              nil)))
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


(defn format-help-msg [msg]
  (->> msg
       # Add a new line after "Optional:", so that it's clearly separated
       # from the actual help text
       (peg/replace-all
        ~{:main " Optional:"}
        "Optional:\n")
       # Fix the help text for "--help" flag, which we can't control at all
       (peg/replace-all
        ~{:main (sequence (capture "-h, --help") (some (set " \t\f\v")) (capture (some (if-not "\n" 1))))}
        (fn [_str flags text]
          (string flags "\n" text "\n")))
       # Remove excessive spaces before flag names
       (peg/replace-all
        ~{:main (sequence "\n" (some (set " \t\f\v")) "-")}
        "\n-")))


(defn parse-args []
  (def out-buf @"")
  (def cli-args
    (try
      (with-dyns [:out out-buf]
        (parse-command-line))
      ((err fib)
       (show-error-and-exit err 1 (get-stack-trace fib)))))

  (when (nil? cli-args)
    # out-buf contains the help message built by spork/argparse.
    # Re-format it so that it looks nicer on MessageBox.
    # It's a workaround until we get a proper message box with
    # monospaced fonts.
    (def formatted (format-help-msg out-buf))
    (show-error-and-exit formatted 1))

  cli-args)


(defn run-repl-client [cli-args]
  (def repl-addr (in cli-args "repl"))
  (when (nil? repl-addr)
    (show-error-and-exit "Jwno is started in client mode, but REPL address is not specified." 1))
  (try
    (do
      (alloc-console-and-reopen-streams)
      (netrepl/client ;repl-addr))
    ((err fib)
     (show-error-and-exit err 1 (get-stack-trace fib)))))


(defn init-log [cli-args]
  (let [log-path (in cli-args "log-file")
        loggers (if (nil? log-path)
                  [log/print-logger]
                  [log/print-logger (fn [] (log/file-logger log-path))])]
    (try
      (log/init (in cli-args "log-level") ;loggers)
      ((err fib)
       (show-error-and-exit err 1 (get-stack-trace fib))))))


(defn init-com []
  (try
    (CoInitializeEx nil COINIT_MULTITHREADED)
    ((err fib)
     (show-error-and-exit err 1 (get-stack-trace fib)))))


(defn main [& args]
  (def cli-args (parse-args))

  (when (in cli-args "client")
    (run-repl-client cli-args)
    (os/exit 0))

  (init-log cli-args)

  (log/debug "cli-args = %n" cli-args)

  (init-com)

  (def context @{}) # Forward declaration

  (def hook-man (hook-manager))

  (def command-man (command-manager))

  (def ui-man (ui-manager (GetModuleHandle nil) (in args 0) nil))

  (def uia-man
    (try
      (uia-manager)
      ((err fib)
       (show-error-and-exit err 1 (get-stack-trace fib)))))

  (def key-man (key-manager ui-man))

  (def window-man
    (try
      (window-manager uia-man ui-man hook-man)
      ((err fib)
       (show-error-and-exit err 1 (get-stack-trace fib)))))

  (def repl-server
    (if-let [repl-addr (in cli-args "repl")]
      # context will only get referenced after the main-loop is running
      # and when the first REPL client connects.
      (repl/start-server context ;repl-addr)
      nil))

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

  (when repl-server
    (repl/stop-server repl-server))
  (:destroy window-man)
  (:destroy uia-man)
  (CoUninitialize)
  (log/deinit))
