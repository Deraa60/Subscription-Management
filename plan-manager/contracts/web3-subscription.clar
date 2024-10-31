;; Subscription Service Smart Contract
;; Description: A robust subscription management system with refunds and plan changes

;; Error codes
(define-constant ERROR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERROR-SUBSCRIPTION-EXISTS (err u101))
(define-constant ERROR-NO-ACTIVE-SUBSCRIPTION (err u102))
(define-constant ERROR-INSUFFICIENT-STX-BALANCE (err u103))
(define-constant ERROR-INVALID-SUBSCRIPTION-TYPE (err u104))
(define-constant ERROR-SUBSCRIPTION-EXPIRED (err u105))
(define-constant ERROR-INVALID-REFUND-AMOUNT (err u106))
(define-constant ERROR-SAME-PLAN-UPGRADE (err u107))
(define-constant ERROR-REFUND-PERIOD-EXPIRED (err u108))
(define-constant ERROR-INVALID-PLAN-CHANGE (err u109))

;; Data vars
(define-data-var service-administrator principal tx-sender)
(define-data-var base-subscription-cost uint u100)
(define-data-var default-subscription-period uint u2592000)
(define-data-var refund-period-limit uint u259200)  ;; 3 days in seconds
(define-data-var plan-change-fee uint u1000000)     ;; 1 STX fee for changing plans

;; Data maps
(define-map UserSubscriptionDetails
    principal
    {
        subscription-active: bool,
        subscription-start-timestamp: uint,
        subscription-end-timestamp: uint,
        current-subscription-plan: (string-ascii 20),
        last-payment-amount: uint,
        remaining-credit: uint
    }
)

(define-map SubscriptionPlanDetails
    (string-ascii 20)
    {
        plan-cost: uint,
        plan-duration: uint,
        plan-features: (list 10 (string-ascii 50)),
        plan-tier: uint,  ;; Higher number means higher tier
        allows-refunds: bool
    }
)

(define-map RefundHistory
    { user: principal, timestamp: uint }
    {
        refund-amount: uint,
        reason: (string-ascii 50)
    }
)

;; Read-only functions
(define-read-only (get-user-subscription-info (subscriber-address principal))
    (map-get? UserSubscriptionDetails subscriber-address)
)

(define-read-only (get-plan-details (subscription-plan-type (string-ascii 20)))
    (map-get? SubscriptionPlanDetails subscription-plan-type)
)

(define-read-only (calculate-remaining-time (subscriber-address principal))
    (let (
        (subscription (unwrap! (map-get? UserSubscriptionDetails subscriber-address) u0))
    )
    (if (get subscription-active subscription)
        (- (get subscription-end-timestamp subscription) block-height)
        u0
    ))
)

(define-read-only (calculate-refund-amount (subscriber-address principal))
    (let (
        (subscription (unwrap! (map-get? UserSubscriptionDetails subscriber-address) u0))
        (time-elapsed (- block-height (get subscription-start-timestamp subscription)))
        (subscription-length (- (get subscription-end-timestamp subscription) (get subscription-start-timestamp subscription)))
        (original-payment (get last-payment-amount subscription))
    )
    (if (> time-elapsed (var-get refund-period-limit))
        u0
        (/ (* original-payment (- subscription-length time-elapsed)) subscription-length)
    ))
)

;; Private functions
(define-private (verify-administrator-access)
    (is-eq tx-sender (var-get service-administrator))
)

(define-private (process-refund (user principal) (refund-amount uint) (refund-reason (string-ascii 50)))
    (begin
        (try! (stx-transfer? refund-amount (var-get service-administrator) user))
        (map-set RefundHistory
            { user: user, timestamp: block-height }
            {
                refund-amount: refund-amount,
                reason: refund-reason
            }
        )
        (ok true)
    )
)

;; Function for creating subscription plans
(define-public (create-subscription-plan 
    (plan-type (string-ascii 20))
    (cost uint)
    (duration uint)
    (features (list 10 (string-ascii 50)))
    (tier uint)
    (refundable bool))
    (begin
        (asserts! (verify-administrator-access) ERROR-UNAUTHORIZED-ACCESS)
        (ok (map-set SubscriptionPlanDetails
            plan-type
            {
                plan-cost: cost,
                plan-duration: duration,
                plan-features: features,
                plan-tier: tier,
                allows-refunds: refundable
            }
        ))
    )
)

;; Public functions for plan management
(define-public (purchase-subscription (selected-plan-type (string-ascii 20)))
    (let (
        (plan-info (unwrap! (map-get? SubscriptionPlanDetails selected-plan-type) ERROR-INVALID-SUBSCRIPTION-TYPE))
        (current-block-height block-height)
        (subscription-cost (get plan-cost plan-info))
        (existing-subscription (get-user-subscription-info tx-sender))
    )
    ;; Check if subscription exists - if it's none (not found), we can proceed
    (asserts! (is-none existing-subscription) ERROR-SUBSCRIPTION-EXISTS)
    (try! (stx-transfer? subscription-cost tx-sender (var-get service-administrator)))
    
    (ok (map-set UserSubscriptionDetails
        tx-sender
        {
            subscription-active: true,
            subscription-start-timestamp: current-block-height,
            subscription-end-timestamp: (+ current-block-height (get plan-duration plan-info)),
            current-subscription-plan: selected-plan-type,
            last-payment-amount: subscription-cost,
            remaining-credit: u0
        }
    ))
))

