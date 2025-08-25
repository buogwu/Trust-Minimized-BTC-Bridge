;; Trust-Minimized BTC Bridge - Warden Management Contract
;; Manages the registration, staking, and governance of bridge wardens

;; -----------------
;; Constants / Errors
;; -----------------
;; REPLACE THIS with your admin principal (the deployer/owner you want).
(define-constant CONTRACT-OWNER tx-sender) ;; Set to deployer

(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_WARDEN (err u101))
(define-constant ERR_NOT_WARDEN (err u102))
(define-constant ERR_INSUFFICIENT_STAKE (err u103))
(define-constant ERR_INVALID_STATUS (err u104))
(define-constant ERR_WARDEN_NOT_ACTIVE (err u105))
(define-constant ERR_INVALID_THRESHOLD (err u106))
(define-constant ERR_SLASHING_IN_PROGRESS (err u107))
(define-constant ERR_MAX_WARDENS (err u108))
(define-constant ERR_NO_PENDING_SLASH (err u109))
(define-constant ERR_VOTING_CLOSED (err u110))

;; Minimum stake required to become a warden (1000 STX) in micro-STX
(define-constant MIN_WARDEN_STAKE u1000000000)

;; Maximum number of wardens allowed
(define-constant MAX-WARDENS u21)

;; Warden status constants
(define-constant WARDEN-STATUS-PENDING u0)
(define-constant WARDEN-STATUS-ACTIVE u1)
(define-constant WARDEN-STATUS-SUSPENDED u2)
(define-constant WARDEN-STATUS-SLASHED u3)

;; -----------------
;; Data Vars
;; -----------------
(define-data-var warden-count uint u0)
(define-data-var active-warden-count uint u0)
(define-data-var signature-threshold uint u3)
(define-data-var total-staked-amount uint u0)

;; -----------------
;; Data Maps
;; -----------------
(define-map wardens principal {
  status: uint,
  stake-amount: uint,
  btc-public-key: (buff 33),
  registration-height: uint,
  last-activity-height: uint,
  slash-votes: uint,
  reputation-score: uint
})

(define-map warden-list uint principal)
(define-map warden-indices principal uint)

(define-map pending-slashes principal {
  proposer: principal,
  reason: (string-ascii 256),
  votes: uint,
  target-height: uint
})

;; Track which wardens have voted on each slash proposal
(define-map slash-votes { target: principal, voter: principal } bool)

;; -----------------
;; Helpers
;; -----------------
(define-private (contract-principal)
  ;; Returns the contract's principal for safe transfers.
  (as-contract tx-sender)
)

;; -----------------
;; Public Functions
;; -----------------

;; Register as a warden with STX stake and BTC public key
(define-public (register-warden (btc-pubkey (buff 33)) (stake-amount uint))
  (let (
    (caller tx-sender)
    (current-count (var-get warden-count))
  )
    (asserts! (>= stake-amount MIN_WARDEN_STAKE) ERR_INSUFFICIENT_STAKE)
    (asserts! (< current-count MAX-WARDENS) ERR_MAX_WARDENS)
    (asserts! (is-none (map-get? wardens caller)) ERR_ALREADY_WARDEN)

    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount caller (contract-principal)))

    ;; Register warden
    (map-set wardens caller {
      status: WARDEN-STATUS-PENDING,
      stake-amount: stake-amount,
      btc-public-key: btc-pubkey,
      registration-height: stacks-block-height,
      last-activity-height: stacks-block-height,
      slash-votes: u0,
      reputation-score: u100
    })

    (map-set warden-list current-count caller)
    (map-set warden-indices caller current-count)
    (var-set warden-count (+ current-count u1))
    (var-set total-staked-amount (+ (var-get total-staked-amount) stake-amount))

    (print { event: "warden-registered", warden: caller, stake: stake-amount })
    (ok true)
  )
)

;; Activate a pending warden (only contract owner during initial phase)
(define-public (activate-warden (warden principal))
  (let (
    (w (unwrap! (map-get? wardens warden) ERR_NOT_WARDEN))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status w) WARDEN-STATUS-PENDING) ERR_INVALID_STATUS)

    (map-set wardens warden (merge w { status: WARDEN-STATUS-ACTIVE }))
    (var-set active-warden-count (+ (var-get active-warden-count) u1))

    (print { event: "warden-activated", warden: warden })
    (ok true)
  )
)

;; Update warden activity (called during bridge operations)
(define-public (update-warden-activity (warden principal))
  (let (
    (w (unwrap! (map-get? wardens warden) ERR_NOT_WARDEN))
  )
    (asserts! (is-eq (get status w) WARDEN-STATUS-ACTIVE) ERR_WARDEN_NOT_ACTIVE)

    (map-set wardens warden (merge w { last-activity-height: stacks-block-height }))
    (ok true)
  )
)

