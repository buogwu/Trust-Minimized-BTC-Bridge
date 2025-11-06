;; xBTC Mint/Burn Mechanism
;; Wrapped Bitcoin token with warden-coordinated mint/burn operations

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-ALREADY-PROCESSED (err u103))
(define-constant ERR-NOT-ENOUGH-CONFIRMATIONS (err u104))
(define-constant ERR-INVALID-WARDEN (err u105))

(define-fungible-token xbtc)

;; Configuration
(define-data-var contract-owner principal tx-sender)
(define-data-var required-confirmations uint u3)
(define-data-var min-mint-amount uint u100000) ;; 0.001 BTC in satoshis

;; Warden registry
(define-map wardens principal { is-active: bool, joined-at: uint })

;; Mint requests tracking
(define-map mint-requests
    { btc-txid: (buff 32) }
    {
        recipient: principal,
        amount: uint,
        confirmations: uint,
        processed: bool,
        created-at: uint
    }
)

;; Warden confirmations for mint requests
(define-map warden-confirmations
    { btc-txid: (buff 32), warden: principal }
    { confirmed: bool, confirmed-at: uint }
)

;; Burn requests tracking
(define-map burn-requests
    uint
    {
        requester: principal,
        amount: uint,
        btc-address: (string-ascii 64),
        processed: bool,
        created-at: uint
    }
)

(define-data-var burn-nonce uint u0)

;; Read-only functions

(define-read-only (get-name)
    (ok "Wrapped Bitcoin")
)

(define-read-only (get-symbol)
    (ok "xBTC")
)

(define-read-only (get-decimals)
    (ok u8)
)

(define-read-only (get-balance (account principal))
    (ok (ft-get-balance xbtc account))
)

(define-read-only (get-total-supply)
    (ok (ft-get-supply xbtc))
)

(define-read-only (is-warden (address principal))
    (match (map-get? wardens address)
        warden-info (get is-active warden-info)
        false
    )
)

(define-read-only (get-mint-request (btc-txid (buff 32)))
    (map-get? mint-requests { btc-txid: btc-txid })
)

(define-read-only (get-burn-request (nonce uint))
    (map-get? burn-requests nonce)
)

(define-read-only (has-warden-confirmed (btc-txid (buff 32)) (warden principal))
    (match (map-get? warden-confirmations { btc-txid: btc-txid, warden: warden })
        confirmation (get confirmed confirmation)
        false
    )
)

;; Public functions - Token transfers

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
        (try! (ft-transfer? xbtc amount sender recipient))
        (match memo to-print (print to-print) 0x)
        (ok true)
    )
)

;; Admin functions

(define-public (add-warden (warden principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-set wardens warden {
            is-active: true,
            joined-at: stacks-block-height
        })
        (ok warden)
    )
)

(define-public (remove-warden (warden principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (match (map-get? wardens warden)
            warden-info
            (begin
                (map-set wardens warden (merge warden-info { is-active: false }))
                (ok warden)
            )
            ERR-INVALID-WARDEN
        )
    )
)

(define-public (set-required-confirmations (count uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> count u0) ERR-INVALID-AMOUNT)
        (var-set required-confirmations count)
        (ok count)
    )
)

;; Mint flow

(define-public (request-mint (btc-txid (buff 32)) (recipient principal) (amount uint))
    (let ((existing (get-mint-request btc-txid)))
        (asserts! (is-warden tx-sender) ERR-INVALID-WARDEN)
        (asserts! (>= amount (var-get min-mint-amount)) ERR-INVALID-AMOUNT)
        (asserts! (is-none existing) ERR-ALREADY-PROCESSED)
        
        (map-set mint-requests { btc-txid: btc-txid } {
            recipient: recipient,
            amount: amount,
            confirmations: u1,
            processed: false,
            created-at: stacks-block-height
        })
        
        (map-set warden-confirmations 
            { btc-txid: btc-txid, warden: tx-sender }
            { confirmed: true, confirmed-at: stacks-block-height }
        )
        
        (ok btc-txid)
    )
)

(define-public (confirm-mint (btc-txid (buff 32)))
    (let (
        (request (unwrap! (get-mint-request btc-txid) ERR-INVALID-AMOUNT))
        (already-confirmed (has-warden-confirmed btc-txid tx-sender))
    )
        (asserts! (is-warden tx-sender) ERR-INVALID-WARDEN)
        (asserts! (not (get processed request)) ERR-ALREADY-PROCESSED)
        (asserts! (not already-confirmed) ERR-ALREADY-PROCESSED)
        
        (let ((new-confirmations (+ (get confirmations request) u1)))
            (map-set mint-requests { btc-txid: btc-txid }
                (merge request { confirmations: new-confirmations })
            )
            
            (map-set warden-confirmations
                { btc-txid: btc-txid, warden: tx-sender }
                { confirmed: true, confirmed-at: stacks-block-height }
            )
            
            (ok new-confirmations)
        )
    )
)

(define-public (execute-mint (btc-txid (buff 32)))
    (let (
        (request (unwrap! (get-mint-request btc-txid) ERR-INVALID-AMOUNT))
    )
        (asserts! (is-warden tx-sender) ERR-INVALID-WARDEN)
        (asserts! (not (get processed request)) ERR-ALREADY-PROCESSED)
        (asserts! (>= (get confirmations request) (var-get required-confirmations)) ERR-NOT-ENOUGH-CONFIRMATIONS)
        
        (try! (ft-mint? xbtc (get amount request) (get recipient request)))
        
        (map-set mint-requests { btc-txid: btc-txid }
            (merge request { processed: true })
        )
        
        (ok (get amount request))
    )
)

;; Burn flow

(define-public (request-burn (amount uint) (btc-address (string-ascii 64)))
    (let ((nonce (var-get burn-nonce)))
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (ft-get-balance xbtc tx-sender) amount) ERR-INSUFFICIENT-BALANCE)
        
        (try! (ft-burn? xbtc amount tx-sender))
        
        (map-set burn-requests nonce {
            requester: tx-sender,
            amount: amount,
            btc-address: btc-address,
            processed: false,
            created-at: stacks-block-height
        })
        
        (var-set burn-nonce (+ nonce u1))
        (ok nonce)
    )
)

(define-public (mark-burn-processed (nonce uint))
    (let (
        (request (unwrap! (get-burn-request nonce) ERR-INVALID-AMOUNT))
    )
        (asserts! (is-warden tx-sender) ERR-INVALID-WARDEN)
        (asserts! (not (get processed request)) ERR-ALREADY-PROCESSED)
        
        (map-set burn-requests nonce
            (merge request { processed: true })
        )
        
        (ok nonce)
    )
)