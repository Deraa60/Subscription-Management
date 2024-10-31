;; Subscription Service Smart Contract
;; Description: A robust subscription management system implemented in Clarity

;; Error codes
(define-constant ERROR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERROR-SUBSCRIPTION-EXISTS (err u101))
(define-constant ERROR-NO-ACTIVE-SUBSCRIPTION (err u102))
(define-constant ERROR-INSUFFICIENT-STX-BALANCE (err u103))
(define-constant ERROR-INVALID-SUBSCRIPTION-TYPE (err u104))
(define-constant ERROR-SUBSCRIPTION-EXPIRED (err u105))

;; Data vars
(define-data-var service-administrator principal tx-sender)
(define-data-var base-subscription-cost uint u100)     ;; in microSTX
(define-data-var default-subscription-period uint u2592000)  ;; 30 days in seconds

;; Data maps
(define-map UserSubscriptionDetails
    principal
    {
        subscription-active: bool,
        subscription-start-timestamp: uint,
        subscription-end-timestamp: uint,
        current-subscription-plan: (string-utf8 20)
    }
)

(define-map SubscriptionPlanDetails
    (string-utf8 20)
    {
        plan-cost: uint,
        plan-duration: uint,
        plan-features: (list 10 (string-utf8 50))
    }
)

;; Read-only functions
(define-read-only (get-user-subscription-info (subscriber-address principal))
    (map-get? UserSubscriptionDetails subscriber-address)
)

(define-read-only (get-plan-details (subscription-plan-type (string-utf8 20)))
    (map-get? SubscriptionPlanDetails subscription-plan-type)
)

(define-read-only (check-subscription-status (subscriber-address principal))
    (let (
        (user-subscription (map-get? UserSubscriptionDetails subscriber-address))
    )
    (if (is-some user-subscription)
        (let (
            (subscription-info (unwrap-panic user-subscription))
        )
        (and 
            (get subscription-active subscription-info)
            (< block-height (get subscription-end-timestamp subscription-info))
        ))
        false
    ))
)

;; Public functions
(define-public (purchase-subscription (selected-plan-type (string-utf8 20)))
    (let (
        (plan-info (unwrap! (map-get? SubscriptionPlanDetails selected-plan-type) ERROR-INVALID-SUBSCRIPTION-TYPE))
        (current-block-height block-height)
        (subscription-cost (get plan-cost plan-info))
    )
    (asserts! (not (check-subscription-status tx-sender)) ERROR-SUBSCRIPTION-EXISTS)
    (try! (stx-transfer? subscription-cost tx-sender (var-get service-administrator)))
    
    (ok (map-set UserSubscriptionDetails
        tx-sender
        {
            subscription-active: true,
            subscription-start-timestamp: current-block-height,
            subscription-end-timestamp: (+ current-block-height (get plan-duration plan-info)),
            current-subscription-plan: selected-plan-type
        }
    )))
)

(define-public (terminate-subscription)
    (let (
        (user-subscription (unwrap! (map-get? UserSubscriptionDetails tx-sender) ERROR-NO-ACTIVE-SUBSCRIPTION))
    )
    (asserts! (get subscription-active user-subscription) ERROR-NO-ACTIVE-SUBSCRIPTION)
    
    (ok (map-set UserSubscriptionDetails
        tx-sender
        {
            subscription-active: false,
            subscription-start-timestamp: (get subscription-start-timestamp user-subscription),
            subscription-end-timestamp: block-height,
            current-subscription-plan: (get current-subscription-plan user-subscription)
        }
    )))
)

(define-public (extend-subscription)
    (let (
        (user-subscription (unwrap! (map-get? UserSubscriptionDetails tx-sender) ERROR-NO-ACTIVE-SUBSCRIPTION))
        (plan-info (unwrap! (map-get? SubscriptionPlanDetails (get current-subscription-plan user-subscription)) ERROR-INVALID-SUBSCRIPTION-TYPE))
    )
    (try! (stx-transfer? (get plan-cost plan-info) tx-sender (var-get service-administrator)))
    
    (ok (map-set UserSubscriptionDetails
        tx-sender
        {
            subscription-active: true,
            subscription-start-timestamp: block-height,
            subscription-end-timestamp: (+ block-height (get plan-duration plan-info)),
            current-subscription-plan: (get current-subscription-plan user-subscription)
        }
    )))
)

;; Admin functions
(define-public (create-subscription-plan 
    (plan-type (string-utf8 20)) 
    (plan-cost uint) 
    (plan-duration uint) 
    (plan-features (list 10 (string-utf8 50)))
)
    (begin
        (asserts! (is-eq tx-sender (var-get service-administrator)) ERROR-UNAUTHORIZED-ACCESS)
        
        (ok (map-set SubscriptionPlanDetails
            plan-type
            {
                plan-cost: plan-cost,
                plan-duration: plan-duration,
                plan-features: plan-features
            }
        ))
    )
)

(define-public (update-base-subscription-cost (updated-cost uint))
    (begin
        (asserts! (is-eq tx-sender (var-get service-administrator)) ERROR-UNAUTHORIZED-ACCESS)
        (ok (var-set base-subscription-cost updated-cost))
    )
)

(define-public (transfer-admin-rights (new-administrator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get service-administrator)) ERROR-UNAUTHORIZED-ACCESS)
        (ok (var-set service-administrator new-administrator))
    )
)

;; Private functions
(define-private (verify-administrator-access)
    (is-eq tx-sender (var-get service-administrator))
)

;; Initial contract setup
(begin
    ;; Add default subscription plans
    (try! (create-subscription-plan
        "basic-tier"
        u50000000  ;; 50 STX
        u2592000   ;; 30 days
        (list 
            "Basic Platform Access"
            "Standard Customer Support"
            "Core Feature Set"
        )
    ))
    
    (try! (create-subscription-plan
        "premium-tier"
        u100000000  ;; 100 STX
        u2592000    ;; 30 days
        (list 
            "Premium Platform Access"
            "24/7 Priority Support"
            "Complete Feature Set"
            "Advanced Analytics Dashboard"
        )
    ))
)