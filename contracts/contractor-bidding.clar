;; Contractor Bidding Contract
;; Transparent bidding process for maintenance work by qualified contractors

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u501))
(define-constant ERR-BID-NOT-FOUND (err u502))
(define-constant ERR-BIDDING-CLOSED (err u503))
(define-constant ERR-INVALID-AMOUNT (err u504))
(define-constant ERR-NOT-QUALIFIED (err u505))

;; Constants
(define-constant BIDDING-PERIOD u720) ;; ~5 days
(define-constant MIN-BID-AMOUNT u1000) ;; Minimum bid 1000 microSTX
(define-constant MIN-CONTRACTOR-RATING u70) ;; Minimum 70% rating

;; Data variables
(define-data-var bid-counter uint u0)

;; Data maps
(define-map contractors
    principal
    {
        name: (string-ascii 100),
        specialties: (list 5 (string-ascii 50)),
        rating: uint, ;; 0-100 scale
        completed-jobs: uint,
        is-verified: bool,
        join-date: uint
    }
)

(define-map project-bids
    uint ;; request-id
    {
        is-open: bool,
        deadline: uint,
        min-bid: uint,
        winning-bid: (optional uint),
        bid-count: uint
    }
)

(define-map bids
    { request-id: uint, contractor: principal }
    {
        amount: uint,
        timeline: uint, ;; completion timeline in blocks
        description: (string-ascii 300),
        submitted-at: uint,
        is-selected: bool
    }
)

;; Private functions
(define-private (is-contractor-qualified (contractor principal))
    (match (map-get? contractors contractor)
        contractor-data
            (and 
                (get is-verified contractor-data)
                (>= (get rating contractor-data) MIN-CONTRACTOR-RATING)
            )
        false
    )
)

;; Read-only functions
(define-read-only (get-contractor (contractor principal))
    (map-get? contractors contractor)
)

(define-read-only (get-project-bidding (request-id uint))
    (map-get? project-bids request-id)
)

(define-read-only (get-bid (request-id uint) (contractor principal))
    (map-get? bids { request-id: request-id, contractor: contractor })
)

;; Public functions
(define-public (register-contractor (name (string-ascii 100)) (specialties (list 5 (string-ascii 50))))
    (begin
        (map-set contractors tx-sender
            {
                name: name,
                specialties: specialties,
                rating: u80, ;; Start with good rating
                completed-jobs: u0,
                is-verified: false, ;; Would be verified by DAO
                join-date: block-height
            }
        )
        (ok true)
    )
)

(define-public (open-bidding (request-id uint) (min-bid uint))
    (begin
        (asserts! (> min-bid MIN-BID-AMOUNT) ERR-INVALID-AMOUNT)
        
        (map-set project-bids request-id
            {
                is-open: true,
                deadline: (+ block-height BIDDING-PERIOD),
                min-bid: min-bid,
                winning-bid: none,
                bid-count: u0
            }
        )
        
        (ok true)
    )
)

(define-public (submit-bid (request-id uint) (amount uint) (timeline uint) (description (string-ascii 300)))
    (let 
        (
            (bidding-info (unwrap! (map-get? project-bids request-id) ERR-BID-NOT-FOUND))
        )
        (asserts! (is-contractor-qualified tx-sender) ERR-NOT-QUALIFIED)
        (asserts! (get is-open bidding-info) ERR-BIDDING-CLOSED)
        (asserts! (<= block-height (get deadline bidding-info)) ERR-BIDDING-CLOSED)
        (asserts! (>= amount (get min-bid bidding-info)) ERR-INVALID-AMOUNT)
        
        ;; Submit bid
        (map-set bids 
            { request-id: request-id, contractor: tx-sender }
            {
                amount: amount,
                timeline: timeline,
                description: description,
                submitted-at: block-height,
                is-selected: false
            }
        )
        
        ;; Update bid count
        (map-set project-bids request-id
            (merge bidding-info {
                bid-count: (+ (get bid-count bidding-info) u1)
            })
        )
        
        (ok true)
    )
)

(define-public (select-winning-bid (request-id uint) (winning-contractor principal))
    (let 
        (
            (bidding-info (unwrap! (map-get? project-bids request-id) ERR-BID-NOT-FOUND))
            (winning-bid (unwrap! (map-get? bids { request-id: request-id, contractor: winning-contractor }) ERR-BID-NOT-FOUND))
        )
        ;; For simplicity, allow any caller - in production would be DAO governance
        (asserts! (> block-height (get deadline bidding-info)) ERR-BIDDING-CLOSED)
        
        ;; Mark bid as selected
        (map-set bids 
            { request-id: request-id, contractor: winning-contractor }
            (merge winning-bid { is-selected: true })
        )
        
        ;; Close bidding
        (map-set project-bids request-id
            (merge bidding-info {
                is-open: false,
                winning-bid: (some (get amount winning-bid))
            })
        )
        
        (ok winning-contractor)
    )
)

(define-public (complete-job (request-id uint))
    (let 
        (
            (bid-data (unwrap! (map-get? bids { request-id: request-id, contractor: tx-sender }) ERR-BID-NOT-FOUND))
            (contractor-data (unwrap! (map-get? contractors tx-sender) ERR-UNAUTHORIZED))
        )
        (asserts! (get is-selected bid-data) ERR-UNAUTHORIZED)
        
        ;; Update contractor stats
        (map-set contractors tx-sender
            (merge contractor-data {
                completed-jobs: (+ (get completed-jobs contractor-data) u1)
            })
        )
        
        (ok true)
    )
)


;; title: contractor-bidding
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