;; Propose slashing a warden for misconduct
(define-public (propose-slash-warden (target-warden principal) (reason (string-ascii 256)))
  (let (
    (caller tx-sender)
    (caller-data (unwrap! (map-get? wardens caller) ERR_NOT_WARDEN))
    (target-data (unwrap! (map-get? wardens target-warden) ERR_NOT_WARDEN))
    (slash-height (+ stacks-block-height u144)) ;; ~24 hours for voting (assuming ~10-minute blocks)
  )
    (asserts! (is-eq (get status caller-data) WARDEN-STATUS-ACTIVE) ERR_WARDEN_NOT_ACTIVE)
    (asserts! (is-eq (get status target-data) WARDEN-STATUS-ACTIVE) ERR_INVALID_STATUS)
    (asserts! (is-none (map-get? pending-slashes target-warden)) ERR_SLASHING_IN_PROGRESS)

    (map-set pending-slashes target-warden {
      proposer: caller,
      reason: reason,
      votes: u1,
      target-height: slash-height
    })

    ;; Record that proposer has voted
    (map-set slash-votes { target: target-warden, voter: caller } true)

    (print { event: "slash-proposed", target: target-warden, proposer: caller, reason: reason })
    (ok true)
  )
)

(define-public (vote-slash-warden (target-warden principal))
  (let (
    (caller tx-sender)
    (caller-data (unwrap! (map-get? wardens caller) ERR_NOT_WARDEN))
    (slash-data (unwrap! (map-get? pending-slashes target-warden) ERR_NO_PENDING_SLASH))
    (current-votes (get votes slash-data))
    (vote-key { target: target-warden, voter: caller })
  )
    (asserts! (is-eq (get status caller-data) WARDEN-STATUS-ACTIVE) ERR_WARDEN_NOT_ACTIVE)
    (asserts! (<= stacks-block-height (get target-height slash-data)) ERR_VOTING_CLOSED)
    (asserts! (is-none (map-get? slash-votes vote-key)) ERR_UNAUTHORIZED) ;; Already voted

    ;; Record vote
    (map-set slash-votes vote-key true)
    
    ;; Update vote count
    (map-set pending-slashes target-warden 
      (merge slash-data { votes: (+ current-votes u1) }))

    ;; If votes reach threshold, execute slash
    (if (>= (+ current-votes u1) u3) ;; Example: 3 votes needed
      (begin
        (try! (execute-slash target-warden))
        (ok true))
      (ok true)
    )
  )
)

;; Execute slashing of a warden
(define-private (execute-slash (target-warden principal))
  (let (
    (w (unwrap! (map-get? wardens target-warden) ERR_NOT_WARDEN))
    (stake-amount (get stake-amount w))
    (slash-amount (/ (* stake-amount u20) u100)) ;; 20% slash
  )
    ;; Update warden status and reduce stake
    (map-set wardens target-warden 
      (merge w { 
        status: WARDEN-STATUS-SLASHED,
        stake-amount: (- stake-amount slash-amount)
      }))

    ;; Update counters and totals
    (var-set active-warden-count (- (var-get active-warden-count) u1))
    (var-set total-staked-amount (- (var-get total-staked-amount) slash-amount))

    ;; Clean up pending slash
    (map-delete pending-slashes target-warden)

    (print { event: "warden-slashed", warden: target-warden, amount: slash-amount })
    (ok true)
  )
)

;; Withdraw stake (only for non-active wardens)
(define-public (withdraw-stake)
  (let (
    (caller tx-sender)
    (w (unwrap! (map-get? wardens caller) ERR_NOT_WARDEN))
    (stake-amount (get stake-amount w))
    (status (get status w))
  )
    (asserts! (or (is-eq status WARDEN-STATUS-SUSPENDED)
                  (is-eq status WARDEN-STATUS-SLASHED)) ERR_INVALID_STATUS)

    ;; Transfer remaining stake back to warden from contract principal
    (try! (as-contract (stx-transfer? stake-amount tx-sender caller)))

    ;; Remove warden data
    (map-delete wardens caller)
    (var-set total-staked-amount (- (var-get total-staked-amount) stake-amount))

    (print { event: "stake-withdrawn", warden: caller, amount: stake-amount })
    (ok true)
  )
)

;; Update signature threshold (governance function)
(define-public (update-signature-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR_UNAUTHORIZED)
    (asserts! (and (> new-threshold u0)
                   (<= new-threshold (var-get active-warden-count))) ERR_INVALID_THRESHOLD)

    (var-set signature-threshold new-threshold)
    (print { event: "threshold-updated", new-threshold: new-threshold })
    (ok true)
  )
)

;; -----------------
;; Read-only functions
;; -----------------

(define-read-only (get-warden-info (warden principal))
  (map-get? wardens warden)
)

(define-read-only (get-warden-by-index (index uint))
  (map-get? warden-list index)
)

(define-read-only (is-active-warden (warden principal))
  (match (map-get? wardens warden)
    warden-data (is-eq (get status warden-data) WARDEN-STATUS-ACTIVE)
    false
  )
)

(define-read-only (get-active-warden-count)
  (var-get active-warden-count)
)

(define-read-only (get-signature-threshold)
  (var-get signature-threshold)
)

(define-read-only (get-total-staked-amount)
  (var-get total-staked-amount)
)

(define-read-only (get-pending-slash (warden principal))
  (map-get? pending-slashes warden)
)

;; Get list of all active wardens (scans indices 0..20)
(define-read-only (get-active-wardens)
  (fold get-active-wardens-iter
        (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20)
        (list))
)

(define-private (get-active-wardens-iter (index uint) (acc (list 21 principal)))
  (match (map-get? warden-list index)
    warden
      (if (is-active-warden warden)
          (unwrap! (as-max-len? (append acc warden) u21) acc)
          acc)
    acc)
)

;; Check if a warden has voted on a slash proposal
(define-read-only (has-voted-on-slash (target principal) (voter principal))
  (is-some (map-get? slash-votes { target: target, voter: voter }))
)