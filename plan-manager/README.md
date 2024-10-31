# Subscription Service Smart Contract

## Overview
A robust and feature-rich subscription management system implemented in Clarity for the Stacks blockchain. This smart contract enables businesses to manage subscription-based services with features including multiple subscription tiers, upgrades/downgrades, and refund capabilities.

## Features

### Core Functionality
- Multiple subscription tiers (Basic, Premium)
- Flexible subscription duration management
- Automatic subscription status tracking
- Pro-rated calculations for plan changes
- Comprehensive refund system

### Subscription Management
- Purchase new subscriptions
- Upgrade to higher tiers
- Downgrade to lower tiers with credit
- Early termination with refunds
- Subscription renewal

### Administrative Features
- Plan creation and management
- Fee adjustment capabilities
- Refund period configuration
- Contract ownership transfer
- Subscription monitoring

## Contract Structure

### Core Data Structures

#### UserSubscriptionDetails
```clarity
{
    subscription-active: bool,
    subscription-start-timestamp: uint,
    subscription-end-timestamp: uint,
    current-subscription-plan: (string-utf8 20),
    last-payment-amount: uint,
    remaining-credit: uint
}
```

#### SubscriptionPlanDetails
```clarity
{
    plan-cost: uint,
    plan-duration: uint,
    plan-features: (list 10 (string-utf8 50)),
    plan-tier: uint,
    allows-refunds: bool
}
```

### For Administrators

1. Create New Subscription Plan
```clarity
(contract-call? .subscription-service create-subscription-plan 
    "enterprise-tier"
    u200000000
    u2592000
    (list "Enterprise Features" "24/7 Support" "Custom Integration")
    u3
    true
)
```

2. Adjust Refund Period
```clarity
(contract-call? .subscription-service set-refund-period u259200)  ;; 3 days
```

## Administrative Functions

| Function | Description | Access |
|----------|-------------|--------|
| create-subscription-plan | Creates new subscription tier | Admin Only |
| set-refund-period | Updates refund eligibility period | Admin Only |
| set-plan-change-fee | Updates fee for plan changes | Admin Only |
| transfer-admin-rights | Transfers contract ownership | Admin Only |

## Error Handling

| Error Code | Description | Solution |
|------------|-------------|----------|
| ERROR-UNAUTHORIZED-ACCESS | Non-admin accessing protected function | Use admin account |
| ERROR-SUBSCRIPTION-EXISTS | Already has active subscription | Cancel existing first |
| ERROR-NO-ACTIVE-SUBSCRIPTION | No active subscription found | Purchase subscription |
| ERROR-INSUFFICIENT-STX-BALANCE | Insufficient funds | Add more STX |
| ERROR-INVALID-SUBSCRIPTION-TYPE | Invalid plan selected | Check plan name |
| ERROR-SUBSCRIPTION-EXPIRED | Subscription has expired | Renew subscription |
| ERROR-INVALID-REFUND-AMOUNT | Invalid refund calculation | Check eligibility |
| ERROR-SAME-PLAN-UPGRADE | Attempting to upgrade to same plan | Select different plan |
| ERROR-REFUND-PERIOD-EXPIRED | Outside refund window | Contact support |
| ERROR-INVALID-PLAN-CHANGE | Invalid upgrade/downgrade path | Check plan tiers |

## Security Considerations

1. Access Control
   - Administrative functions protected by owner checks
   - User-specific data protected by principal checks
   - Proper error handling for unauthorized access

2. Financial Safety
   - Pro-rated calculations for refunds
   - Protected fund transfers
   - Balance verification before transactions

3. Data Integrity
   - Proper state management
   - Validation of all inputs
   - Protection against invalid state transitions