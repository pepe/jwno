(use jw32/winuser)

(use ./resource)

(import ./log)


(defn cmd-quit [context]
  (if (in context :msg-hwnd)
    (PostMessage (in context :msg-hwnd) WM_COMMAND ID_MENU_EXIT 0)
    (os/exit 0)))


(defn cmd-map-to [key-code key-state]
  (def input
    (INPUT :type INPUT_KEYBOARD
           :ki.wVk key-code
           :ki.dwFlags (case key-state
                         :up KEYEVENTF_KEYUP
                         :down 0)))
  (SendInput [input]))


(defn cmd-send-keys [keys context]
  (let [input-seqs @[]]
    (var cur-inputs @[])
    (array/push input-seqs cur-inputs)
    (each k keys
      (match k
        [:wait duration]
        (do
          (array/push input-seqs duration)
          (set cur-inputs @[])
          (array/push input-seqs cur-inputs))

        [key-code key-state]
        (array/push cur-inputs
                    (INPUT :type INPUT_KEYBOARD
                           :ki.wVk key-code
                           :ki.dwFlags (if (= key-state :up)
                                         KEYEVENTF_KEYUP
                                         0)))

        key-code
        (do
          # Down event
          (array/push cur-inputs
                      (INPUT :type INPUT_KEYBOARD
                             :ki.wVk key-code
                             :ki.dwFlags 0))
          # Up event
          (array/push cur-inputs
                      (INPUT :type INPUT_KEYBOARD
                             :ki.wVk key-code
                             :ki.dwFlags KEYEVENTF_KEYUP)))

        _
        (log/warning "Unknown key spec: %n" k)))

    (log/debug "input-seqs = %n" input-seqs)

    (each seq input-seqs
      (if (number? seq)
        (ev/sleep seq)
        (SendInput seq)))))


(defn cmd-retile [context]
  (def wm (in context :wm))
  (def cur-win (:get-current-window (in wm :layout)))
  (:retile wm)
  (:activate wm cur-win))


(defn cmd-split [context dir nfr ratios to-activate]
  (def cur-frame (:get-current-frame (get-in context [:wm :layout])))
  (:split cur-frame dir nfr ratios)
  (:retile (in context :wm) cur-frame)
  (:activate (in context :wm) (get-in cur-frame [:children to-activate])))


(defn cmd-flatten [context]
  (def cur-frame (:get-current-frame (get-in context [:wm :layout])))
  (def parent (in cur-frame :parent))
  (cond
    (nil? parent)
    (break)

    (not= :frame (in parent :type))
    (break)

    true
    (do
      (def cur-win (:get-current-window cur-frame))
      (:flatten parent)
      (:retile (in context :wm) parent)
      (if cur-win
        (:activate cur-win)
        (when (not (empty? (in parent :children)))
          (:activate (get-in parent [:children 0])))))))


(defn cmd-next-frame [context]
  (def cur-frame (:get-current-frame (get-in context [:wm :layout])))
  (when-let [next-fr (:get-next-frame (get-in context [:wm :layout]) cur-frame)]
    (:activate (in context :wm) next-fr)))


(defn cmd-prev-frame [context]
  (def cur-frame (:get-current-frame (get-in context [:wm :layout])))
  (when-let [prev-fr (:get-prev-frame (get-in context [:wm :layout]) cur-frame)]
    (:activate (in context :wm) prev-fr)))


(defn cmd-next-window-in-frame [context]
  (def cur-frame (:get-current-frame (get-in context [:wm :layout])))
  (:purge-windows cur-frame)
  (when-let [cur-win (:get-current-window cur-frame)]
    (when-let [sibling (:get-next-sibling cur-win)]
      (:activate (in context :wm) sibling))))


(defn cmd-prev-window-in-frame [context]
  (def cur-frame (:get-current-frame (get-in context [:wm :layout])))
  (:purge-windows cur-frame)
  (when-let [cur-win (:get-current-window cur-frame)]
    (when-let [sibling (:get-prev-sibling cur-win)]
      (:activate (in context :wm) sibling))))


(defn dispatch-command [cmd key-struct key-state context]
  (match cmd
    :quit
    (when (= key-state :down)
      (cmd-quit context))

    [:map-to key-code]
    (cmd-map-to key-code key-state)

    [:send-keys & keys]
    (when (= key-state :down)
      (cmd-send-keys keys context))

    :retile
    (when (= key-state :down)
      (cmd-retile context))

    [:split dir nfr ratios to-activate]
    (when (= key-state :down)
      (cmd-split context dir nfr ratios to-activate))

    :flatten
    (when (= key-state :down)
      (cmd-flatten context))

    :next-frame
    (when (= key-state :down)
      (cmd-next-frame context))

    :prev-frame
    (when (= key-state :down)
      (cmd-prev-frame context))

    :next-window-in-frame
    (when (= key-state :down)
      (cmd-next-window-in-frame context))

    :prev-window-in-frame
    (when (= key-state :down)
      (cmd-prev-window-in-frame context))

    _
    (log/warning "Unknown command: %n" cmd)))
