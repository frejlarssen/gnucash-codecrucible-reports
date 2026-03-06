;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; project-tags-balance.scm : Project balance report
;;
;; Summarises income and expenses per project, where projects
;; are identified by tags like #P-general, #P-FEB2026 attached
;; to transaction descriptions, notes or split memos.
;;
;; Based on the custom transaction report engine in
;; transaction-extended.scm and the tag handling ideas in
;; transaction-tags.scm.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-module (gnucash report project-tags-balance))

(use-modules (gnucash core-utils))
(use-modules (gnucash engine))
(use-modules (gnucash app-utils))
(use-modules (gnucash utilities))
(use-modules (gnucash report report-core)
             (gnucash report report-utilities)
             (gnucash report options-utilities)
             (gnucash report html-document)
             (gnucash report html-style-info)
             (gnucash report html-utilities)
             (gnucash report html-table)
             (gnucash report html-text))
(use-modules (srfi srfi-1))
(use-modules (ice-9 match))
(use-modules (ice-9 regex))
(use-modules (ice-9 i18n))

;; Basic option names reused from the transaction report

(define optname-accounts (N_ "Accounts"))
(define optname-startdate (N_ "Start Date"))
(define optname-enddate (N_ "End Date"))
(define optname-date-source (N_ "Date Filter"))
(define optname-table-export (N_ "Table for Exporting"))
(define optname-infobox-display (N_ "Add options summary"))

;; Currency
(define pagename-currency (N_ "Currency"))
(define optname-price-source (N_ "Price Source"))
(define optname-common-currency (N_ "Common Currency"))
(define optname-currency (N_ "Report's currency"))

;; Simple display options for this report
(define pagename-display (N_ "Display"))
(define optname-project-tag-prefix (N_ "Project Tag Prefix"))
(define optname-strip-prefix (N_ "Strip Prefix From Name"))

;; Default project tag prefix
(define def:project-tag-prefix "#P-")

;; Special accounts for project reallocations
(define ptb:realloc-expense-account-name "Expenses:Project Reallocations")
(define ptb:realloc-income-account-name "Income:Project Reallocations")

(define (ptb:realloc-expense-account? account)
  (string=? (gnc-account-get-full-name account) ptb:realloc-expense-account-name))

(define (ptb:realloc-income-account? account)
  (string=? (gnc-account-get-full-name account) ptb:realloc-income-account-name))

(define no-project-tag-style "primary-subheading")

;; Helper: simple association helpers

;; Numeric helpers for gnc-numeric values.
(define (ptb:n+ a b)
  (gnc-numeric-add a b 0 GNC-DENOM-LCD))

(define (ptb:n- a b)
  (gnc-numeric-sub a b 0 GNC-DENOM-LCD))

(define ptb:zero (gnc-numeric-zero))

;; Simple HTML table cell helpers, following patterns from standard
;; reports like account-summary and investment-lots.

(define (ptb:header-cell label)
  (gnc:make-html-table-cell/markup "number-header" label))

(define (ptb:text-cell value)
  (gnc:make-html-table-cell/markup "text-cell" value))

(define (ptb:number-cell value)
  (gnc:make-html-table-cell/markup "number-cell" value))

(define (ptb:total-label-cell label)
  (gnc:make-html-table-cell/markup "total-label-cell" label))

(define (ptb:total-number-cell value)
  (gnc:make-html-table-cell/markup "total-number-cell" value))

;; Per-project accumulator helpers.
;; For each project tag we keep a list of four gnc-numeric values:
;; (income expense realloc-income realloc-expense)

(define (ptb:make-totals income expense realloc-income realloc-expense)
  (list income expense realloc-income realloc-expense))

(define (ptb:totals-income totals)
  (list-ref totals 0))

(define (ptb:totals-expense totals)
  (list-ref totals 1))

(define (ptb:totals-realloc-income totals)
  (list-ref totals 2))

(define (ptb:totals-realloc-expense totals)
  (list-ref totals 3))

