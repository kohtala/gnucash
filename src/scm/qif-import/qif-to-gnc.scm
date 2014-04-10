;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  qif-to-gnc.scm
;;;  this is where QIF transactions are transformed into a 
;;;  Gnucash account tree.
;;;
;;;  Bill Gribble <grib@billgribble.com> 20 Feb 2000 
;;;  $Id$
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(gnc:support "qif-import/qif-to-gnc.scm")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  find-or-make-acct:
;;  given a colon-separated account path, return an Account* to
;;  an existing or new account.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-import:find-or-make-acct acct-info currency security 
                                      gnc-acct-hash acct-group)
  (let* ((separator (string-ref (gnc:account-separator-char) 0))
         (gnc-name (qif-map-entry:gnc-name acct-info))
         (existing-account (hash-ref gnc-acct-hash gnc-name))
         (same-gnc-account 
          (gnc:get-account-from-full-name acct-group gnc-name separator))
         (make-new-acct #f))
    
    (if (or (pointer-token-null? same-gnc-account) 
            (and (not (pointer-token-null? same-gnc-account))
                 (not (string=? 
                       (gnc:account-get-full-name same-gnc-account)
                       gnc-name))))
        (set! make-new-acct #t))
    
    (if existing-account 
        existing-account 
        (let ((new-acct (gnc:malloc-account))
              (parent-acct #f)
              (parent-name #f)
              (acct-name #f)
              (last-colon #f))
          (set! last-colon (string-rindex gnc-name separator))
          
          (gnc:init-account new-acct)
          (gnc:account-begin-edit new-acct)
          
          ;; if this is a copy of an existing gnc account, 
          ;; copy the account properties 
          (if (not make-new-acct)
              (begin 
                (gnc:account-set-name 
                 new-acct (gnc:account-get-name same-gnc-account))
                (gnc:account-set-description
                 new-acct (gnc:account-get-description same-gnc-account))
                (gnc:account-set-type
                 new-acct (gnc:account-get-type same-gnc-account))
                (gnc:account-set-currency
                 new-acct (gnc:account-get-currency same-gnc-account))
                (gnc:account-set-notes 
                 new-acct (gnc:account-get-notes same-gnc-account))
                (gnc:account-set-code 
                 new-acct (gnc:account-get-code same-gnc-account))
                (gnc:account-set-security
                 new-acct (gnc:account-get-security same-gnc-account))))
          
          ;; make sure that if this is a nested account foo:bar:baz,
          ;; foo:bar and foo exist also.
          (if last-colon
              (let ((pinfo (make-qif-map-entry)))
                (set! parent-name (substring gnc-name 0 last-colon))
                (set! acct-name (substring gnc-name (+ 1 last-colon) 
                                           (string-length gnc-name)))
                (qif-map-entry:set-qif-name! pinfo parent-name)
                (qif-map-entry:set-gnc-name! pinfo parent-name)
                (qif-map-entry:set-allowed-types! 
                 pinfo (qif-map-entry:allowed-types acct-info))
                
                (set! parent-acct (qif-import:find-or-make-acct 
                                   pinfo currency security 
                                   gnc-acct-hash acct-group)))
              (begin 
                (set! acct-name gnc-name)))
          
          ;; if this is a new account, use the 
          ;; parameters passed in
          (if make-new-acct
              (begin 
                ;; set the name, description, etc.
                (gnc:account-set-name new-acct acct-name)
                (if (qif-map-entry:description acct-info)
                    (gnc:account-set-description 
                     new-acct (qif-map-entry:description acct-info)))
                (gnc:account-set-currency new-acct currency)
                (gnc:account-set-security new-acct security)
                
                ;; set the account type FIXME !!
                (if (qif-map-entry:allowed-types acct-info)
                    (gnc:account-set-type 
                     new-acct (car (qif-map-entry:allowed-types acct-info))))))
          
          (gnc:account-commit-edit new-acct)
          (if parent-acct
              (gnc:insert-subaccount parent-acct new-acct)
              (gnc:group-insert-account acct-group new-acct))
          
          (hash-set! gnc-acct-hash gnc-name new-acct)
          new-acct))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; qif-import:qif-to-gnc 
;; this is the top-level of the back end conversion from 
;; QIF to GNC.  all the account mappings and so on should be 
;; done before this is called. 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-import:qif-to-gnc qif-files-list 
                               qif-acct-map qif-cat-map stock-map 
                               default-currency-name)
  (let* ((account-group (gnc:get-current-group))
         (gnc-acct-hash (make-hash-table 20))
         (separator (string-ref (gnc:account-separator-char) 0))
         (default-currency 
           (gnc:commodity-table-find-full 
            (gnc:engine-commodities) 
            GNC_COMMODITY_NS_ISO default-currency-name))
         (sorted-accounts-list '())
         (markable-xtns '())
         (sorted-qif-files-list 
          (sort qif-files-list 
                (lambda (a b)
                  (> (length (qif-file:xtns a)) 
                     (length (qif-file:xtns b)))))))
    
    ;; first, build a local account tree that mirrors the gnucash
    ;; accounts in the mapping data.  we need to iterate over the
    ;; cat-map and the acct-map to build the list
    (for-each 
     (lambda (bin)
       (for-each 
        (lambda (hashpair)
          (let* ((acctinfo (cdr hashpair)))
            (if (qif-map-entry:display? acctinfo)
                (set! sorted-accounts-list 
                      (cons acctinfo sorted-accounts-list)))))
        bin))
     (vector->list qif-acct-map))
    
    (for-each 
     (lambda (bin)
       (for-each 
        (lambda (hashpair)
          (let* ((acctinfo (cdr hashpair)))
            (if (qif-map-entry:display? acctinfo)
                (set! sorted-accounts-list 
                      (cons acctinfo sorted-accounts-list)))))
        bin))
     (vector->list qif-cat-map))
    

    ;; sort the account info on the depth of the account path.  if a
    ;; short part is explicitly mentioned, make sure it gets created
    ;; before the deeper path, which will create the parent accounts
    ;; without the information about their type.
    (set! sorted-accounts-list 
          (sort sorted-accounts-list 
                (lambda (a b)
                  (let ((a-depth 
                         (length 
                          (string-split-on (qif-map-entry:gnc-name a) 
                                           separator)))
                        (b-depth 
                         (length 
                          (string-split-on (qif-map-entry:gnc-name b) 
                                           separator))))
                    (< a-depth b-depth)))))
    
    ;; make all the accounts 
    (for-each 
     (lambda (acctinfo)
       (let* ((security 
               (and stock-map 
                    (hash-ref stock-map 
                              (qif-import:get-account-name 
                               (qif-map-entry:qif-name acctinfo)))))
              (ok-types (qif-map-entry:allowed-types acctinfo))
              (equity? (memq GNC-EQUITY-TYPE ok-types)))
         
         (cond ((and equity? security)  ;; a "retained holdings" acct
                (qif-import:find-or-make-acct acctinfo 
                                              security security
                                              gnc-acct-hash account-group))
               (security 
                (qif-import:find-or-make-acct acctinfo 
                                              default-currency security
                                              gnc-acct-hash account-group))
               (#t 
                (qif-import:find-or-make-acct acctinfo 
                                              default-currency default-currency
                                              gnc-acct-hash account-group)))))
     sorted-accounts-list)
    
    ;; before trying to mark transactions, prune down the list of 
    ;; ones to match. 
    (for-each 
     (lambda (qif-file)
       (for-each 
        (lambda (xtn)
          (let splitloop ((splits (qif-xtn:splits xtn)))             
            (if (qif-split:category-is-account? (car splits))
                (set! markable-xtns (cons xtn markable-xtns))
                (if (not (null? (cdr splits)))
                    (splitloop (cdr splits))))))
        (qif-file:xtns qif-file)))
     qif-files-list)
    
    ;; now run through the markable transactions marking any
    ;; duplicates.  marked transactions/splits won't get imported.
    (if (> (length markable-xtns) 1)
        (let xloop ((xtn (car markable-xtns))
                    (rest (cdr markable-xtns)))
          (if (not (qif-xtn:mark xtn))
              (qif-import:mark-matching-xtns xtn rest))
          (if (not (null? (cdr rest)))
              (xloop (car rest) (cdr rest)))))
    
    ;; iterate over files. Going in the sort order by number of 
    ;; transactions should give us a small speed advantage.
    (for-each 
     (lambda (qif-file)
       (for-each 
        (lambda (xtn)
          (if (not (qif-xtn:mark xtn))
              (begin 
                ;; create and fill in the GNC transaction
                (let ((gnc-xtn (gnc:transaction-create)))
                  (gnc:transaction-begin-edit gnc-xtn 1)

                  ;; destroy any automagic splits in the transaction
                  (let ((numsplits (gnc:transaction-get-split-count gnc-xtn)))
                    (if (not (eqv? 0 numsplits))
                        (let splitloop ((ind (- numsplits 1)))
                          (gnc:split-destroy 
                           (gnc:transaction-get-split gnc-xtn ind))
                          (if (> ind 0)
                              (loop (- ind 1))))))
                  
                  ;; build the transaction
                  (qif-import:qif-xtn-to-gnc-xtn 
                   xtn qif-file gnc-xtn gnc-acct-hash 
                   qif-acct-map qif-cat-map)
                  
                  ;; rebalance and commit everything
                  (gnc:transaction-commit-edit gnc-xtn)))))
        (qif-file:xtns qif-file)))
     sorted-qif-files-list)
    
    ;; now take the new account tree and merge it in with the 
    ;; existing gnucash account tree. 
    (gnc:merge-accounts account-group)
    (gnc:refresh-main-window)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; qif-import:qif-xtn-to-gnc-xtn
;; translate a single transaction to a set of gnucash splits and 
;; a gnucash transaction structure. 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-import:qif-xtn-to-gnc-xtn qif-xtn qif-file gnc-xtn 
                                       gnc-acct-hash qif-acct-map qif-cat-map)
  (let ((splits (qif-xtn:splits qif-xtn))
        (gnc-near-split (gnc:split-create))
        (near-split-total 0.0)
        (near-acct-info #f)
        (near-acct-name #f)
        (near-acct #f)
        (qif-payee (qif-xtn:payee qif-xtn))
        (qif-number (qif-xtn:number qif-xtn))
        (qif-action (qif-xtn:action qif-xtn))
        (qif-security (qif-xtn:security-name qif-xtn))
        (qif-memo (qif-split:memo (car (qif-xtn:splits qif-xtn))))
        (qif-from-acct (qif-xtn:from-acct qif-xtn))
        (qif-cleared (qif-xtn:cleared qif-xtn)))
    
    ;; set properties of the whole transaction     
    (apply gnc:transaction-set-date gnc-xtn (qif-xtn:date qif-xtn))
    
    (if qif-payee
        (gnc:transaction-set-description gnc-xtn qif-payee))
    (if qif-number
        (gnc:transaction-set-xnum gnc-xtn qif-number))
    (if qif-memo
        (gnc:split-set-memo gnc-near-split qif-memo))
    
    (if (eq? qif-cleared 'cleared)        
        (gnc:split-set-reconcile gnc-near-split #\c))
    (if (eq? qif-cleared 'reconciled)
        (gnc:split-set-reconcile gnc-near-split #\y))

    (if (not qif-security)
        (begin 
          ;; NON-STOCK TRANSACTIONS: the near account is the current
          ;; bank-account or the default associated with the file.
          ;; the far account is the one associated with the split
          ;; category.
          (set! near-acct-info (hash-ref qif-acct-map qif-from-acct))
          (set! near-acct-name (qif-map-entry:gnc-name near-acct-info))
          (set! near-acct (hash-ref gnc-acct-hash near-acct-name))
          
          ;; iterate over QIF splits.  Each split defines one "far
          ;; end" for the transaction.
          (for-each 
           (lambda (qif-split)
             (if (not (qif-split:mark qif-split))
                 (let ((gnc-far-split (gnc:split-create))
                       (far-acct-info #f)
                       (far-acct-name #f)
                       (far-acct-type #f)
                       (far-acct #f)
                       (split-amt (qif-split:amount qif-split))
                       (memo (qif-split:memo qif-split)))
                   
                   (if (not split-amt) (set! split-amt 0.0))
                   
                   ;; fill the splits in (near first).  This handles
                   ;; files in multiple currencies by pulling the
                   ;; currency value from the file import.
                   (set! near-split-total (+ near-split-total split-amt))
                   (gnc:split-set-value gnc-far-split (- split-amt))
                   
                   (if memo (gnc:split-set-memo gnc-far-split memo))
                   
                   (if (qif-split:category-is-account? qif-split)
                       (set! far-acct-info
                             (hash-ref qif-acct-map 
                                       (qif-split:category qif-split)))
                       (set! far-acct-info
                             (hash-ref qif-cat-map 
                                       (qif-split:category qif-split))))
                   (set! far-acct-name (qif-map-entry:gnc-name far-acct-info))
                   (set! far-acct (hash-ref gnc-acct-hash far-acct-name))
                   
                   ;; set the reconcile status. 
                   (let ((cleared (qif-split:matching-cleared qif-split)))
                     (if (eq? 'cleared cleared)
                         (gnc:split-set-reconcile gnc-far-split #\c))
                     (if (eq? 'reconciled cleared)
                         (gnc:split-set-reconcile gnc-far-split #\y)))
                   
                   ;; finally, plug the split into the account 
                   (gnc:transaction-append-split gnc-xtn gnc-far-split)
                   (gnc:account-insert-split far-acct gnc-far-split))))
           splits)
          
          ;; the value of the near split is the total of the far splits.
          (gnc:split-set-value gnc-near-split near-split-total)
          (gnc:transaction-append-split gnc-xtn gnc-near-split)
          (gnc:account-insert-split near-acct gnc-near-split))
        
        ;; STOCK TRANSACTIONS: the near/far accounts depend on the
        ;; "action" encoded in the Number field.  It's generally the
        ;; security account (for buys, sells, and reinvests) but can
        ;; also be an interest, dividend, or SG/LG account.
        (let ((share-price (qif-xtn:share-price qif-xtn))
              (num-shares (qif-xtn:num-shares qif-xtn))
              (split-amt (qif-split:amount (car (qif-xtn:splits qif-xtn))))
              (qif-accts #f)
              (qif-near-acct #f)
              (qif-far-acct #f)
              (qif-commission-acct #f)
              (far-acct-info #f)
              (far-acct-name #f)
              (far-acct #f)
              (commission-acct #f)
              (commission-amt (qif-xtn:commission qif-xtn))
              (commission-split #f)
              (defer-share-price #f)
              (gnc-far-split (gnc:split-create)))
          
          (if (not num-shares) (set! num-shares 0.0))
          (if (not share-price) (set! share-price 0.0))
          (if (not split-amt) (set! split-amt (* num-shares share-price)))
          
          ;; I don't think this should ever happen, but I want 
          ;; to keep this check just in case. 
          (if (> (length splits) 1)
              (begin 
                (display "qif-import:qif-xtn-to-gnc-xtn : ")
                (display "splits in stock transaction!") (newline)))

          (set! qif-accts 
                (qif-split:accounts-affected (car (qif-xtn:splits qif-xtn))
                                             qif-xtn))
          
          (set! qif-near-acct (car qif-accts))
          (set! qif-far-acct (cadr qif-accts))
          (set! qif-commission-acct (caddr qif-accts))

          ;; translate the QIF account names into Gnucash accounts
          (if (and qif-near-acct qif-far-acct)
              (begin 
                (set! near-acct-info 
                      (or (hash-ref qif-acct-map qif-near-acct)
                          (hash-ref qif-cat-map qif-near-acct)))
                (set! near-acct-name (qif-map-entry:gnc-name near-acct-info))
                (set! near-acct (hash-ref gnc-acct-hash near-acct-name))
                
                (set! far-acct-info
                      (or (hash-ref qif-acct-map qif-far-acct)
                          (hash-ref qif-cat-map qif-far-acct)))
                (set! far-acct-name (qif-map-entry:gnc-name far-acct-info))
                (set! far-acct (hash-ref gnc-acct-hash far-acct-name))))
          
          ;; the amounts and signs: are shares going in or out? 
          ;; are amounts currency or shares? 
          (case qif-action
            ((buy buyx reinvint reinvdiv reinvsg reinvsh reinvlg)
             (if (not share-price) (set! share-price 0.0))
             (gnc:split-set-share-price gnc-near-split share-price)
             (gnc:split-set-share-price gnc-far-split share-price)
             (gnc:split-set-share-amount gnc-near-split num-shares)
             (gnc:split-set-share-amount gnc-far-split (- num-shares))
             (gnc:split-set-value gnc-near-split split-amt)
             (gnc:split-set-value gnc-far-split (- split-amt)))
            
            ((sell sellx) 
             (if (not share-price) (set! share-price 0.0))
             (gnc:split-set-share-price gnc-near-split share-price)
             (gnc:split-set-share-price gnc-far-split share-price)
             (gnc:split-set-share-amount gnc-near-split (- num-shares))
             (gnc:split-set-share-amount gnc-far-split num-shares)
             (gnc:split-set-value gnc-near-split (- split-amt))
             (gnc:split-set-value gnc-far-split split-amt))
            
            ((cgshort cgshortx cglong cglongx intinc intincx div divx
                      miscinc miscincx xin)
             (gnc:split-set-value gnc-near-split split-amt)
             (gnc:split-set-value gnc-far-split (- split-amt)))
            
            ((xout miscexp miscexpx )
             (gnc:split-set-value gnc-near-split (- split-amt))
             (gnc:split-set-value gnc-far-split  split-amt))
            
            ((shrsin)
             ;; for shrsin, the near account is the security account.
             ;; we'll need to set the share-price after a little 
             ;; trickery post-adding-to-account
             (if (not share-price) 
                 (set! defer-share-price #t)
                 (gnc:split-set-share-price gnc-near-split share-price))
             (gnc:split-set-share-amount gnc-near-split num-shares)
             (gnc:split-set-value gnc-far-split num-shares))

            ((shrsout)
             ;; shrsout is like shrsin             
             (if (not share-price) 
                 (set! defer-share-price #t)
                 (gnc:split-set-share-price gnc-near-split share-price))
             (gnc:split-set-share-amount gnc-near-split (- num-shares))
             (gnc:split-set-value gnc-far-split (- num-shares)))
            
            ;; stock splits: QIF just specifies the split ratio, not
            ;; the number of shares in and out, so we have to fetch
            ;; the number of shares from the security account 

            ;; FIXME : this could be wrong.  Make sure the
            ;; share-amount is at the correct time.
            ((stksplit)
             (let* ((splitratio (/ num-shares 10))
                    (in-shares 
                     (gnc:account-get-share-balance near-acct))
                    (out-shares (* in-shares splitratio)))
               (if (not share-price) (set! share-price 0.0))
               (gnc:split-set-share-price gnc-near-split 
                                          (/ share-price splitratio))
               (gnc:split-set-share-price gnc-far-split share-price) 
               (gnc:split-set-share-amount gnc-near-split out-shares)
               (gnc:split-set-share-amount gnc-far-split (- in-shares))
               (gnc:split-set-value gnc-near-split (- split-amt))
               (gnc:split-set-value gnc-far-split split-amt)))
            (else 
             (display "symbol = " ) (write qif-action) (newline)))
          
          (let ((cleared (qif-split:matching-cleared 
                          (car (qif-xtn:splits qif-xtn)))))
            (if (eq? 'cleared cleared)
                (gnc:split-set-reconcile gnc-far-split #\c))
            (if (eq? 'reconciled cleared)
                (gnc:split-set-reconcile gnc-far-split #\y)))

          (if qif-commission-acct
              (let* ((commission-acct-info 
                      (or (hash-ref qif-acct-map qif-commission-acct)
                          (hash-ref qif-cat-map qif-commission-acct)))
                     (commission-acct-name 
                      (qif-map-entry:gnc-name commission-acct-info)))
                (set! commission-acct 
                      (hash-ref gnc-acct-hash commission-acct-name))))
          
          (if (and commission-amt commission-acct)
              (begin 
                (set! commission-split (gnc:split-create))
                (gnc:split-set-value commission-split commission-amt)))
          
          (if (and qif-near-acct qif-far-acct)
              (begin 
                (gnc:transaction-append-split gnc-xtn gnc-near-split)
                (gnc:account-insert-split near-acct gnc-near-split)
                
                (gnc:transaction-append-split gnc-xtn gnc-far-split)
                (gnc:account-insert-split far-acct gnc-far-split)
                
                (if commission-split
                    (begin 
                      (gnc:transaction-append-split gnc-xtn commission-split)
                      (gnc:account-insert-split commission-acct 
                                                commission-split)))
                
                ;; now find the share price if we need to 
                ;; (shrsin and shrsout xtns)
                (if defer-share-price
                    (qif-import:set-share-price gnc-near-split))))))
    ;; return the modified transaction (though it's ignored).
    gnc-xtn))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  qif-import:mark-matching-xtns 
;;  find transactions that are the "opposite half" of xtn and 
;;  mark them so they won't be imported. 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-import:mark-matching-xtns xtn candidate-xtns)
  (let splitloop ((splits-left (qif-xtn:splits xtn)))
    
    ;; splits-left starts out as all the splits of this transaction.
    ;; if multiple splits match up with a single split on the other 
    ;; end, we may remove more than one split from splits-left with
    ;; each call to mark-some-splits.  
    (if (not (null? splits-left))
        (if (and (not (qif-split:mark (car splits-left)))
                 (qif-split:category-is-account? (car splits-left)))
            (set! splits-left 
                  (qif-import:mark-some-splits 
                   splits-left xtn candidate-xtns))
            (set! splits-left (cdr splits-left))))
    
    (if (not (null? splits-left))
        (splitloop splits-left))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; qif-import:mark-some-splits
;; find split(s) matching elements of splits and mark them so they
;; don't get imported.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-import:mark-some-splits splits xtn candidate-xtns)
  (let* ((split (car splits))
         (near-acct-name #f)
         (far-acct-name #f)
         (date (qif-xtn:date xtn))
         (amount (- (qif-split:amount split)))
         (group-amount #f)
         (memo (qif-split:memo split))        
         (security-name (qif-xtn:security-name xtn))
         (action (qif-xtn:action xtn))
         (bank-xtn? (not security-name))
         (cleared? #f)
         (different-acct-splits '())
         (same-acct-splits '())
         (how #f)
         (done #f))
    
    (if bank-xtn?
        (begin 
          (set! near-acct-name (qif-xtn:from-acct xtn))
          (set! far-acct-name (qif-split:category split))
          (set! group-amount 0.0)
          
          ;; group-amount is the sum of all the splits in this xtn
          ;; going to the same account as 'split'.  We might be able
          ;; to match this whole group to a single matching opposite
          ;; split.
          (for-each 
           (lambda (s)
             (if (and (qif-split:category-is-account? s)
                      (string=? far-acct-name (qif-split:category s)))
                 (begin
                   (set! same-acct-splits 
                         (cons s same-acct-splits))
                   (set! group-amount (- group-amount (qif-split:amount s))))
                 (set! different-acct-splits 
                       (cons s different-acct-splits))))
           splits)
          
          (set! same-acct-splits (reverse same-acct-splits))
          (set! different-acct-splits (reverse different-acct-splits)))
          
        ;; stock transactions.  they can't have splits as far as I can
        ;; tell, so the 'different-acct-splits' is always '()
        (let ((qif-accts 
               (qif-split:accounts-affected split xtn)))
          (set! near-acct-name (car qif-accts))
          (set! far-acct-name (cadr qif-accts))
          (set! same-acct-splits (list split))
          (if action
              ;; we need to do some special massaging to get
              ;; transactions to match up.  Quicken thinks the near
              ;; and far accounts are different than we do.
              (case action
                ((intincx divx cglongx cgshortx sellx)
                 (set! amount (- amount))
                 (set! near-acct-name (qif-xtn:from-acct xtn))
                 (set! far-acct-name (qif-split:category split)))
                ((miscincx miscexpx)
                 (set! amount (- amount))
                 (set! near-acct-name (qif-xtn:from-acct xtn))
                 (set! far-acct-name (qif-split:miscx-category split)))
                ((buyx)
                 (set! near-acct-name (qif-xtn:from-acct xtn))
                 (set! far-acct-name (qif-split:category split)))
                ((xout)
                 (set! amount (- amount)))))))
    
    ;; this is the grind loop.  Go over every unmarked transaction in
    ;; the candidate-xtns list.
    (let xtn-loop ((xtns candidate-xtns))
      (if (not (qif-xtn:mark (car xtns)))
          (begin 
            (set! how
                  (qif-import:xtn-has-matches? (car xtns) near-acct-name
                                               date amount group-amount))
            (if how
                (begin
                  (qif-import:merge-and-mark-xtns xtn same-acct-splits 
                                                  (car xtns) how)
                  (set! done #t)))))
      ;; iterate with the next transaction
      (if (and (not done)
               (not (null? (cdr xtns))))
          (xtn-loop (cdr xtns))))
    
    ;; return the rest of the splits to iterate on
    (if (not how)
        (cdr splits)
        (case (car how)
          ((one-to-one many-to-one)
           (cdr splits))
          ((one-to-many)
           different-acct-splits)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  qif-import:xtn-has-matches?
;;  check for one-to-one, many-to-one, one-to-many split matches.
;;  returns either #f (no match) or a cons cell with the car being one
;;  of 'one-to-one 'one-to-many 'many-to-one, the cdr being a list of
;;  splits that were part of the matching group.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-import:xtn-has-matches? xtn acct-name date amount group-amt)
  (let ((matching-splits '())
        (same-acct-splits '())
        (this-group-amt 0.0)
        (how #f)
        (date-matches 
         (let ((self-date (qif-xtn:date xtn)))
           (and (pair? self-date)
                (pair? date)
                (eq? (length self-date) 3)
                (eq? (length date) 3)
                (= (car self-date) (car date))
                (= (cadr self-date) (cadr date))
                (= (caddr self-date) (caddr date))))))
    (if date-matches 
        (begin 
          ;; calculate a group total for splits going to acct-name    
          (let split-loop ((splits-left (qif-xtn:splits xtn)))
            (let ((split (car splits-left)))
              ;; does the account match up?
              (if (and (qif-split:category-is-account? split)
                       (string=? (qif-split:category split) acct-name))
                  ;; if so, get the amount 
                  (let ((this-amt (qif-split:amount split))
                        (stock-xtn (qif-xtn:security-name xtn))
                        (action (qif-xtn:action xtn)))
                    ;; need to change the sign of the amount for some
                    ;; stock transactions (buy/sell both positive in
                    ;; QIF)
                    (if (and stock-xtn action)
                        (case action 
                          ((xout sellx intincx divx cglongx cgshortx 
                                 miscincx miscexpx)
                           (set! this-amt (- this-amt)))))
                    
                    ;; we might be done if this-amt is either equal 
                    ;; to the split amount or the group amount.
                    (cond 
                     ((= this-amt amount)
                      (set! how 
                            (cons 'one-to-one (list split))))
                     ((and group-amt (= this-amt group-amt))
                      (set! how
                            (cons 'one-to-many (list split))))
                     (#t
                      (set! same-acct-splits (cons split same-acct-splits))
                      (set! this-group-amt 
                            (+ this-group-amt this-amt))))))
              
              ;; if 'how' is non-#f, we are ready to return.
              (if (and (not how) 
                       (not (null? (cdr splits-left))))
                  (split-loop (cdr splits-left)))))
          
          ;; now we're out of the loop.  if 'how' isn't set, 
          ;; we can still have a many-to-one match.
          (if (and (not how)
                   (= this-group-amt amount))
              (begin 
                (set! how 
                      (cons 'many-to-one same-acct-splits))))))
    
    ;; we're all done.  'how' either is #f or a 
    ;; cons of the way-it-matched and a list of the matching 
    ;; splits. 
    how))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  (qif-split:accounts-affected split xtn)
;;  Get the near and far ends of a split, returned as a list 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-split:accounts-affected split xtn) 
  (let ((near-acct-name #f)
        (far-acct-name #f)
        (commission-acct-name #f)
        (security (qif-xtn:security-name xtn))
        (action (qif-xtn:action xtn))
        (from-acct (qif-xtn:from-acct xtn)))
    
    ;; for non-security transactions, the near account is the 
    ;; acct in which the xtn is, and the far is the account 
    ;; linked by the category line. 
    
    (if (not security)
        ;; non-security transactions 
        (begin 
          (set! near-acct-name from-acct)
          (set! far-acct-name (qif-split:category split)))
        
        ;; security transactions : the near end is either the 
        ;; brokerage, the stock, or the category 
        (begin
          (case action
            ((buy buyx sell sellx reinvint reinvdiv reinvsg reinvsh 
                  reinvlg shrsin shrsout stksplit)
             (set! near-acct-name (default-stock-acct from-acct security)))
            ((div cgshort cglong intinc miscinc miscexp xin xout)
             (set! near-acct-name from-acct))
            ((divx cgshortx cglongx intincx)
             (set! near-acct-name 
                   (qif-split:category (car (qif-xtn:splits xtn)))))
            ((miscincx miscexpx)
             (set! near-acct-name 
                   (qif-split:miscx-category (car (qif-xtn:splits xtn))))))

          ;; the far split: where is the money coming from?  
          ;; Either the brokerage account, the category,
          ;; or an external account 
          (case action
            ((buy sell)
             (set! far-acct-name from-acct))
            ((buyx sellx miscinc miscincx miscexp miscexpx xin xout)
             (set! far-acct-name 
                   (qif-split:category (car (qif-xtn:splits xtn)))))
            ((stksplit)
             (set! far-acct-name (default-stock-acct from-acct security)))
            ((cgshort cgshortx reinvsg reinvsh)
             (set! far-acct-name
                   (default-cgshort-acct from-acct security)))
            ((cglong cglongx reinvlg)
             (set! far-acct-name
                   (default-cglong-acct from-acct security)))
            ((intinc intincx reinvint)
             (set! far-acct-name
                   (default-interest-acct from-acct security)))
            ((div divx reinvdiv)
             (set! far-acct-name
                   (default-dividend-acct from-acct security)))            
            ((shrsin shrsout)
             (set! far-acct-name
                   (default-equity-holding security))))

          ;; the commission account, if it exists 
          (if (qif-xtn:commission xtn)
              (set! commission-acct-name 
                    (default-commission-acct from-acct)))))
    
    (list near-acct-name far-acct-name commission-acct-name)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; qif-import:merge-and-mark-xtns 
;; we know that the splits match.  Pick one to mark and 
;; merge the information into the other one.  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-import:merge-and-mark-xtns xtn splits other-xtn how)
  ;; merge transaction fields 
  (let ((action (qif-xtn:action xtn))
        (o-action (qif-xtn:action other-xtn))
        (security (qif-xtn:security-name xtn))
        (o-security (qif-xtn:security-name other-xtn))
        (split (car splits))
        (match-type (car how))
        (match-splits (cdr how)))
    (case match-type 
      ;; many-to-one: the other-xtn has several splits that total
      ;; in amount to 'split'.  We want to preserve the multi-split
      ;; transaction.  
      ((many-to-one)
       (qif-xtn:mark-split xtn split)
       (qif-import:merge-xtn-info xtn other-xtn)
       (for-each 
        (lambda (s)
          (qif-split:set-matching-cleared! s (qif-xtn:cleared xtn)))
        match-splits))
      
      ;; one-to-many: 'split' is just one of a set of splits in xtn
      ;; that total up to the split in match-splits.
      ((one-to-many)
       (qif-xtn:mark-split other-xtn (car match-splits))
       (qif-import:merge-xtn-info other-xtn xtn)
       (for-each 
        (lambda (s)
          (qif-split:set-matching-cleared! 
           s (qif-xtn:cleared other-xtn)))
        splits))

      ;; otherwise: one-to-one, a normal single split match.
      (else 
       (cond 
        ;; this is a transfer involving a security xtn.  Let the 
        ;; security xtn dominate the way it's handled. 
        ((and (not action) o-action o-security)
         (qif-xtn:mark-split xtn split)
         (qif-import:merge-xtn-info xtn other-xtn)
         (qif-split:set-matching-cleared! 
          (car match-splits) (qif-xtn:cleared xtn)))
        
        ((and action (not o-action) security)
         (qif-xtn:mark-split other-xtn (car match-splits))
         (qif-import:merge-xtn-info other-xtn xtn)
         (qif-split:set-matching-cleared! 
          split (qif-xtn:cleared other-xtn)))
        
        ;; this is a security transaction from one brokerage to another
        ;; or within a brokerage.  The "foox" xtn has the most
        ;; information about what went on, so use it.
        ((and action o-action o-security)
         (case o-action
           ((buyx sellx cgshortx cglongx intincx divx miscincx miscexpx)
            (qif-xtn:mark-split xtn split)
            (qif-import:merge-xtn-info xtn other-xtn)
            (qif-split:set-matching-cleared!
             (car match-splits) (qif-xtn:cleared xtn)))
           
           (else 
            (qif-xtn:mark-split other-xtn (car match-splits))
            (qif-import:merge-xtn-info other-xtn xtn)
            (qif-split:set-matching-cleared! 
             split (qif-xtn:cleared other-xtn)))))        
        
        ;; otherwise, this is a normal no-frills split match.  if one
        ;; transaction has more splits than the other one,
        ;; (heuristically) mark the one with less splits.
        (#t 
         (if (< (length (qif-xtn:splits xtn))
                (length (qif-xtn:splits other-xtn)))
             (begin 
               (qif-xtn:mark-split xtn split)
               (qif-import:merge-xtn-info xtn other-xtn)
               (qif-split:set-matching-cleared!
                (car match-splits) (qif-xtn:cleared xtn)))
             
             (begin
               (qif-xtn:mark-split other-xtn (car match-splits))
               (qif-import:merge-xtn-info other-xtn xtn)
               (qif-split:set-matching-cleared!
                split (qif-xtn:cleared other-xtn))))))))))

(define (qif-import:merge-xtn-info from-xtn to-xtn)
  (if (and (qif-xtn:payee from-xtn)
           (not (qif-xtn:payee to-xtn)))
      (qif-xtn:set-payee! to-xtn (qif-xtn:payee from-xtn)))
  (if (and (qif-xtn:address from-xtn)
           (not (qif-xtn:address to-xtn)))
      (qif-xtn:set-address! to-xtn (qif-xtn:address from-xtn)))
  (if (and (qif-xtn:number from-xtn)
           (not (qif-xtn:number to-xtn)))
      (qif-xtn:set-number! to-xtn (qif-xtn:number from-xtn))))


(define (qif-xtn:mark-split xtn split)
  (qif-split:set-mark! split #t)
  (let ((all-marked #t))
    (let loop ((splits (qif-xtn:splits xtn)))
      (if (not (qif-split:mark (car splits)))
          (set! all-marked #f)
          (if (not (null? (cdr splits)))
              (loop (cdr splits)))))
    (if all-marked
        (qif-xtn:set-mark! xtn #t))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; qif-import:set-share-price split 
;; find the split that precedes 'split' in the account and set split's
;; share price to that.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-import:set-share-price split)
  (let* ((account (gnc:split-get-account split))
         (numsplits (gnc:account-get-split-count account)))
    (let loop ((i 0)
               (last-split #f))
      (let ((ith-split (gnc:account-get-split account i)))        
        (if (pointer-token-eq? ith-split split)
            (if last-split
                (gnc:split-set-share-price 
                 split (gnc:split-get-share-price last-split)))
            (if (< i numsplits) (loop (+ 1 i) ith-split)))))))