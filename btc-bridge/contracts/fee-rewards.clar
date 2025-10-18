;; BTC Bridge - Fee Economics & Warden Rewards
;; Manages bridge fees, warden compensation, and protocol sustainability

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-INSUFFICIENT-FUNDS (err u301))
(define-constant ERR-INVALID-AMOUNT (err u302))
(define-constant ERR-NO-PENDING-REWARDS (err u303))

;; Fee structure (in basis points: 100 = 1%)
(define-data-var bridge-fee-basis-points uint u50)
(define-data-var warden-reward-basis-points uint u30)
(define-data-var protocol-fee-basis-points uint u20)

;; Treasury and rewards tracking
(define-data-var protocol-treasury uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var total-warden-rewards uint u0)

;; Per-warden reward tracking
(define-map warden-pending-rewards principal uint)
(define-map warden-total-earned principal uint)

;; Fee history for audits
(define-map bridge-txns uint {
  sender: principal,
  amount: uint,
  fee-charged: uint,
  timestamp: uint
})

(define-data-var txn-counter uint u0)

;; Read-only functions
(define-read-only (get-bridge-fee)
  (var-get bridge-fee-basis-points)
)

(define-read-only (get-warden-reward-percentage)
  (var-get warden-reward-basis-points)
)

(define-read-only (get-protocol-fee-percentage)
  (var-get protocol-fee-basis-points)
)

(define-read-only (get-protocol-treasury)
  (var-get protocol-treasury)
)

(define-read-only (get-total-fees-collected)
  (var-get total-fees-collected)
)

(define-read-only (calculate-bridge-fee (amount uint))
  (/ (* amount (var-get bridge-fee-basis-points)) u10000)
)

(define-read-only (calculate-warden-reward (total-fee uint))
  (/ (* total-fee (var-get warden-reward-basis-points)) u100)
)

(define-read-only (calculate-protocol-fee (total-fee uint))
  (/ (* total-fee (var-get protocol-fee-basis-points)) u100)
)

(define-read-only (get-warden-pending-reward (warden principal))
  (default-to u0 (map-get? warden-pending-rewards warden))
)

(define-read-only (get-warden-total-earned (warden principal))
  (default-to u0 (map-get? warden-total-earned warden))
)

(define-read-only (get-txn-record (txn-id uint))
  (map-get? bridge-txns txn-id)
)

;; Public functions

;; Process bridge transaction and collect fees
(define-public (process-bridge-txn (sender principal) (amount uint))
  (let ((fee (calculate-bridge-fee amount))
        (warden-reward (calculate-warden-reward fee))
        (protocol-fee (calculate-protocol-fee fee))
        (txn-id (var-get txn-counter)))
    
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Record transaction
    (map-set bridge-txns txn-id {
      sender: sender,
      amount: amount,
      fee-charged: fee,
      timestamp: stacks-block-height
    })
    
    ;; Update totals
    (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
    (var-set protocol-treasury (+ (var-get protocol-treasury) protocol-fee))
    (var-set txn-counter (+ txn-id u1))
    
    (ok {
      transaction-fee: fee,
      warden-share: warden-reward,
      protocol-share: protocol-fee
    })
  )
)

;; Distribute warden rewards across active wardens
(define-public (distribute-warden-rewards (reward-amount uint) (warden-list (list 21 principal)))
  (let ((warden-count (len warden-list))
        (per-warden-share (if (> warden-count u0)
                              (/ reward-amount warden-count)
                              u0)))
    
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (> reward-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> warden-count u0) ERR-INVALID-AMOUNT)
    
    ;; Update each warden's pending rewards
    (map distribute-reward-to-warden warden-list)
    (var-set total-warden-rewards (+ (var-get total-warden-rewards) reward-amount))
    
    (ok {
      total-distributed: reward-amount,
      warden-count: (len warden-list),
      per-warden-amount: per-warden-share
    })
  )
)

;; Helper to distribute reward to single warden
(define-private (distribute-reward-to-warden (warden principal))
  (let ((current-pending (default-to u0 (map-get? warden-pending-rewards warden)))
        (current-total (default-to u0 (map-get? warden-total-earned warden))))
    
    (map-set warden-pending-rewards warden (+ current-pending u1))
    (map-set warden-total-earned warden (+ current-total u1))
  )
)

;; Warden claims their pending rewards
(define-public (claim-warden-reward)
  (let ((warden tx-sender)
        (pending (default-to u0 (map-get? warden-pending-rewards warden))))
    
    (asserts! (> pending u0) ERR-NO-PENDING-REWARDS)
    (asserts! (<= pending (var-get protocol-treasury)) ERR-INSUFFICIENT-FUNDS)
    
    ;; Clear pending rewards
    (map-set warden-pending-rewards warden u0)
    
    ;; Deduct from treasury
    (var-set protocol-treasury (- (var-get protocol-treasury) pending))
    
    ;; Transfer to warden
    (try! (stx-transfer? pending (as-contract tx-sender) warden))
    
    (ok {
      warden: warden,
      amount-claimed: pending
    })
  )
)

;; Update fee parameters (governance)
(define-public (update-bridge-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= new-fee u500) ERR-INVALID-AMOUNT)
    
    (var-set bridge-fee-basis-points new-fee)
    (ok new-fee)
  )
)

(define-public (update-warden-reward-percentage (new-percentage uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (and (>= new-percentage u10) (<= new-percentage u50)) ERR-INVALID-AMOUNT)
    
    (var-set warden-reward-basis-points new-percentage)
    (ok new-percentage)
  )
)

(define-public (update-protocol-fee-percentage (new-percentage uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (and (>= new-percentage u10) (<= new-percentage u50)) ERR-INVALID-AMOUNT)
    
    (var-set protocol-fee-basis-points new-percentage)
    (ok new-percentage)
  )
)

;; Withdraw protocol treasury (governance)
(define-public (withdraw-protocol-treasury (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= amount (var-get protocol-treasury)) ERR-INSUFFICIENT-FUNDS)
    
    (var-set protocol-treasury (- (var-get protocol-treasury) amount))
    (try! (stx-transfer? amount (as-contract tx-sender) recipient))
    
    (ok amount)
  )
)