;; table: alist of (project-tag . (income expense realloc-income realloc-expense))
(define (alist-inc! table key income-delta expense-delta realloc-income-delta realloc-expense-delta)
  (let ((existing (assoc key table)))
    (if existing
        (let* ((cur (cdr existing))
               (new (ptb:make-totals
                     (ptb:n+ (ptb:totals-income cur) income-delta)
                     (ptb:n+ (ptb:totals-expense cur) expense-delta)
                     (ptb:n+ (ptb:totals-realloc-income cur) realloc-income-delta)
                     (ptb:n+ (ptb:totals-realloc-expense cur) realloc-expense-delta))))
          (set-cdr! existing new)
          table)
        (let ((initial (ptb:make-totals
                        income-delta
                        expense-delta
                        realloc-income-delta
                        realloc-expense-delta)))
          (cons (cons key initial) table)))))

;; Helper: find first project tag matching the prefix in split/transaction.
;; Small, self-contained version inspired by transaction-tags.scm.

(define (ptb:extract-project-tag split tag-prefix)
  (let* ((rx (make-regexp
              (string-append
               (regexp-substitute/global
                #f "[#-.]|[[-^]|[?|{}]" tag-prefix
                'pre (lambda (m) (string-append "\\" (match:substring m))) 'post)
               "[^ ]*")))
         (try (lambda (s)
                (and s (regexp-exec rx s)))))
    (match (or (try (xaccSplitGetMemo split))
               (try (xaccTransGetNotes (xaccSplitGetParent split)))
               (try (xaccTransGetDescription (xaccSplitGetParent split))))
      (#f #f)
      (sm
       (let ((tag (match:substring sm)))
         (and (string-prefix? tag-prefix tag) tag))))))

;; Helper: determine whether an account should be treated as income or expense

(define (ptb:income-or-expense? account)
  (let ((type (xaccAccountGetType account)))
    (or (eq? type ACCT-TYPE-INCOME)
        (eq? type ACCT-TYPE-EXPENSE))))

;; Options generator: small, focused set based on trep-options

(define (ptb:options-generator)
  (let ((options (gnc-new-optiondb)))

    ;; General/date options
    (gnc:options-add-date-interval!
     options gnc:pagename-general optname-startdate optname-enddate "a")

    (gnc-register-multichoice-option options
      gnc:pagename-general optname-date-source
      "a5" (G_ "Specify date to filter by…")
      "posted"
      (list (vector 'posted (G_ "Date Posted"))
            (vector 'reconciled (G_ "Reconciled Date"))
            (vector 'entered (G_ "Date Entered"))))

    (gnc-register-simple-boolean-option options
      gnc:pagename-general optname-table-export
      "g" (G_ "Formats the table suitable for cut & paste exporting with extra cells.")
      #f)

    (gnc-register-multichoice-option options
      gnc:pagename-general optname-infobox-display
      "h" (G_ "Add summary of options.")
      "no-match"
      (list (vector 'no-match (G_ "If no transactions matched"))
            (vector 'always (G_ "Always"))
            (vector 'never (G_ "Never"))))

    ;; Accounts options: list of accounts to consider.
    ;; Default to all INCOME and EXPENSE accounts, similar to income/expense reports.

    (gnc-register-account-list-option options
      gnc:pagename-accounts optname-accounts
      "a" (G_ "Report on these accounts.")
      (gnc:filter-accountlist-type
       (list ACCT-TYPE-INCOME ACCT-TYPE-EXPENSE)
       (gnc-account-get-descendants-sorted (gnc-get-current-root-account))))

    ;; Currency options (reuse helpers)

    (gnc-register-simple-boolean-option options
      pagename-currency optname-common-currency
      "a" (G_ "Convert all amounts into a common currency.") #t)

    (gnc:options-add-currency!
     options pagename-currency optname-currency "c")

    (gnc:options-add-price-source!
     options pagename-currency optname-price-source "d" 'pricedb-nearest)

    ;; Display / project-tag specific options

    (gnc-register-string-option options
      pagename-display optname-project-tag-prefix
      "a1" (G_ "Prefix that identifies project tags (e.g. #P-).")
      def:project-tag-prefix)

    (gnc-register-simple-boolean-option options
      pagename-display optname-strip-prefix
      "a2" (G_ "Strip the project tag prefix from the displayed project name.")
      #t)

    options))

;; Renderer

(define (ptb:renderer report-obj)
  (define options (gnc:report-options report-obj))
  (define (opt-val section name)
    (gnc-optiondb-lookup-value (gnc:optiondb options) section name))

  (gnc:report-starting (opt-val gnc:pagename-general gnc:optname-reportname))

  (let* ((document (gnc:make-html-document))
         (accounts (opt-val gnc:pagename-accounts optname-accounts))
         (begindate (gnc:time64-start-day-time
                     (gnc:date-option-absolute-time
                      (opt-val gnc:pagename-general optname-startdate))))
         (enddate (gnc:time64-end-day-time
                   (gnc:date-option-absolute-time
                    (opt-val gnc:pagename-general optname-enddate))))
         (date-source (opt-val gnc:pagename-general optname-date-source))
         (infobox-display (opt-val gnc:pagename-general optname-infobox-display))
         (report-title (opt-val gnc:pagename-general gnc:optname-reportname))
         (project-tag-prefix-raw (opt-val pagename-display optname-project-tag-prefix))
         (project-tag-prefix
          (let ((trimmed (string-trim project-tag-prefix-raw)))
            (if (string-null? trimmed) def:project-tag-prefix trimmed)))
         (strip-prefix? (opt-val pagename-display optname-strip-prefix)))

    (cond
     ((null? accounts)
      (gnc:html-document-add-object!
       document
       (gnc:html-make-no-account-warning report-title (gnc:report-id report-obj)))
      (gnc:html-document-set-export-error document "No accounts selected"))
     (else
      ;; Build query and collect splits
      (let* ((query (qof-query-create-for-splits))
             (book (gnc-get-current-book)))

        (qof-query-set-book query book)
        (xaccQueryAddAccountMatch query accounts QOF-GUID-MATCH-ANY QOF-QUERY-AND)

        ;; Date filter: only support posted and entered here, like the transaction report
        (case date-source
          ((posted)
           (xaccQueryAddDateMatchTT query #t begindate #t enddate QOF-QUERY-AND))
          ((entered)
           (xaccQueryAddDateEnteredMatchTT query #t begindate #t enddate QOF-QUERY-AND))
          ((reconciled)
           (xaccQueryAddReconcileDateMatchTT query #t begindate #t enddate QOF-QUERY-AND))
          (else
           (xaccQueryAddDateMatchTT query #t begindate #t enddate QOF-QUERY-AND)))

        (let* ((splits (qof-query-run query))
               (untagged-income ptb:zero)
               (untagged-expense ptb:zero)
               (untagged-realloc-income ptb:zero)
               (untagged-realloc-expense ptb:zero))
          (qof-query-destroy query)

          ;; Filter splits to income/expense accounts and with project tags.
          ;; Accumulate per-project income, expense and reallocations separately.
          (let loop ((remaining splits)
                     (project->amount '()))    ; (project . (income expense realloc-income realloc-expense))
            (if (null? remaining)
                ;; done
                (if (null? project->amount)
                    (begin
                      (gnc:html-document-add-object!
                       document
                       (gnc:html-make-generic-warning
                        report-title (gnc:report-id report-obj)
                        (G_ "No matching project-tagged splits found")
                        ""))
                      (gnc:html-document-set-export-error document "No project-tagged splits found"))
                    (let* ((sorted-projects
                            (sort project->amount
                                  (lambda (a b)
                                    (string<? (car a) (car b)))))
                           (table (gnc:make-html-table))
                           (grand-income (gnc-numeric-zero))
                           (grand-expense (gnc-numeric-zero))
                           (grand-realloc-income (gnc-numeric-zero))
                           (grand-realloc-expense (gnc-numeric-zero)))
                      ;; Title and date range
                      (gnc:html-document-set-title! document report-title)

                      (gnc:html-document-add-object!
                       document
                       (gnc:make-html-text
                        (gnc:html-markup-h3
                         (format #f
                                 (G_ "From ~a to ~a")
                                 (qof-print-date begindate)
                                 (qof-print-date enddate)))))

                      (when (eq? infobox-display 'always)
                        (gnc:html-document-add-object!
                         document
                         (gnc:html-render-options-changed options)))

                      ;; Table header
                      (gnc:html-table-append-row!
                       table
                       (list
                        (ptb:header-cell (G_ "Project"))
                        (ptb:header-cell (G_ "Income"))
                        (ptb:header-cell (G_ "Expenses"))
                        (ptb:header-cell (G_ "Reallocations In"))
                        (ptb:header-cell (G_ "Reallocations Out"))
                        (ptb:header-cell (G_ "Balance"))))

                      ;; Rows
                      (for-each
                       (lambda (entry)
                         (let* ((raw-name (car entry))
                                (totals (cdr entry))
                                (income (ptb:totals-income totals))
                                (expense (ptb:totals-expense totals))
                                (realloc-income (ptb:totals-realloc-income totals))
                                (realloc-expense (ptb:totals-realloc-expense totals))
                                (balance (ptb:n- (ptb:n+ income realloc-income)
                                                 (ptb:n+ expense realloc-expense)))
                                (display-name
                                 (if (and strip-prefix?
                                          (string-prefix? project-tag-prefix raw-name))
                                     (substring raw-name (string-length project-tag-prefix))
                                     raw-name))
                                (commodity (xaccAccountGetCommodity
                                            (xaccSplitGetAccount (car splits))))
                                (income-mon (gnc:make-gnc-monetary commodity income))
                                (expense-mon (gnc:make-gnc-monetary commodity expense))
                                (realloc-income-mon (gnc:make-gnc-monetary commodity realloc-income))
                                (realloc-expense-mon (gnc:make-gnc-monetary commodity realloc-expense))
                                (balance-mon (gnc:make-gnc-monetary commodity balance)))
                           (set! grand-income (ptb:n+ grand-income income))
                           (set! grand-expense (ptb:n+ grand-expense expense))
                           (set! grand-realloc-income (ptb:n+ grand-realloc-income realloc-income))
                           (set! grand-realloc-expense (ptb:n+ grand-realloc-expense realloc-expense))
                           (gnc:html-table-append-row!
                            table
                            (list
                             (ptb:text-cell display-name)
                             (ptb:number-cell income-mon)
                             (ptb:number-cell expense-mon)
                             (ptb:number-cell realloc-income-mon)
                             (ptb:number-cell realloc-expense-mon)
                             (ptb:number-cell balance-mon)))))
                       sorted-projects)

                      ;; Total row for income/expenses with project tag
                      (let* ((commodity (xaccAccountGetCommodity
                                         (xaccSplitGetAccount (car splits))))
                             (grand-balance (ptb:n- (ptb:n+ grand-income grand-realloc-income)
                                                    (ptb:n+ grand-expense grand-realloc-expense)))
                             (grand-income-mon (gnc:make-gnc-monetary commodity grand-income))
                             (grand-expense-mon (gnc:make-gnc-monetary commodity grand-expense))
                             (grand-realloc-income-mon (gnc:make-gnc-monetary commodity grand-realloc-income))
                             (grand-realloc-expense-mon (gnc:make-gnc-monetary commodity grand-realloc-expense))
                             (grand-balance-mon (gnc:make-gnc-monetary commodity grand-balance)))
                        (gnc:html-table-append-row/markup!
                         table "grand-total"
                         (list
                          (ptb:total-label-cell (G_ "Total"))
                          (ptb:total-number-cell grand-income-mon)
                          (ptb:total-number-cell grand-expense-mon)
                          (ptb:total-number-cell grand-realloc-income-mon)
                          (ptb:total-number-cell grand-realloc-expense-mon)
                          (ptb:total-number-cell grand-balance-mon))))

                          ;; Row for income/expenses without project tag
                          (let* ((commodity (xaccAccountGetCommodity
                                             (xaccSplitGetAccount (car splits))))
                                 (untagged-balance (ptb:n- (ptb:n+ untagged-income untagged-realloc-income)
                                                           (ptb:n+ untagged-expense untagged-realloc-expense)))
                                 (untagged-income-mon (gnc:make-gnc-monetary commodity untagged-income))
                                 (untagged-expense-mon (gnc:make-gnc-monetary commodity untagged-expense))
                                 (untagged-realloc-income-mon (gnc:make-gnc-monetary commodity untagged-realloc-income))
                                 (untagged-realloc-expense-mon (gnc:make-gnc-monetary commodity untagged-realloc-expense))
                                 (untagged-balance-mon (gnc:make-gnc-monetary commodity untagged-balance)))
                           (gnc:html-table-append-row/markup!
                            table no-project-tag-style
                            (list
                             (ptb:total-label-cell (G_ "No project tag"))
                             (ptb:total-number-cell untagged-income-mon)
                             (ptb:total-number-cell untagged-expense-mon)
                             (ptb:total-number-cell untagged-realloc-income-mon)
                             (ptb:total-number-cell untagged-realloc-expense-mon)
                             (ptb:total-number-cell untagged-balance-mon))))

                      (gnc:html-document-add-object! document table)

                      (when (opt-val gnc:pagename-general optname-table-export)
                        (let ((rows
                               (map (lambda (entry)
                                      (let* ((raw-name (car entry))
                                             (totals (cdr entry))
                                             (income (ptb:totals-income totals))
                                             (expense (ptb:totals-expense totals))
                                             (realloc-income (ptb:totals-realloc-income totals))
                                             (realloc-expense (ptb:totals-realloc-expense totals))
                                             (balance (ptb:n- (ptb:n+ income realloc-income)
                                                              (ptb:n+ expense realloc-expense)))
                                             (commodity (xaccAccountGetCommodity
                                                         (xaccSplitGetAccount (car splits))))
                                             (income-mon (gnc:make-gnc-monetary commodity income))
                                             (expense-mon (gnc:make-gnc-monetary commodity expense))
                                             (realloc-income-mon (gnc:make-gnc-monetary commodity realloc-income))
                                             (realloc-expense-mon (gnc:make-gnc-monetary commodity realloc-expense))
                                             (balance-mon (gnc:make-gnc-monetary commodity balance)))
                                        (list raw-name income-mon expense-mon realloc-income-mon realloc-expense-mon balance-mon)))
                                    sorted-projects)))
                          (gnc:html-document-set-export-string
                           document
                           (gnc:lists->csv
                            (cons '("project" "income" "expenses" "reallocations_in" "reallocations_out" "balance") rows)))))))
                (let* ((split (car remaining)) ; if remaining is not null
                       (rest (cdr remaining))
                       (account (xaccSplitGetAccount split)))
                  (if (ptb:income-or-expense? account)
                      (let* ((tag (ptb:extract-project-tag split project-tag-prefix))
                             (raw-amount (xaccSplitGetAmount split))
                             (type (xaccAccountGetType account))
                             (income-delta ptb:zero)
                             (expense-delta ptb:zero)
                             (realloc-income-delta ptb:zero)
                             (realloc-expense-delta ptb:zero))
                        (cond
                         ((ptb:realloc-income-account? account)
                          (set! realloc-income-delta
                                (if (eq? type ACCT-TYPE-INCOME)
                                    (gnc-numeric-neg raw-amount)
                                    ptb:zero)))
                         ((ptb:realloc-expense-account? account)
                          (set! realloc-expense-delta
                                (if (eq? type ACCT-TYPE-EXPENSE)
                                    raw-amount
                                    ptb:zero)))
                         (else
                          (set! income-delta
                                (if (eq? type ACCT-TYPE-INCOME)
                                    (gnc-numeric-neg raw-amount)
                                    ptb:zero))
                          (set! expense-delta
                                (if (eq? type ACCT-TYPE-EXPENSE)
                                    raw-amount
                                    ptb:zero))))
                        (if tag
                            (let ((updated (alist-inc! project->amount
                                                       tag income-delta expense-delta
                                                       realloc-income-delta realloc-expense-delta)))
                              (loop rest updated))
                            (begin
                              (set! untagged-income (ptb:n+ untagged-income income-delta))
                              (set! untagged-expense (ptb:n+ untagged-expense expense-delta))
                              (set! untagged-realloc-income (ptb:n+ untagged-realloc-income realloc-income-delta))
                              (set! untagged-realloc-expense (ptb:n+ untagged-realloc-expense realloc-expense-delta))
                              (loop rest project->amount))))
                      (loop rest project->amount)))))))))

    (gnc:report-finished)
    document))

;; Register the report

(gnc:define-report
 'version 1
 'name (N_ "Project Balance")
 'report-guid "5beff7158aec4f27b26f7235e6015a8e"
 'menu-path (list gnc:menuname-experimental)
 'options-generator ptb:options-generator
 'renderer ptb:renderer)

