;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; budget-extended.scm: budget report with project (#P-) filter
;;
;; Extended from standard budget.scm (GnuCash).
;; Adds option to filter Actual (and Difference) by project tag
;; in transaction memo, notes, or description.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, contact:
;;
;; Free Software Foundation           Voice:  +1-617-542-5942
;; 51 Franklin Street, Fifth Floor    Fax:    +1-617-542-2652
;; Boston, MA  02110-1301,  USA       gnu@gnu.org
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-module (gnucash report budget-extended))

(use-modules (gnucash engine))
(use-modules (gnucash utilities))
(use-modules (gnucash core-utils))
(use-modules (gnucash app-utils))
(use-modules (gnucash report))
(use-modules (gnucash report report-utilities))

(use-modules (srfi srfi-1))
(use-modules (ice-9 match))
(use-modules (ice-9 regex))

(define trep-uuid "2fe3b9833af044abb929a88d5a59620f")

(define reportname (N_ "Budget Report Extended"))

;; define all option's names so that they are properly defined
;; in *one* place.

(define optname-display-depth
  (N_ "Account Display Depth"))
(define optname-show-subaccounts (N_ "Always show sub-accounts"))
(define optname-accounts (N_ "Account"))

(define optname-show-budget (N_ "Show Budget"))
(define opthelp-show-budget (N_ "Display a column for the budget values."))
(define optname-show-notes (N_ "Show Budget Notes"))
(define opthelp-show-notes (N_ "Display a column for the budget notes."))
(define optname-show-actual (N_ "Show Actual"))
(define opthelp-show-actual (N_ "Display a column for the actual values."))
(define optname-show-trep (N_ "Link to actual transactions"))
(define opthelp-show-trep (N_ "Show the actual transactions for the budget period"))
(define optname-show-difference (N_ "Show Difference"))
(define opthelp-show-difference (N_ "Display the difference as budget - actual."))
(define optname-accumulate (N_ "Use accumulated amounts"))
(define opthelp-accumulate (N_ "Values are accumulated across periods."))
(define optname-show-totalcol (N_ "Show Column with Totals"))
(define opthelp-show-totalcol (N_ "Display a column with the row totals."))
(define optname-show-zb-accounts (N_ "Include accounts with zero total balances and budget values"))
(define opthelp-show-zb-accounts (N_ "Include accounts with zero total (recursive) balances and budget values in this report."))


(define optname-use-budget-period-range
  (N_ "Report for range of budget periods"))
(define opthelp-use-budget-period-range
  (N_ "Create report for a budget period range instead of the entire budget."))

(define optname-budget-period-start (N_ "Range start"))
(define opthelp-budget-period-start
  (N_ "Select a budget period type that starts the reporting range."))
(define optname-budget-period-start-exact (N_ "Exact start period"))
(define opthelp-budget-period-start-exact
  (N_ "Select exact period that starts the reporting range."))

(define optname-budget-period-end (N_ "Range end"))
(define opthelp-budget-period-end
  (N_ "Select a budget period type that ends the reporting range."))
(define optname-budget-period-end-exact (N_ "Exact end period"))
(define opthelp-budget-period-end-exact
  (N_ "Select exact period that ends the reporting range."))

(define optname-period-collapse-before (N_ "Include collapsed periods before selected."))
(define opthelp-period-collapse-before (N_ "Include in report previous periods as single collapsed column (one for all periods before starting)"))
(define optname-period-collapse-after (N_ "Include collapsed periods after selected."))
(define opthelp-period-collapse-after (N_ "Include in report further periods as single collapsed column (one for all periods after ending and to the end of budget range)"))

(define optname-bottom-behavior (N_ "Flatten list to depth limit"))
(define opthelp-bottom-behavior
  (N_ "Displays accounts which exceed the depth limit at the depth limit."))

(define optname-budget (N_ "Budget"))

;; Project filter: only Actual (and Difference) are filtered by this tag.
(define optname-project-filter (N_ "Project filter"))
(define opthelp-project-filter
  (N_ "Filter Actual and Difference by transactions whose memo, notes, or description contain this string (e.g. #P-2025Aug). Leave blank to show all transactions."))
(define optname-project-filter-regex (N_ "Use regular expression for project filter"))
(define optname-project-filter-caseinsensitive (N_ "Project filter is case insensitive"))

