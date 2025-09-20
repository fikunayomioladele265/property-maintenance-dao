;; Expense Tracking Contract
;; Track maintenance expenses and distribute costs among property owners

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u601))
(define-constant ERR-EXPENSE-NOT-FOUND (err u602))
(define-constant ERR-INSUFFICIENT-FUNDS (err u603))
(define-constant ERR-INVALID-AMOUNT (err u604))
(define-constant ERR-ALREADY-PAID (err u605))

;; Constants
(define-constant DAO-FEE-RATE u5) ;; 5% DAO fee
(define-constant MAX-EXPENSE-AMOUNT u10000000) ;; 10 STX max

;; Data variables
(define-data-var expense-counter uint u0)
(define-data-var total-expenses uint u0)
(define-data-var dao-balance uint u0)

;; Data maps
(define-map expenses
    uint ;; expense-id
    {
        request-id: uint,
        contractor: principal,
        amount: uint,
        category: (string-ascii 50),
        description: (string-ascii 200),
        status: (string-ascii 20), ;; "pending", "approved", "paid"
        submitted-at: uint,
        approved-at: (optional uint)
    }
)

(define-map property-owners
    principal
    {
        unit-number: (string-ascii 10),
        ownership-percentage: uint, ;; 0-10000 basis points (0-100%)
        total-contributions: uint,
        outstanding-balance: uint,
        is-active: bool
    }
)

(define-map owner-payments
    { expense-id: uint, owner: principal }
    {
        amount-owed: uint,
        amount-paid: uint,
        paid-at: (optional uint)
    }
)

;; Private functions
(define-private (get-next-expense-id)
    (let ((current-id (var-get expense-counter)))
        (var-set expense-counter (+ current-id u1))
        (+ current-id u1)
    )
)

(define-private (calculate-owner-share (total-amount uint) (ownership-percentage uint))
    (/ (* total-amount ownership-percentage) u10000)
)

;; Read-only functions
(define-read-only (get-expense (expense-id uint))
    (map-get? expenses expense-id)
)

(define-read-only (get-property-owner (owner principal))
    (map-get? property-owners owner)
)

(define-read-only (get-payment-info (expense-id uint) (owner principal))
    (map-get? owner-payments { expense-id: expense-id, owner: owner })
)

(define-read-only (get-dao-balance)
    (var-get dao-balance)
)

(define-read-only (get-total-expenses)
    (var-get total-expenses)
)

;; Public functions
(define-public (register-owner (unit-number (string-ascii 10)) (ownership-percentage uint))
    (begin
        (asserts! (<= ownership-percentage u10000) ERR-INVALID-AMOUNT)
        
        (map-set property-owners tx-sender
            {
                unit-number: unit-number,
                ownership-percentage: ownership-percentage,
                total-contributions: u0,
                outstanding-balance: u0,
                is-active: true
            }
        )
        
        (ok true)
    )
)

(define-public (submit-expense (request-id uint) (contractor principal) (amount uint) (category (string-ascii 50)) (description (string-ascii 200)))
    (let ((expense-id (get-next-expense-id)))
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= amount MAX-EXPENSE-AMOUNT) ERR-INVALID-AMOUNT)
        
        (map-set expenses expense-id
            {
                request-id: request-id,
                contractor: contractor,
                amount: amount,
                category: category,
                description: description,
                status: "pending",
                submitted-at: block-height,
                approved-at: none
            }
        )
        
        (ok expense-id)
    )
)

(define-public (approve-expense (expense-id uint))
    (let 
        (
            (expense-data (unwrap! (map-get? expenses expense-id) ERR-EXPENSE-NOT-FOUND))
        )
        ;; For simplicity, allow any caller - in production would be DAO governance
        (asserts! (is-eq (get status expense-data) "pending") ERR-UNAUTHORIZED)
        
        (map-set expenses expense-id
            (merge expense-data {
                status: "approved",
                approved-at: (some block-height)
            })
        )
        
        ;; Create payment obligations for all owners
        (distribute-expense-to-owners expense-id (get amount expense-data))
        
        (ok true)
    )
)

(define-public (pay-expense-share (expense-id uint))
    (let 
        (
            (expense-data (unwrap! (map-get? expenses expense-id) ERR-EXPENSE-NOT-FOUND))
            (owner-data (unwrap! (map-get? property-owners tx-sender) ERR-UNAUTHORIZED))
            (payment-info (unwrap! (map-get? owner-payments { expense-id: expense-id, owner: tx-sender }) ERR-EXPENSE-NOT-FOUND))
        )
        (asserts! (is-eq (get status expense-data) "approved") ERR-UNAUTHORIZED)
        (asserts! (is-eq (get amount-paid payment-info) u0) ERR-ALREADY-PAID)
        
        (let ((amount-owed (get amount-owed payment-info)))
            ;; Process payment (simplified - in production would use actual STX transfers)
            (map-set owner-payments { expense-id: expense-id, owner: tx-sender }
                (merge payment-info {
                    amount-paid: amount-owed,
                    paid-at: (some block-height)
                })
            )
            
            ;; Update owner stats
            (map-set property-owners tx-sender
                (merge owner-data {
                    total-contributions: (+ (get total-contributions owner-data) amount-owed),
                    outstanding-balance: (- (get outstanding-balance owner-data) amount-owed)
                })
            )
            
            ;; Update global stats
            (var-set total-expenses (+ (var-get total-expenses) amount-owed))
            
            (ok amount-owed)
        )
    )
)

;; Private helper function
(define-private (distribute-expense-to-owners (expense-id uint) (total-amount uint))
    ;; Simplified - in production would iterate through all owners
    ;; For now, just create a placeholder for the current transaction sender
    (match (map-get? property-owners tx-sender)
        owner-data
            (let ((owner-share (calculate-owner-share total-amount (get ownership-percentage owner-data))))
                (map-set owner-payments { expense-id: expense-id, owner: tx-sender }
                    {
                        amount-owed: owner-share,
                        amount-paid: u0,
                        paid-at: none
                    }
                )
                
                ;; Update outstanding balance
                (map-set property-owners tx-sender
                    (merge owner-data {
                        outstanding-balance: (+ (get outstanding-balance owner-data) owner-share)
                    })
                )
                true
            )
        true
    )
)


;; title: expense-tracking
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

