# Trust-Minimized-BTC-Bridge

A decentralized bridge solution to bring Bitcoin onto Stacks without relying on centralized custodians, enabling truly trustless Bitcoin DeFi on the Stacks blockchain.

## 🎯 Core Concept

This project implements a federated bridge model using Clarity smart contracts to manage a distributed network of "wardens" - independent entities that collectively control Bitcoin custody through multi-signature or Threshold Signature Scheme (TSS) wallets. The system eliminates single points of failure while maintaining security through economic incentives and cryptographic guarantees.

## 🏗️ Architecture Overview

### Federated Warden Model
- **Distributed Control**: Geographically and politically distributed wardens collectively manage Bitcoin custody
- **Multi-Signature Security**: Bitcoin funds are secured by multi-sig wallets requiring consensus from multiple wardens
- **Threshold Signature Schemes**: Advanced cryptographic techniques ensure no single warden can unilaterally access funds

### Mint/Burn Mechanism
1. **Lock BTC**: Users deposit Bitcoin into the multi-signature wallet controlled by wardens
2. **Verification**: Wardens verify the Bitcoin transaction on-chain
3. **Mint xBTC**: Upon consensus, the Clarity contract mints equivalent wrapped Bitcoin (xBTC) on Stacks
4. **Burn & Release**: Reverse process burns xBTC to release native Bitcoin back to users

### Economic Security
- **Staking Requirements**: Wardens must stake STX tokens as collateral
- **Slashing Conditions**: Malicious behavior or prolonged offline periods result in stake slashing
- **Reputation System**: Performance tracking ensures only reliable wardens maintain active status

## 📋 Current Implementation Status

### ✅ Completed Features

#### Warden Management Contract (`warden-management.clar`)

The foundational contract for managing the warden network with comprehensive governance and security features:

**Core Functionality:**
- **Warden Registration**: Allows entities to register as wardens with STX stake and Bitcoin public keys
- **Stake Management**: Handles minimum stake requirements (1000 STX) and stake transfers
- **Activation System**: Contract owner can activate pending wardens during initial bootstrap phase
- **Activity Tracking**: Records warden participation in bridge operations

**Security & Governance:**
- **Slashing Mechanism**: Multi-warden voting system to slash misbehaving wardens
- **Vote Tracking**: Prevents double voting and ensures fair slash proposals
- **Reputation Scoring**: Maintains warden reputation scores for network health
- **Time-locked Voting**: 24-hour voting periods for slash proposals

**Access Control:**
- **Status Management**: Tracks warden states (Pending, Active, Suspended, Slashed)
- **Threshold Updates**: Dynamic signature threshold adjustment based on active wardens
- **Stake Withdrawal**: Allows non-active wardens to withdraw remaining stake

## 🔧 Technical Specifications

### Contract Constants
- **Minimum Stake**: 1,000 STX (1,000,000,000 microSTX)
- **Maximum Wardens**: 21 participants
- **Default Signature Threshold**: 3 wardens required for operations
- **Slashing Rate**: 20% of staked amount for confirmed violations
- **Voting Period**: 144 blocks (~24 hours) for slash proposals

### Warden States
| State | Value | Description |
|-------|-------|-------------|
| Pending | 0 | Newly registered, awaiting activation |
| Active | 1 | Participating in bridge operations |
| Suspended | 2 | Temporarily inactive |
| Slashed | 3 | Penalized for misconduct |

### Key Functions

#### Registration & Management
```clarity
(register-warden (btc-pubkey (buff 33)) (stake-amount uint))
(activate-warden (warden principal))
(update-warden-activity (warden principal))
```

#### Governance & Slashing
```clarity
(propose-slash-warden (target-warden principal) (reason (string-ascii 256)))
(vote-slash-warden (target-warden principal))
(update-signature-threshold (new-threshold uint))
```

#### Queries
```clarity
(get-warden-info (warden principal))
(is-active-warden (warden principal))
(get-active-wardens)
```

## 🚀 Getting Started

### Prerequisites
- Stacks blockchain development environment
- Clarinet CLI tool for contract testing and deployment
- Minimum 1,000 STX for warden registration

### Deployment
1. Update `CONTRACT-OWNER` constant to your deployer principal
2. Deploy the contract using Clarinet:
   ```bash
   clarinet deploy
   ```
3. Register initial wardens and activate them to bootstrap the network

### Testing
```bash
clarinet test
clarinet console
```

## 🛣️ Roadmap

### Phase 2: Bridge Core Logic
- [ ] Bitcoin transaction verification
- [ ] xBTC token contract implementation
- [ ] Multi-signature wallet integration
- [ ] Cross-chain communication protocol

### Phase 3: Advanced Features
- [ ] Threshold Signature Scheme (TSS) integration
- [ ] Automated warden selection algorithms
- [ ] Fee distribution mechanisms
- [ ] Emergency pause/recovery procedures

### Phase 4: Production Hardening
- [ ] Security audits and formal verification
- [ ] Mainnet deployment and warden onboarding
- [ ] Monitoring and alerting systems
- [ ] Documentation and developer tools

## 🔒 Security Considerations

- **Economic Security**: Wardens risk significant STX stake for misbehavior
- **Cryptographic Security**: Multi-signature requirements prevent single points of failure
- **Operational Security**: Activity tracking and slashing ensure network liveness
- **Governance Security**: Time-locked voting prevents rushed decisions

## 🤝 Contributing

This project represents critical infrastructure for Bitcoin DeFi on Stacks. Contributions are welcome in areas including:
- Security auditing and testing
- Performance optimizations
- Additional governance mechanisms
- Integration with Bitcoin infrastructure
- Documentation improvements

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🙏 Acknowledgments

This project aims to solve one of the most challenging problems in cross-chain infrastructure - creating a truly decentralized bridge for Bitcoin. The success of this system would represent a monumental achievement for the Stacks ecosystem and Bitcoin DeFi as a whole.