;;List of common helper functions, that is not bound only to options generation or report evaluation
(define (get-option-val options pagename optname)
  (gnc-optiondb-lookup-value options pagename optname))

(define (set-option-enabled options page opt-name enabled)
  (gnc-optiondb-set-option-selectable-by-name
   options page opt-name enabled))

;; options generator
(define (budget-report-options-generator)
  (let* ((options (gnc-new-optiondb))
         (period-options
          (list (vector 'first (N_ "First budget period"))
                (vector 'previous (N_ "Previous budget period"))
                (vector 'current (N_ "Current budget period"))
                (vector 'next (N_ "Next budget period"))
                (vector 'last (N_ "Last budget period"))
                (vector 'manual (N_ "Manual period selection"))))
         (ui-use-periods #f)
         (ui-start-period-type 'current)
         (ui-end-period-type 'next))

    (gnc-register-budget-option options
      gnc:pagename-general optname-budget
      "a" (N_ "Budget to use.")
      (gnc-budget-get-default (gnc-get-current-book)))

    (gnc-register-simple-boolean-option options
      gnc:pagename-general optname-accumulate
      "b" opthelp-accumulate #f)

    (gnc-register-complex-boolean-option options
      gnc:pagename-general optname-use-budget-period-range
      "f" opthelp-use-budget-period-range #f
      (lambda (value)
        (for-each
         (lambda (opt)
           (set-option-enabled options gnc:pagename-general opt value))
         (list optname-budget-period-start optname-budget-period-end
               optname-period-collapse-before optname-period-collapse-after))

        (set-option-enabled options gnc:pagename-general
                            optname-budget-period-start-exact
                            (and value (eq? 'manual ui-start-period-type)))

        (set-option-enabled options gnc:pagename-general
                            optname-budget-period-end-exact
                            (and value (eq? 'manual ui-end-period-type)))

        (set! ui-use-periods value)))

    (gnc-register-multichoice-callback-option options
      gnc:pagename-general optname-budget-period-start
      "g1.1" opthelp-budget-period-start "current" period-options
      (lambda (new-val)
        (set-option-enabled options gnc:pagename-general
                            optname-budget-period-start-exact
                            (and ui-use-periods (eq? 'manual new-val)))
        (set! ui-start-period-type new-val)))

    (gnc-register-number-range-option options
      gnc:pagename-general optname-budget-period-start-exact
      "g1.2" opthelp-budget-period-start-exact
      1 1 60 1)

    (gnc-register-multichoice-callback-option options
      gnc:pagename-general optname-budget-period-end
      "g2.1" opthelp-budget-period-end "next" period-options
      (lambda (new-val)
        (set-option-enabled options gnc:pagename-general
                            optname-budget-period-end-exact
                            (and ui-use-periods (eq? 'manual new-val)))
        (set! ui-end-period-type new-val)))

    (gnc-register-number-range-option options
      gnc:pagename-general optname-budget-period-end-exact
      "g2.2" opthelp-budget-period-end-exact
      1 1 60 1)

    (gnc-register-simple-boolean-option options
      gnc:pagename-general optname-period-collapse-before
      "g3" opthelp-period-collapse-before #t)

    (gnc-register-simple-boolean-option options
      gnc:pagename-general optname-period-collapse-after
      "g4" opthelp-period-collapse-after #t)

    ;; Project filter (Actual column only)
    (gnc-register-string-option options
      gnc:pagename-general optname-project-filter
      "g5" opthelp-project-filter "")

    (gnc-register-simple-boolean-option options
      gnc:pagename-general optname-project-filter-regex
      "g6" (N_ "Use full regular expression for project filter.") #f)

    (gnc-register-simple-boolean-option options
      gnc:pagename-general optname-project-filter-caseinsensitive
      "g7" (N_ "Project filter matching is case insensitive.") #f)

    (gnc:options-add-account-selection!
     options gnc:pagename-accounts optname-display-depth
     optname-show-subaccounts optname-accounts "a" 2
     (lambda ()
       (gnc:filter-accountlist-type
        (list ACCT-TYPE-ASSET ACCT-TYPE-LIABILITY ACCT-TYPE-INCOME
              ACCT-TYPE-EXPENSE)
        (gnc-account-get-descendants-sorted (gnc-get-current-root-account))))
     #f)

    (gnc-register-simple-boolean-option options
      gnc:pagename-accounts optname-bottom-behavior
      "c" opthelp-bottom-behavior #f)

    ;; columns to display
    (gnc-register-complex-boolean-option options
      gnc:pagename-display optname-show-budget
      "s1" opthelp-show-budget #t
      (lambda (x)
        (set-option-enabled options gnc:pagename-display optname-show-notes x)))
    (gnc-register-simple-boolean-option options
      gnc:pagename-display optname-show-notes
      "s15" opthelp-show-notes #t)
    (gnc-register-complex-boolean-option options
      gnc:pagename-display optname-show-actual
      "s2" opthelp-show-actual #t
      (lambda (x)
        (gnc-optiondb-set-option-selectable-by-name
         options gnc:pagename-display optname-show-trep x)))
    (gnc-register-simple-boolean-option options
      gnc:pagename-display optname-show-trep
      "s25" opthelp-show-trep #f)
    (gnc-register-simple-boolean-option options
      gnc:pagename-display optname-show-difference
      "s3" opthelp-show-difference #f)
    (gnc-register-simple-boolean-option options
      gnc:pagename-display optname-show-totalcol
      "s4" opthelp-show-totalcol #f)
    (gnc-register-simple-boolean-option options
      gnc:pagename-display optname-show-zb-accounts
      "s5" opthelp-show-zb-accounts #t)

    ;; Set the general page as default option tab
    (gnc:options-set-default-section options gnc:pagename-general)

    options))

;; creates a footnotes collector. (make-footnote-collector) => coll
;; (coll elt) if elt is not null or "", adds elt to store, returns
;; html-text containing ref eg. <sup title='note'>1</sup>. calling
;; (coll 'list) returns html-text containing <ol> of all stored elts
(define (make-footnote-collector)
  (let ((notes '()) (num 0))
    (match-lambda
      ('list
       (let lp ((notes notes) (res '()))
         (match notes
           (() (gnc:make-html-text (gnc:html-markup-ol res)))
           ((note . rest) (lp rest (cons note res))))))
      ((or #f "") "")
      (note
       (set! notes (cons (gnc:html-string-sanitize note) notes))
       (set! num (1+ num))
       (let ((text (gnc:make-html-text
                    " " (gnc:html-markup "sup" (number->string num)))))
         (gnc:html-text-set-style! text "sup" 'attribute `("title" ,note))
         text)))))

;; Get actual value for one account and one period, filtered by project tag.
;; Matches memo, notes, or description (same as transaction-extended).
(define (get-account-period-actual-value-filtered budget acct period project-filter params)
  (let* ((get-val (lambda (alist key)
                    (let ((lst (assoc-ref alist key)))
                      (and lst (car lst)))))
         (start-date (gnc-budget-get-period-start-date budget period))
         (end-date (gnc-budget-get-period-end-date budget period))
         (query (qof-query-create-for-splits)))
    (qof-query-set-book query (gnc-get-current-book))
    (xaccQueryAddAccountMatch
      query
      (gnc-accounts-and-all-descendants (list acct))
      QOF-GUID-MATCH-ANY
      QOF-QUERY-AND
    )
    (xaccQueryAddDateMatchTT query #t start-date #t end-date QOF-QUERY-AND)
    (xaccQueryAddClearedMatch query
                              (logand CLEARED-ALL (lognot CLEARED-VOIDED))
                              QOF-QUERY-AND)
    (let* ((splits (qof-query-run query)))
      (qof-query-destroy query)
      (if (null? splits)
          0
          (let* ((use-regexp (get-val params 'project-filter-regexp))
                 (case-insensitive? (get-val params 'project-filter-case-insensitive))
                 (match? (lambda (str)
                           (cond
                            (use-regexp
                             (and (regexp-exec use-regexp str)))
                            (case-insensitive?
                             (string-contains-ci str project-filter))
                            (else
                             (string-contains str project-filter)))))
                 (transaction-filter-match (lambda (split)
                                             (or (match? (or (xaccTransGetDescription (xaccSplitGetParent split)) ""))
                                                 (match? (or (xaccTransGetNotes (xaccSplitGetParent split)) ""))
                                                 (match? (or (xaccSplitGetMemo split) "")))))
                 (filtered (filter transaction-filter-match splits))
                 (comm (xaccAccountGetCommodity acct))
                 (value-collector (gnc:make-commodity-collector)))
            (for-each
             (lambda (split)
               (value-collector 'add
                               (xaccTransGetCurrency (xaccSplitGetParent split))
                               (xaccSplitGetValue split)))
             filtered)
            (let ((pair (value-collector 'getpair comm #f)))
              (if (and pair (list? pair) (>= (length pair) 2))
                  (cadr pair)
                  0)))))))

;; Create the html table for the budget report
;;
;; Parameters
;;   html-table - HTML table to fill in
;;   acct-table - Table of accounts to use
;;   budget - budget to use
;;   params - report parameters
(define (gnc:html-table-add-budget-values!
         html-table acct-table budget params report-obj)
  (let* ((get-val (lambda (alist key)
                    (let ((lst (assoc-ref alist key)))
                      (and lst (car lst)))))
         (show-actual? (get-val params 'show-actual))
         (show-trep? (get-val params 'show-trep))
         (show-budget? (get-val params 'show-budget))
         (show-diff? (get-val params 'show-difference))
         (show-note? (get-val params 'show-note))
         (footnotes (get-val params 'footnotes))
         (accumulate? (get-val params 'use-envelope))
         (show-totalcol? (get-val params 'show-totalcol))
         (use-ranges? (get-val params 'use-ranges))
         (project-filter (string-trim-both (or (get-val params 'project-filter) "")))
         (num-rows (gnc:html-acct-table-num-rows acct-table))
         (numcolumns (gnc:html-table-num-columns html-table))
         (colnum (quotient numcolumns 2)))

    ;; Calculate the value to use for the budget of an account for a
    ;; specific set of periods.
    (define (gnc:get-account-periodlist-budget-value budget acct periodlist)
      (apply +
             (map
              (lambda (period)
                (gnc:get-account-period-rolledup-budget-value budget acct period))
              periodlist)))

    ;; Calculate the value to use for the actual of an account for a
    ;; specific set of periods. When project-filter is set, use
    ;; query + filter by memo/notes/description; otherwise use engine.
    (define (gnc:get-account-periodlist-actual-value budget acct periodlist)
      (if (string-null? project-filter)
          (apply + (map
                    (lambda (period)
                      (gnc-budget-get-account-period-actual-value budget acct period))
                    periodlist))
          (apply + (map
                    (lambda (period)
                      (get-account-period-actual-value-filtered
                       budget acct period project-filter params))
                    periodlist))))

    ;; Adds a line to the budget report.
    (define (gnc:html-table-add-budget-line!
             html-table rownum colnum budget acct
             column-list exchange-fn)
      (let* ((comm (xaccAccountGetCommodity acct))
             (reverse-balance? (gnc-reverse-balance acct))
             (maybe-negate (lambda (amt) (if reverse-balance? (- amt) amt)))
             (allperiods (filter number? (gnc:list-flatten column-list)))
             (total-periods (if (and accumulate? (not (null? allperiods)))
                                (iota (1+ (apply max allperiods)))
                                allperiods))
             (income-acct? (eqv? (xaccAccountGetType acct) ACCT-TYPE-INCOME)))

        (define (disp-cols style-tag col0 acct start-date end-date
                           bgt-val act-val dif-val note)
          (let* ((col1 (+ col0 (if show-budget? 1 0)))
                 (col2 (+ col1 (if show-actual? 1 0)))
                 (col3 (+ col2 (if show-diff? 1 0)))
                 (trep-opts (append
                             (list
                              (list "General" "Start Date" (cons 'absolute start-date))
                              (list "General" "End Date" (cons 'absolute end-date))
                              (list "Accounts" "Accounts" (gnc-accounts-and-all-descendants (list acct)))
                              (list "Currency" "Common Currency" #t)
                              (list "Currency" "Report's currency" (gnc-account-get-currency-or-parent acct)))
                             (if (and show-trep? (not (string-null? project-filter)))
                                 (list (list "Filter" "Transaction Filter" project-filter))
                                 '()))))
            (if show-budget?
                (gnc:html-table-set-cell/tag!
                 html-table rownum col0 style-tag
                 (if (zero? bgt-val) "."
                     (gnc:make-gnc-monetary comm bgt-val))
                 (if show-note? (footnotes note) "")))
            (if show-actual?
                (gnc:html-table-set-cell/tag!
                 html-table rownum col1
                 style-tag
                 (if show-trep?
                     (gnc:make-html-text
                      (gnc:html-markup-anchor
                       (gnc:make-report-anchor trep-uuid report-obj trep-opts)
                       (gnc:make-gnc-monetary comm act-val)))
                     (gnc:make-gnc-monetary comm act-val))))
            (if show-diff?
                (gnc:html-table-set-cell/tag!
                 html-table rownum col2
                 style-tag
                 (if (and (zero? bgt-val) (zero? act-val)) "."
                     (gnc:make-gnc-monetary comm dif-val))))
            col3))

        (let loop ((column-list column-list)
                   (current-col (1+ colnum)))
          (cond

           ((null? column-list)
            #f)

           ((eq? (car column-list) 'total)
            (let* ((bgt-total (maybe-negate
                               (gnc:get-account-periodlist-budget-value
                                budget acct total-periods)))
                   (act-total (maybe-negate
                               (gnc:get-account-periodlist-actual-value
                                budget acct total-periods)))
                   (dif-total (- bgt-total act-total)))
              (loop (cdr column-list)
                    (disp-cols "total-number-cell" current-col acct
                               (gnc-budget-get-period-start-date budget (car total-periods))
                               (gnc-budget-get-period-end-date budget (last total-periods))
                               bgt-total act-total dif-total #f))))

           (else
            (let* ((period-list (cond
                                 ((list? (car column-list)) (car column-list))
                                 (accumulate? (iota (1+ (car column-list))))
                                 (else (list (car column-list)))))
                   (note (and (= 1 (length period-list))
                              (gnc-budget-get-account-period-note
                               budget acct (car period-list))))
                   (bgt-val (maybe-negate
                             (gnc:get-account-periodlist-budget-value
                              budget acct period-list)))
                   (act-val (maybe-negate
                             (gnc:get-account-periodlist-actual-value
                              budget acct period-list)))
                   (dif-val (- bgt-val act-val)))
              (loop (cdr column-list)
                    (disp-cols "number-cell" current-col acct
                               (gnc-budget-get-period-start-date budget (car period-list))
                               (gnc-budget-get-period-end-date budget (car period-list))
                               bgt-val act-val dif-val note))))))))

    ;; Adds header rows to the budget report.
    (define (gnc:html-table-add-budget-headers!
             html-table colnum budget column-list)
      (let* ((current-col (1+ colnum))
             (col-span (max 1 (count identity
                                    (list show-budget? show-actual? show-diff?))))
             (period-to-date-string (lambda (p)
                                      (qof-print-date
                                       (gnc-budget-get-period-start-date budget p)))))

        (gnc:html-table-prepend-row! html-table '())
        (gnc:html-table-prepend-row! html-table '())

        (let loop ((column-list column-list)
                   (current-col current-col))
          (unless (null? column-list)
            (gnc:html-table-set-cell!
             html-table 0 current-col
             (cond
              ((eq? (car column-list) 'total)
               (G_ "Total"))
              ((list? (car column-list))
               (format #f (G_ "~a to ~a")
                       (period-to-date-string (car (car column-list)))
                       (period-to-date-string (last (car column-list)))))
              (else
               (period-to-date-string (car column-list)))))

            (let ((tc (gnc:html-table-get-cell html-table 0 current-col)))
              (gnc:html-table-cell-set-colspan! tc col-span)
              (gnc:html-table-cell-set-tag! tc "centered-label-cell"))

            (loop (cdr column-list)
                  (1+ current-col))))

        (let loop ((column-list column-list)
                   (col0 current-col))
          (unless (null? column-list)
            (let* ((col1 (+ col0 (if show-budget? 1 0)))
                   (col2 (+ col1 (if show-actual? 1 0)))
                   (col3 (+ col2 (if show-diff? 1 0))))
              (when show-budget?
                (gnc:html-table-set-cell/tag!
                 html-table 1 col0 "centered-label-cell"
                 (G_ "Bgt")))
              (when show-actual?
                (gnc:html-table-set-cell/tag!
                 html-table 1 col1 "centered-label-cell"
                 (G_ "Act")))
              (when show-diff?
                (gnc:html-table-set-cell/tag!
                 html-table 1 col2 "centered-label-cell"
                 (G_ "Diff")))
              (loop (cdr column-list)
                    col3))))))

    ;; Period calculation helpers (unchanged from standard budget)
    (define (find-period-relative-to-current budget adjuster)
      (let* ((now (current-time))
             (total-periods (gnc-budget-get-num-periods budget))
             (last-period (1- total-periods))
             (period-start (lambda (x) (gnc-budget-get-period-start-date budget x)))
             (period-end (lambda (x) (gnc-budget-get-period-end-date budget x))))
        (cond ((< now (period-start 0)) 1)
              ((> now (period-end last-period)) total-periods)
              (else (let ((found-period
                           (find (lambda (period)
                                   (<= (period-start period)
                                       now
                                       (period-end period)))
                                 (iota total-periods))))
                      (and found-period
                           (max 0 (min last-period (adjuster found-period)))))))))

    (define (calc-user-period budget use-ranges? period-type period-exact-val)
      (and use-ranges?
           (case period-type
            ((first)    0)
            ((last)     (1- (gnc-budget-get-num-periods budget)))
            ((manual)   (1- period-exact-val))
            ((previous) (find-period-relative-to-current budget 1-))
            ((current)  (find-period-relative-to-current budget identity))
            ((next)     (find-period-relative-to-current budget 1+)))))

    (define (calc-periods
             budget user-start user-end collapse-before? collapse-after? show-total?)
      (define (range start end)
        (if (< start end)
            (iota (- end start) start)
            (iota (- start end) end)))
      (let* ((num-periods (gnc-budget-get-num-periods budget))
             (range-start (or user-start 0))
             (range-end (if user-end (1+ user-end) num-periods))
             (fold-before-start 0)
             (fold-before-end (if collapse-before? range-start 0))
             (fold-after-start (if collapse-after? range-end num-periods))
             (fold-after-end num-periods))
        (map (lambda (x) (if (and (list? x) (null? (cdr x))) (car x) x))
             (filter (lambda (x) (not (null? x)))
                     (append (list (range fold-before-start fold-before-end))
                             (range range-start range-end)
                             (list (range fold-after-start fold-after-end))
                             (if show-total? '(total) '()))))))

    (let ((column-info-list (calc-periods
                             budget
                             (calc-user-period
                              budget use-ranges?
                              (get-val params 'user-start-period)
                              (get-val params 'user-start-period-exact))
                             (calc-user-period
                              budget use-ranges?
                              (get-val params 'user-end-period)
                              (get-val params 'user-end-period-exact))
                             (get-val params 'collapse-before)
                             (get-val params 'collapse-after)
                             show-totalcol?)))
      (gnc:debug "use-ranges? =" use-ranges?)
      (gnc:debug "user-start-period =" (get-val params 'user-start-period))
      (gnc:debug "user-start-period-exact =" (get-val params 'user-start-period-exact))
      (gnc:debug "user-end-period =" (get-val params 'user-end-period))
      (gnc:debug "user-end-period-exact =" (get-val params 'user-end-period-exact))
      (gnc:debug "column-info-list=" column-info-list)

      (let loop ((rownum 0))
        (when (< rownum num-rows)
          (let* ((env (append (gnc:html-acct-table-get-row-env acct-table rownum)
                              params))
                 (acct (get-val env 'account))
                 (exchange-fn (get-val env 'exchange-fn)))
            (gnc:html-table-add-budget-line!
             html-table rownum colnum budget acct
             column-info-list exchange-fn)
            (loop (1+ rownum)))))

      (gnc:html-table-add-budget-headers!
       html-table colnum budget column-info-list))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; budget-renderer
;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (budget-renderer report-obj)
  (define (get-option pagename optname)
    (get-option-val (gnc:report-options report-obj) pagename optname))

  (gnc:report-starting reportname)

  (let* ((budget (get-option gnc:pagename-general optname-budget))
         (budget-valid? (and budget (not (null? budget))))
         (display-depth (get-option gnc:pagename-accounts
                                    optname-display-depth))
         (show-subaccts? (get-option gnc:pagename-accounts
                                     optname-show-subaccounts))
         (accounts (get-option gnc:pagename-accounts
                               optname-accounts))
         (bottom-behavior (get-option gnc:pagename-accounts optname-bottom-behavior))
         (show-zb-accts? (get-option gnc:pagename-display
                                     optname-show-zb-accounts))
         (use-ranges? (get-option gnc:pagename-general optname-use-budget-period-range))
         (include-collapse-before? (and use-ranges?
                                        (get-option gnc:pagename-general
                                                    optname-period-collapse-before)))
         (include-collapse-after? (and use-ranges?
                                       (get-option gnc:pagename-general
                                                   optname-period-collapse-after)))
         (doc (gnc:make-html-document))
         (accounts (if show-subaccts?
                       (gnc-accounts-and-all-descendants accounts)
                       accounts))
         (project-filter-str (get-option gnc:pagename-general optname-project-filter))
         (project-filter-regexp
          (and (get-option gnc:pagename-general optname-project-filter-regex)
               (not (string-null? (string-trim-both project-filter-str)))
               (catch 'regular-expression-syntax
                 (lambda ()
                   (if (get-option gnc:pagename-general optname-project-filter-caseinsensitive)
                       (make-regexp project-filter-str regexp/icase)
                       (make-regexp project-filter-str)))
                 (const #f)))))

    (cond

     ((null? accounts)
      (gnc:html-document-add-object!
       doc (gnc:html-make-no-account-warning reportname (gnc:report-id report-obj))))

     ((not budget-valid?)
      (gnc:html-document-add-object!
       doc (gnc:html-make-generic-budget-warning reportname)))

     (else
      (let* ((tree-depth (if (eq? display-depth 'all)
                             (gnc:accounts-get-children-depth accounts)
                             display-depth))
             (to-period-val (lambda (v)
                              (inexact->exact
                               (truncate
                                (get-option gnc:pagename-general v)))))
             (env (list
                   (list 'start-date (gnc:budget-get-start-date budget))
                   (list 'end-date (gnc:budget-get-end-date budget))
                   (list 'display-tree-depth tree-depth)
                   (list 'depth-limit-behavior
                         (if bottom-behavior 'flatten 'summarize))
                   (list 'zero-balance-mode
                         (if show-zb-accts? 'show-leaf-acct 'omit-leaf-acct))
                   (list 'report-budget budget)))
             (accounts (sort accounts gnc:account-full-name<?))
             (accumulate? (get-option gnc:pagename-general optname-accumulate))
             (acct-table (gnc:make-html-acct-table/env/accts env accounts))
             (footnotes (make-footnote-collector))
             (paramsBudget
              (list
               (list 'show-actual
                     (get-option gnc:pagename-display optname-show-actual))
               (list 'show-trep
                     (get-option gnc:pagename-display optname-show-trep))
               (list 'show-budget
                     (get-option gnc:pagename-display optname-show-budget))
               (list 'show-difference
                     (get-option gnc:pagename-display optname-show-difference))
               (list 'show-note
                     (and (get-option gnc:pagename-display optname-show-budget)
                          (get-option gnc:pagename-display optname-show-notes)))
               (list 'footnotes footnotes)
               (list 'use-envelope accumulate?)
               (list 'show-totalcol
                     (get-option gnc:pagename-display optname-show-totalcol))
               (list 'use-ranges use-ranges?)
               (list 'collapse-before include-collapse-before?)
               (list 'collapse-after include-collapse-after?)
               (list 'user-start-period
                     (get-option gnc:pagename-general
                                 optname-budget-period-start))
               (list 'user-end-period
                     (get-option gnc:pagename-general
                                 optname-budget-period-end))
               (list 'user-start-period-exact
                     (to-period-val optname-budget-period-start-exact))
               (list 'user-end-period-exact
                     (to-period-val optname-budget-period-end-exact))
               (list 'project-filter project-filter-str)
               (list 'project-filter-regexp project-filter-regexp)
               (list 'project-filter-case-insensitive
                     (get-option gnc:pagename-general optname-project-filter-caseinsensitive))))
             (report-name (get-option gnc:pagename-general
                                      gnc:optname-reportname)))

        (gnc:html-document-set-title!
         doc (format #f "~a: ~a ~a"
                     report-name (gnc-budget-get-name budget)
                     (if accumulate? (G_ "using accumulated amounts")
                         "")))

        (let ((html-table (gnc:html-table-add-account-balances #f acct-table '())))

          (gnc:html-table-add-budget-values! html-table acct-table budget
                                             paramsBudget report-obj)

          (gnc:html-table-set-style!
           html-table "td"
           'attribute '("valign" "bottom"))

          (gnc:html-document-add-object! doc html-table)

          (gnc:html-document-add-object! doc (footnotes 'list))))))

    (gnc:report-finished)
    doc))

(gnc:define-report
 'version 1.1
 'name reportname
 'report-guid "301c0c4b5dde4f1a9a947959824983ed"
 'menu-path (list gnc:menuname-budget)
 'options-generator budget-report-options-generator
 'renderer budget-renderer)
