;; Yearly income and expenses grouped by one classification tag per split.
;; SPDX-License-Identifier: GPL-2.0-or-later

(define-module (gnucash reports cc-yearly-summary))
(use-modules (gnucash engine)
             (gnucash utilities)
             (gnucash core-utils)
             (gnucash app-utils)
             (gnucash report)
             (srfi srfi-1)
             (srfi srfi-13)
             (ice-9 format))

(define report-guid "0dff30716cee4e9b8f7a6e934404d131")
(define report-name (N_ "CC Yearly Summary"))
(define opt-start (N_ "Start Date"))
(define opt-end (N_ "End Date"))
(define opt-accounts (N_ "Accounts"))
(define opt-currency (N_ "Report's currency"))
(define opt-prices (N_ "Price Source"))
(define dimensions
  (list (list (N_ "Regular") #f)
        (list (N_ "Irregular") "#I-")
        (list (N_ "Travels") "#T-")
        (list (N_ "Projects") "#P-")))

(define (classification-tag? token)
  (any (lambda (dimension)
         (and (cadr dimension) (string-prefix? (cadr dimension) token)))
       dimensions))

;; Inspect every field, not just the first match. Identical tags repeated in
;; multiple fields are harmless. Sibling split memos are deliberately excluded.
(define (split-tags split)
  (let ((trans (xaccSplitGetParent split)))
    (delete-duplicates
     (append-map (lambda (text)
                   (filter classification-tag? (string-tokenize (or text ""))))
                 (list (xaccTransGetDescription trans)
                       (xaccTransGetNotes trans)
                       (xaccSplitGetMemo split)))
     string=?)))

(define (eligible-split? split)
  (and (memv (xaccAccountGetType (xaccSplitGetAccount split))
             (list ACCT-TYPE-INCOME ACCT-TYPE-EXPENSE))
       (not (xaccTransGetIsClosingTxn (xaccSplitGetParent split)))
       (not (char=? (xaccSplitGetReconcile split) #\v))))

(define (query-splits book accounts start end)
  (let ((query (qof-query-create-for-splits)))
    (dynamic-wind
      (lambda ()
        (qof-query-set-book query book)
        (xaccQueryAddAccountMatch query accounts QOF-GUID-MATCH-ANY QOF-QUERY-AND)
        (xaccQueryAddDateMatchTT query #t start #t end QOF-QUERY-AND))
      (lambda () (qof-query-run query))
      (lambda () (qof-query-destroy query)))))

;; Rows: (kind dimension tag income expenses net-cost monthly-income
;;        monthly-expenses monthly-net-cost). Keep zero and negative totals.
(define (make-row kind dimension tag income expenses)
  (let ((net (- expenses income)))
    (list kind dimension tag income expenses net
          (/ income 12) (/ expenses 12) (/ net 12))))

(define (summary-rows totals)
  (let ((grand-income 0) (grand-expenses 0))
    (define (dimension-rows dimension)
      (let* ((name (car dimension))
             (prefix (cadr dimension))
             (tags (sort
                    (filter (lambda (tag)
                              (if prefix (string-prefix? prefix tag)
                                  (string-null? tag)))
                            (hash-map->list (lambda (tag amounts) tag) totals))
                    string<?))
             (income 0) (expenses 0)
             (rows
              (map (lambda (tag)
                     (let ((amounts (hash-ref totals tag)))
                       (set! income (+ income (car amounts)))
                       (set! expenses (+ expenses (cadr amounts)))
                       (make-row "tag" name tag (car amounts) (cadr amounts))))
                   tags)))
        (set! grand-income (+ grand-income income))
        (set! grand-expenses (+ grand-expenses expenses))
        (append rows (list (make-row "subtotal" name "" income expenses)))))
    (let ((rows (append-map dimension-rows dimensions)))
      (append rows
              (list (make-row "grand-total" (N_ "Grand Total") ""
                              grand-income grand-expenses))))))

;; exchange takes a monetary and posted date, returning report-currency money.
;; Return no rows if validation or currency conversion fails: partial totals
;; would look authoritative while omitting some of the selected activity.
(define (summarize splits currency exchange)
  (let ((totals (make-hash-table)) (errors '()))
    (hash-set! totals "" '(0 0))
    (for-each
     (lambda (split)
       (when (eligible-split? split)
         (let ((tags (split-tags split)))
           (if (> (length tags) 1)
               (set! errors
                     (cons (list split (format #f (G_ "Conflicting classification tags: ~a")
                                               (string-join tags ", ")))
                           errors))
               (let* ((trans (xaccSplitGetParent split))
                      (account (xaccSplitGetAccount split))
                      ;; Use native account amounts, like the Income Statement.
                      ;; A foreign-currency receipt must not revalue an amount
                      ;; already recorded in a report-currency expense account.
                      (raw (xaccSplitGetAmount split))
                      (converted
                       (exchange (gnc:make-gnc-monetary (xaccAccountGetCommodity account) raw)
                                 (xaccTransGetDate trans)))
                      (amount (gnc:gnc-monetary-amount converted))
                      (tag (if (null? tags) "" (car tags)))
                      (current (hash-ref totals tag '(0 0))))
                 (if (or (not (gnc-commodity-equiv
                               currency (gnc:gnc-monetary-commodity converted)))
                         (and (not (zero? raw)) (zero? amount)))
                     (set! errors
                           (cons (list split (G_ "Missing currency conversion; add a price in the Price Database."))
                                 errors))
                     (hash-set! totals tag
                                (if (= (xaccAccountGetType account) ACCT-TYPE-INCOME)
                                    (list (- (car current) amount) (cadr current))
                                    (list (car current) (+ (cadr current) amount))))))))))
     splits)
    (values (and (null? errors) (summary-rows totals)) (reverse errors))))

(define (options-generator)
  (let ((options (gnc-new-optiondb)))
    (gnc:options-add-date-interval! options gnc:pagename-general opt-start opt-end "a")
    (gnc-set-option options gnc:pagename-general opt-start '(relative . start-prev-year))
    (gnc-set-option options gnc:pagename-general opt-end '(relative . end-prev-year))
    (gnc:options-add-currency! options gnc:pagename-general opt-currency "b")
    (gnc:options-add-price-source! options gnc:pagename-general opt-prices "c" 'pricedb-nearest)
    (gnc-register-account-list-limited-option options
      gnc:pagename-accounts opt-accounts "a"
      (N_ "Report on these income and expense accounts. Select all for a complete overview.")
      (gnc:filter-accountlist-type
       (list ACCT-TYPE-INCOME ACCT-TYPE-EXPENSE)
       (gnc-account-get-descendants-sorted (gnc-get-current-root-account)))
      (list ACCT-TYPE-INCOME ACCT-TYPE-EXPENSE))
    (gnc:options-set-default-section options gnc:pagename-general)
    options))

(define csv-header
  '("row_type" "dimension" "tag" "income" "expenses" "net_cost"
    "monthly_income" "monthly_expenses" "monthly_net_cost"))

(define (rows->csv rows currency start end)
  (gnc:lists->csv
   (append (list (list "currency" (gnc-commodity-get-mnemonic currency))
                 (list "from" (gnc-print-time64 start "%Y-%m-%d"))
                 (list "to" (gnc-print-time64 end "%Y-%m-%d"))
                 '("monthly_divisor" 12)
                 csv-header)
           rows)))

(define (add-summary-table! document rows currency)
  (let ((table (gnc:make-html-table)))
    (gnc:html-table-set-col-headers!
     table (map G_ (list (N_ "Dimension") (N_ "Tag") (N_ "Income")
                         (N_ "Expenses") (N_ "Net Cost") (N_ "Monthly Income")
                         (N_ "Monthly Expenses") (N_ "Monthly Net Cost"))))
    (for-each
     (lambda (row)
       (let* ((total? (not (string=? (car row) "tag")))
              (text-style (if total? "total-label-cell" "text-cell"))
              (number-style (if total? "total-number-cell" "number-cell"))
              (tag (list-ref row 2)))
         (gnc:html-table-append-row/markup!
          table (if total? "grand-total" "normal-row")
          (append
           (list (gnc:make-html-table-cell/markup text-style (G_ (cadr row)))
                 (gnc:make-html-table-cell/markup
                  text-style (cond (total? (G_ "Total"))
                                   ((string-null? tag) (G_ "No classification tag"))
                                   (else tag))))
           (map (lambda (amount)
                  (gnc:make-html-table-cell/markup
                   number-style (gnc:make-gnc-monetary currency amount)))
                (drop row 3))))))
     rows)
    (gnc:html-document-add-object! document table)))

(define (add-errors! document errors)
  (let ((table (gnc:make-html-table)))
    (gnc:html-document-add-object!
     document (gnc:make-html-text
               (gnc:html-markup-h3 (G_ "Resolve these errors before viewing totals or exporting CSV."))))
    (gnc:html-table-set-col-headers!
     table (map G_ (list (N_ "Date") (N_ "Transaction") (N_ "Account")
                         (N_ "Memo") (N_ "Error"))))
    (for-each
     (lambda (entry)
       (let* ((split (car entry)) (trans (xaccSplitGetParent split)))
         (gnc:html-table-append-row!
          table (list (qof-print-date (xaccTransGetDate trans))
                      (gnc:html-split-anchor split (xaccTransGetDescription trans))
                      (gnc-account-get-full-name (xaccSplitGetAccount split))
                      (xaccSplitGetMemo split) (cadr entry)))))
     errors)
    (gnc:html-document-add-object! document table)
    (gnc:html-document-set-export-error document (G_ "Resolve report errors before exporting."))))

(define (renderer report-obj export-type)
  (define (option name)
    (gnc-option-value (gnc:report-options report-obj) gnc:pagename-general name))
  (let* ((document (gnc:make-html-document))
         (title (option gnc:optname-reportname))
         (start (gnc:time64-start-day-time (gnc:date-option-absolute-time (option opt-start))))
         (end (gnc:time64-end-day-time (gnc:date-option-absolute-time (option opt-end))))
         (currency (option opt-currency))
         (accounts (gnc-option-value (gnc:report-options report-obj)
                                     gnc:pagename-accounts opt-accounts)))
    (gnc:report-starting title)
    (gnc:html-document-set-title! document title)
    (cond
     ((> start end)
      (gnc:html-document-add-object!
       document (gnc:make-html-text (G_ "Start date must be on or before end date.")))
      (gnc:html-document-set-export-error document (G_ "Invalid date range.")))
     ((null? accounts)
      (gnc:html-document-add-object!
       document (gnc:html-make-no-account-warning title (gnc:report-id report-obj)))
      (gnc:html-document-set-export-error document (G_ "No accounts selected.")))
     (else
      (let* ((splits (query-splits (gnc-get-current-book) accounts start end))
             (exchange (gnc:case-exchange-time-fn
                        (option opt-prices) currency
                        (gnc:accounts-get-commodities accounts currency) end 0 0)))
        (call-with-values
            (lambda () (summarize splits currency
                                  (lambda (money date) (exchange money currency date))))
          (lambda (rows errors)
            (if (pair? errors)
                (add-errors! document errors)
                (begin
                  (gnc:html-document-add-object!
                   document (gnc:make-html-text
                             (format #f (G_ "From ~a to ~a. Monthly averages are period totals divided by 12; choose a full year for a monthly spending average. Net cost is expenses minus income.")
                                     (qof-print-date start) (qof-print-date end))))
                  (add-summary-table! document rows currency)
                  (when (eq? export-type 'csv)
                    (gnc:html-document-set-export-string
                     document (rows->csv rows currency start end))))))))))
    (gnc:report-finished)
    document))

(gnc:define-report
 'version 1
 'name report-name
 'report-guid report-guid
 'menu-path (list gnc:menuname-income-expense)
 'options-generator options-generator
 'renderer (lambda (report) (renderer report #f))
 'export-types '(("CSV" . csv))
 'export-thunk (lambda (report type) (renderer report type)))
