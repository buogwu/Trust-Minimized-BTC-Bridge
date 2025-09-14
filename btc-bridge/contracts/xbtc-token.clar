;; xBTC Token Contract
;; Wrapped Bitcoin token for the Trust-Minimized BTC Bridge
;; Implements SIP-010 fungible token standard with bridge-specific functionality

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INSUFFICIENT_BALANCE (err u402))
(define-constant ERR_INVALID_AMOUNT (err u403))
(define-constant ERR_BRIDGE_NOT_SET (err u404))
(define-constant ERR_ALREADY_INITIALIZED (err u405))
(define-constant ERR_NOT_INITIALIZED (err u406))

;; Token definition
(define-fungible-token xbtc)

;; Data variables
(define-data-var token-name (string-ascii 32) "Wrapped Bitcoin")
(define-data-var token-symbol (string-ascii 10) "xBTC")
(define-data-var token-decimals uint u8)
(define-data-var bridge-contract (optional principal) none)
(define-data-var is-initialized bool false)
(define-data-var total-supply uint u0)

;; Data maps
(define-map authorized-minters principal bool)

;; Events
(define-data-var mint-events-nonce uint u0)
(define-data-var burn-events-nonce uint u0)

;; Private functions
(define-private (is-authorized-minter (sender principal))
  (or 
    (is-eq sender CONTRACT_OWNER)
    (match (var-get bridge-contract)
      bridge-addr (is-eq sender bridge-addr)
      false)
    (default-to false (map-get? authorized-minters sender))))

;; Public functions

;; Initialize the contract (can only be called once)
(define-public (initialize (bridge-addr principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (not (var-get is-initialized)) ERR_ALREADY_INITIALIZED)
    (var-set bridge-contract (some bridge-addr))
    (var-set is-initialized true)
    (ok true)))

;; Set bridge contract (only owner)
(define-public (set-bridge-contract (new-bridge principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set bridge-contract (some new-bridge))
    (ok true)))

;; Add authorized minter (only owner)
(define-public (add-authorized-minter (minter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-minters minter true)
    (ok true)))

;; Remove authorized minter (only owner)
(define-public (remove-authorized-minter (minter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-delete authorized-minters minter)
    (ok true)))

;; Mint tokens (only authorized minters)
(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (var-get is-initialized) ERR_NOT_INITIALIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-authorized-minter tx-sender) ERR_UNAUTHORIZED)
    
    ;; Mint tokens
    (try! (ft-mint? xbtc amount recipient))
    
    ;; Update total supply
    (var-set total-supply (+ (var-get total-supply) amount))
    
    ;; Increment mint events nonce
    (var-set mint-events-nonce (+ (var-get mint-events-nonce) u1))
    
    ;; Print mint event
    (print {
      event: "mint",
      nonce: (var-get mint-events-nonce),
      amount: amount,
      recipient: recipient,
      minter: tx-sender,
      block-height: stacks-block-height
    })
    
    (ok true)))

;; Burn tokens (only token holder or authorized minter)
(define-public (burn (amount uint) (holder principal))
  (begin
    (asserts! (var-get is-initialized) ERR_NOT_INITIALIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Check authorization: either the holder themselves or an authorized minter
    (asserts! (or 
      (is-eq tx-sender holder)
      (is-authorized-minter tx-sender)) ERR_UNAUTHORIZED)
    
    ;; Check sufficient balance
    (asserts! (>= (ft-get-balance xbtc holder) amount) ERR_INSUFFICIENT_BALANCE)
    
    ;; Burn tokens
    (try! (ft-burn? xbtc amount holder))
    
    ;; Update total supply
    (var-set total-supply (- (var-get total-supply) amount))
    
    ;; Increment burn events nonce
    (var-set burn-events-nonce (+ (var-get burn-events-nonce) u1))
    
    ;; Print burn event
    (print {
      event: "burn",
      nonce: (var-get burn-events-nonce),
      amount: amount,
      holder: holder,
      burner: tx-sender,
      block-height: stacks-block-height
    })
    
    (ok true)))

;; SIP-010 Standard Functions

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq tx-sender sender) (is-eq contract-caller sender)) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (ft-transfer? xbtc amount sender recipient)))

(define-read-only (get-name)
  (ok (var-get token-name)))

(define-read-only (get-symbol)
  (ok (var-get token-symbol)))

(define-read-only (get-decimals)
  (ok (var-get token-decimals)))

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance xbtc who)))

(define-read-only (get-total-supply)
  (ok (ft-get-supply xbtc)))

(define-read-only (get-token-uri)
  (ok none))

;; Additional read-only functions

(define-read-only (get-bridge-contract)
  (var-get bridge-contract))

(define-read-only (is-authorized-minter-read (minter principal))
  (is-authorized-minter minter))

(define-read-only (get-contract-info)
  {
    name: (var-get token-name),
    symbol: (var-get token-symbol),
    decimals: (var-get token-decimals),
    total-supply: (var-get total-supply),
    bridge-contract: (var-get bridge-contract),
    is-initialized: (var-get is-initialized)
  })

;; Emergency functions (only owner)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Implementation for pausing would go here
    ;; For now, just emit an event
    (print { event: "contract-paused", block-height: stacks-block-height })
    (ok true)))

(define-public (emergency-burn (amount uint) (holder principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (ft-get-balance xbtc holder) amount) ERR_INSUFFICIENT_BALANCE)
    
    (try! (ft-burn? xbtc amount holder))
    (var-set total-supply (- (var-get total-supply) amount))
    
    (print {
      event: "emergency-burn",
      amount: amount,
      holder: holder,
      block-height: stacks-block-height
    })
    
    (ok true)))
