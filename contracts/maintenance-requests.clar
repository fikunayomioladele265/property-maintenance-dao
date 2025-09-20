;; Maintenance Requests Contract
;; Submit and prioritize property maintenance requests from residents

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-REQUEST-NOT-FOUND (err u402))
(define-constant ERR-INVALID-STATUS (err u403))
(define-constant ERR-ALREADY-VOTED (err u404))
(define-constant ERR-INVALID-PRIORITY (err u405))

;; Constants
(define-constant MAX-DESCRIPTION-LENGTH u500)
(define-constant VOTING-PERIOD u1008) ;; ~7 days
(define-constant MIN-VOTES-THRESHOLD u3)

;; Data variables
(define-data-var request-counter uint u0)
(define-data-var total-requests uint u0)

;; Data maps
(define-map maintenance-requests
    uint ;; request-id
    {
        requester: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        priority: uint, ;; 1-5 scale
        category: (string-ascii 50),
        status: (string-ascii 20), ;; "pending", "approved", "in-progress", "completed", "rejected"
        votes-for: uint,
        votes-against: uint,
        created-at: uint,
        updated-at: uint,
        estimated-cost: (optional uint),
        assigned-contractor: (optional principal)
    }
)

(define-map request-votes
    { request-id: uint, voter: principal }
    { vote: bool, timestamp: uint }
)

(define-map resident-profiles
    principal
    {
        unit-number: (string-ascii 10),
        is-verified: bool,
        voting-power: uint,
        requests-submitted: uint,
        join-date: uint
    }
)

;; Private functions
(define-private (get-next-request-id)
    (let ((current-id (var-get request-counter)))
        (var-set request-counter (+ current-id u1))
        (+ current-id u1)
    )
)

(define-private (is-valid-priority (priority uint))
    (and (>= priority u1) (<= priority u5))
)

(define-private (calculate-request-score (request-id uint))
    (match (map-get? maintenance-requests request-id)
        request-data
            (let 
                (
                    (votes-for (get votes-for request-data))
                    (votes-against (get votes-against request-data))
                    (priority (get priority request-data))
                )
                (+ (* votes-for u10) (* priority u5) (- u0 (* votes-against u5)))
            )
        u0
    )
)

;; Read-only functions
(define-read-only (get-request (request-id uint))
    (map-get? maintenance-requests request-id)
)

(define-read-only (get-resident-profile (resident principal))
    (map-get? resident-profiles resident)
)

(define-read-only (get-vote (request-id uint) (voter principal))
    (map-get? request-votes { request-id: request-id, voter: voter })
)

(define-read-only (get-request-score (request-id uint))
    (calculate-request-score request-id)
)

(define-read-only (get-total-requests)
    (var-get total-requests)
)

;; Public functions
(define-public (register-resident (unit-number (string-ascii 10)))
    (begin
        (map-set resident-profiles tx-sender
            {
                unit-number: unit-number,
                is-verified: false, ;; Would be verified by property management
                voting-power: u1,
                requests-submitted: u0,
                join-date: block-height
            }
        )
        (ok true)
    )
)

(define-public (submit-request (title (string-ascii 100)) (description (string-ascii 500)) (priority uint) (category (string-ascii 50)))
    (let 
        (
            (request-id (get-next-request-id))
            (resident-profile (map-get? resident-profiles tx-sender))
        )
        (asserts! (is-some resident-profile) ERR-UNAUTHORIZED)
        (asserts! (is-valid-priority priority) ERR-INVALID-PRIORITY)
        
        ;; Create maintenance request
        (map-set maintenance-requests request-id
            {
                requester: tx-sender,
                title: title,
                description: description,
                priority: priority,
                category: category,
                status: "pending",
                votes-for: u0,
                votes-against: u0,
                created-at: block-height,
                updated-at: block-height,
                estimated-cost: none,
                assigned-contractor: none
            }
        )
        
        ;; Update resident stats
        (match resident-profile
            profile
                (map-set resident-profiles tx-sender
                    (merge profile {
                        requests-submitted: (+ (get requests-submitted profile) u1)
                    })
                )
            true
        )
        
        ;; Update global stats
        (var-set total-requests (+ (var-get total-requests) u1))
        
        (ok request-id)
    )
)

(define-public (vote-on-request (request-id uint) (support bool))
    (let 
        (
            (request-data (unwrap! (map-get? maintenance-requests request-id) ERR-REQUEST-NOT-FOUND))
            (resident-profile (unwrap! (map-get? resident-profiles tx-sender) ERR-UNAUTHORIZED))
            (existing-vote (map-get? request-votes { request-id: request-id, voter: tx-sender }))
        )
        (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
        (asserts! (get is-verified resident-profile) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status request-data) "pending") ERR-INVALID-STATUS)
        
        ;; Record vote
        (map-set request-votes 
            { request-id: request-id, voter: tx-sender }
            { vote: support, timestamp: block-height }
        )
        
        ;; Update vote counts
        (let 
            (
                (voting-power (get voting-power resident-profile))
                (new-votes-for 
                    (if support 
                        (+ (get votes-for request-data) voting-power)
                        (get votes-for request-data)
                    )
                )
                (new-votes-against
                    (if support
                        (get votes-against request-data)
                        (+ (get votes-against request-data) voting-power)
                    )
                )
            )
            (map-set maintenance-requests request-id
                (merge request-data {
                    votes-for: new-votes-for,
                    votes-against: new-votes-against,
                    updated-at: block-height
                })
            )
        )
        
        (ok true)
    )
)

(define-public (update-request-status (request-id uint) (new-status (string-ascii 20)))
    (let 
        (
            (request-data (unwrap! (map-get? maintenance-requests request-id) ERR-REQUEST-NOT-FOUND))
        )
        ;; For simplicity, allow requester to update status
        ;; In production, this would have proper authorization
        (asserts! (is-eq tx-sender (get requester request-data)) ERR-UNAUTHORIZED)
        
        (map-set maintenance-requests request-id
            (merge request-data {
                status: new-status,
                updated-at: block-height
            })
        )
        
        (ok true)
    )
)

(define-public (assign-contractor (request-id uint) (contractor principal) (estimated-cost uint))
    (let 
        (
            (request-data (unwrap! (map-get? maintenance-requests request-id) ERR-REQUEST-NOT-FOUND))
        )
        ;; For simplicity, allow requester to assign contractor
        ;; In production, this would be handled by contractor-bidding contract
        (asserts! (is-eq tx-sender (get requester request-data)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status request-data) "approved") ERR-INVALID-STATUS)
        
        (map-set maintenance-requests request-id
            (merge request-data {
                assigned-contractor: (some contractor),
                estimated-cost: (some estimated-cost),
                status: "in-progress",
                updated-at: block-height
            })
        )
        
        (ok true)
    )
)

(define-public (complete-request (request-id uint))
    (let 
        (
            (request-data (unwrap! (map-get? maintenance-requests request-id) ERR-REQUEST-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get requester request-data)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status request-data) "in-progress") ERR-INVALID-STATUS)
        
        (map-set maintenance-requests request-id
            (merge request-data {
                status: "completed",
                updated-at: block-height
            })
        )
        
        (ok true)
    )
)


;; title: maintenance-requests
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