(define-public (request-refund (refund-reason (string-ascii 50)))
    (let (
        (subscription (unwrap! (map-get? UserSubscriptionDetails tx-sender) ERROR-NO-ACTIVE-SUBSCRIPTION))
        (plan-info (unwrap! (map-get? SubscriptionPlanDetails (get current-subscription-plan subscription)) ERROR-INVALID-SUBSCRIPTION-TYPE))
        (refund-amount (calculate-refund-amount tx-sender))
    )
    (asserts! (get subscription-active subscription) ERROR-NO-ACTIVE-SUBSCRIPTION)
    (asserts! (get allows-refunds plan-info) ERROR-INVALID-REFUND-AMOUNT)
    (asserts! (> refund-amount u0) ERROR-INVALID-REFUND-AMOUNT)
    
    (try! (process-refund tx-sender refund-amount refund-reason))
    
    (ok (map-set UserSubscriptionDetails
        tx-sender
        {
            subscription-active: false,
            subscription-start-timestamp: (get subscription-start-timestamp subscription),
            subscription-end-timestamp: block-height,
            current-subscription-plan: (get current-subscription-plan subscription),
            last-payment-amount: u0,
            remaining-credit: u0
        }
    ))
))

(define-public (upgrade-subscription-plan (new-plan-type (string-ascii 20)))
    (begin
        (let (
            (current-subscription (unwrap! (map-get? UserSubscriptionDetails tx-sender) ERROR-NO-ACTIVE-SUBSCRIPTION))
            (current-plan (unwrap! (map-get? SubscriptionPlanDetails (get current-subscription-plan current-subscription)) ERROR-INVALID-SUBSCRIPTION-TYPE))
            (new-plan (unwrap! (map-get? SubscriptionPlanDetails new-plan-type) ERROR-INVALID-SUBSCRIPTION-TYPE))
            (remaining-time (calculate-remaining-time tx-sender))
            (remaining-value (* (get last-payment-amount current-subscription) (/ remaining-time (get plan-duration current-plan))))
        )
        (asserts! (get subscription-active current-subscription) ERROR-NO-ACTIVE-SUBSCRIPTION)
        (asserts! (> (get plan-tier new-plan) (get plan-tier current-plan)) ERROR-INVALID-PLAN-CHANGE)
        (asserts! (not (is-eq new-plan-type (get current-subscription-plan current-subscription))) ERROR-SAME-PLAN-UPGRADE)
        
        (let (
            (upgrade-cost (- (get plan-cost new-plan) remaining-value))
        )
        (try! (stx-transfer? (+ upgrade-cost (var-get plan-change-fee)) tx-sender (var-get service-administrator)))
        
        (ok (map-set UserSubscriptionDetails
            tx-sender
            {
                subscription-active: true,
                subscription-start-timestamp: block-height,
                subscription-end-timestamp: (+ block-height (get plan-duration new-plan)),
                current-subscription-plan: new-plan-type,
                last-payment-amount: (get plan-cost new-plan),
                remaining-credit: u0
            }
        ))
    ))
))

(define-public (downgrade-subscription-plan (new-plan-type (string-ascii 20)))
    (begin
        (let (
            (current-subscription (unwrap! (map-get? UserSubscriptionDetails tx-sender) ERROR-NO-ACTIVE-SUBSCRIPTION))
            (current-plan (unwrap! (map-get? SubscriptionPlanDetails (get current-subscription-plan current-subscription)) ERROR-INVALID-SUBSCRIPTION-TYPE))
            (new-plan (unwrap! (map-get? SubscriptionPlanDetails new-plan-type) ERROR-INVALID-SUBSCRIPTION-TYPE))
            (remaining-time (calculate-remaining-time tx-sender))
        )
        (asserts! (get subscription-active current-subscription) ERROR-NO-ACTIVE-SUBSCRIPTION)
        (asserts! (< (get plan-tier new-plan) (get plan-tier current-plan)) ERROR-INVALID-PLAN-CHANGE)
        
        (let (
            (remaining-value (* (get last-payment-amount current-subscription) (/ remaining-time (get plan-duration current-plan))))
            (credit-amount (- remaining-value (get plan-cost new-plan)))
        )
        (try! (stx-transfer? (var-get plan-change-fee) tx-sender (var-get service-administrator)))
        
        (ok (map-set UserSubscriptionDetails
            tx-sender
            {
                subscription-active: true,
                subscription-start-timestamp: block-height,
                subscription-end-timestamp: (+ block-height (get plan-duration new-plan)),
                current-subscription-plan: new-plan-type,
                last-payment-amount: (get plan-cost new-plan),
                remaining-credit: credit-amount
            }
        ))
    ))
))

;; Admin functions
(define-public (set-refund-period (new-period uint))
    (begin
        (asserts! (verify-administrator-access) ERROR-UNAUTHORIZED-ACCESS)
        (ok (var-set refund-period-limit new-period))
    )
)

(define-public (set-plan-change-fee (new-fee uint))
    (begin
        (asserts! (verify-administrator-access) ERROR-UNAUTHORIZED-ACCESS)
        (ok (var-set plan-change-fee new-fee))
    )
)

;; Initial contract setup
(begin
    ;; Add default subscription plans
    (try! (create-subscription-plan
        "basic-tier"  ;; Basic tier plan
        u50000000  ;; 50 STX
        u2592000   ;; 30 days
        (list 
            "Basic Platform Access"
            "Standard Customer Support"
            "Core Feature Set"
        )
        u1  ;; Tier 1
        true ;; Allows refunds
    ))
    
    (try! (create-subscription-plan
        "premium-tier"  ;; Premium tier plan
        u100000000  ;; 100 STX
        u2592000    ;; 30 days
        (list 
            "Premium Platform Access"
            "24/7 Priority Support"
            "Complete Feature Set"
            "Advanced Analytics Dashboard"
        )
        u2  ;; Tier 2
        true ;; Allows refunds
    ))
)