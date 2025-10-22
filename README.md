# Decentralized Stablecoin (DSC) Protocol

![Solidity](https://img.shields.io/badge/Solidity-v0.8.19-blue)
![Foundry](https://img.shields.io/badge/Foundry-Framework-red)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-Contracts-green)
![Chainlink](https://img.shields.io/badge/Chainlink-Oracles-blue)

A decentralized, algorithmic stablecoin protocol built on Ethereum that maintains a $1.00 USD peg through overcollateralization with crypto assets.

## 🎯 Business Case & Purpose

The Decentralized Stablecoin (DSC) protocol addresses the need for a truly decentralized, stable digital currency that:

- **Maintains Price Stability**: Anchored to $1.00 USD through algorithmic mechanisms
- **Ensures Decentralization**: No governance tokens, no fees, purely algorithmic
- **Provides Capital Efficiency**: Users can leverage their crypto holdings while maintaining exposure
- **Guarantees Transparency**: All operations are on-chain and verifiable
- **Offers Censorship Resistance**: No central authority can freeze or control the system

### Key Value Propositions

1. **For DeFi Users**: Stable medium of exchange without centralized risks
2. **For Crypto Holders**: Ability to access liquidity without selling assets
3. **For Developers**: Reliable stable token for DeFi integrations
4. **For Institutions**: Transparent, auditable monetary system

## 🏗️ Protocol Architecture

### Core Properties

- **Relative Stability**: Anchored/Pegged to $1.00 USD
- **Stability Mechanism**: Algorithmic (Decentralized) - no governance
- **Collateral Type**: Exogenous (External Crypto Assets)
- **Collateralization**: Always overcollateralized (>150% ratio)

### Supported Collateral

- **wETH** (Wrapped Ethereum)
- **wBTC** (Wrapped Bitcoin)

### Similar to MakerDAO DAI but:

- ❌ No governance
- ❌ No fees
- ❌ Only WETH & WBTC collateral
- ✅ Purely algorithmic
- ✅ Minimal design

## 🛠️ Technologies Used

### Smart Contract Stack

- **Solidity ^0.8.19** - Smart contract development
- **Foundry** - Development framework, testing, and deployment
- **OpenZeppelin Contracts** - Security-audited contract libraries
- **Chainlink Price Feeds** - Reliable price oracles

### Key Dependencies

- **ERC20Burnable** - Token standard with burn functionality
- **ReentrancyGuard** - Protection against reentrancy attacks
- **AggregatorV3Interface** - Chainlink price feed integration

### Development Tools

- **Forge** - Testing and compilation
- **Anvil** - Local blockchain simulation
- **Cast** - Command-line tool for Ethereum

## 📋 Prerequisites

- [Git](https://git-scm.com/)
- [Node.js](https://nodejs.org/) (v16+ recommended)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/foundry-stablecoin.git
cd foundry-stablecoin
```

### 2. Install Dependencies

```bash
forge install
```

### 3. Set Up Environment Variables

```bash
cp .env.example .env
# Edit .env with your configuration
```

### 4. Compile Contracts

```bash
forge build
```

### 5. Run Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testDepositCollateral
```

### 6. Deploy Locally

```bash
# Start local blockchain
anvil

# Deploy to local network
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

## 🔧 Configuration

### Network Configuration

The protocol supports multiple networks through `HelperConfig.s.sol`:

- **Local (Anvil)**: Uses mock price feeds and tokens
- **Sepolia Testnet**: Uses real Chainlink price feeds
- **Mainnet**: Production deployment (configure carefully)

### Key Parameters

- **Liquidation Threshold**: 50% (200% collateralization required)
- **Liquidation Bonus**: 10% bonus for liquidators
- **Min Health Factor**: 1e18 (1.0)
- **Precision**: 1e18 (18 decimal places)

## 📊 Core Functionality

### For Users

1. **Deposit Collateral**: Deposit wETH or wBTC as collateral
2. **Mint DSC**: Create DSC tokens against collateral (max 50% of collateral value)
3. **Burn DSC**: Repay DSC to reduce debt
4. **Redeem Collateral**: Withdraw collateral after burning DSC

### For Liquidators

1. **Liquidate**: Liquidate undercollateralized positions for 10% bonus

### Key Functions

```solidity
// Deposit collateral and mint DSC in one transaction
function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)

// Burn DSC and redeem collateral in one transaction
function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)

// Liquidate undercollateralized positions
function liquidate(address collateral, address user, uint256 debtToCover)
```

## 🧪 Testing

### Test Categories

```bash
# Unit Tests
forge test --match-path "test/unit/*"

# Integration Tests
forge test --match-path "test/integration/*"

# Invariant/Fuzz Tests
forge test --match-path "test/fuzz/*"
```

### Key Invariants

1. **Protocol must always be overcollateralized**
2. **Users can't mint more DSC than their collateral allows**
3. **Liquidations maintain system health**

### Gas Optimization

```bash
# Gas report
forge test --gas-report

# Gas snapshots
forge snapshot
```

## 🚀 Deployment

### Testnet Deployment (Sepolia)

```bash
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

### Mainnet Deployment

```bash
forge script script/DeployDSC.s.sol --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

## 🔐 Security Considerations

### Implemented Security Measures

- ✅ **Reentrancy Protection**: ReentrancyGuard on all state-changing functions
- ✅ **Oracle Security**: Chainlink price feeds with staleness checks
- ✅ **Health Factor Checks**: Prevents undercollateralization
- ✅ **Input Validation**: Comprehensive parameter validation
- ✅ **Emergency Liquidation**: Automated liquidation system

### Audit Status

⚠️ **This code is for educational purposes and has not been audited. Do not use in production without proper security audit.**

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Solidity style guide
- Write comprehensive tests
- Update documentation
- Ensure all tests pass

## 📚 Additional Resources

- [Foundry Documentation](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Chainlink Price Feeds](https://docs.chain.link/data-feeds/price-feeds)
- [MakerDAO Documentation](https://docs.makerdao.com/)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This software is provided "as is", without warranty of any kind. The authors are not responsible for any damages or losses. Always conduct thorough testing and audits before deploying to mainnet.

---

**Built with ❤️ by Anton using Foundry**
