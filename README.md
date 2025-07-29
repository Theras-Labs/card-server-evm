# Boltis Game Server - Smart Contract

Boltis is an on-chain multiplayer card game built on Ethereum. This repository contains the Solidity smart contracts that power the game logic for the Boltis card game, including the core game mechanics and mock ERC20 tokens for testing.

## Overview

Boltis is a strategic card game for 2-4 players (humans or bots) where players take turns playing cards to deplete their hand. The game features different card elements, special abilities, and interactive gameplay mechanics.

## Game Features

- **Multiplayer Support**: Play with 2-4 players (human or AI)
- **Card Elements**: Fire, Water, Plant, and Thunder elements with unique interactions
- **Card Types**: Number cards and special cards (Skip, Reverse, Stack, Void)
- **Game Modes**: Stack mode (destroy or move cards)
- **Turn-based Gameplay**: With configurable time limits
- **Bot Players**: AI opponents with configurable difficulty

## Smart Contract Architecture

The project consists of several key contracts:

### Core Game Contracts (contracts/boltisV2/)
- **MatchRegistry.sol**: Central registry for creating and managing game matches
- **GameMatch.sol**: Individual match instance for 4-player card games
- **SessionKeyManager.sol**: Manages session keys for gasless transactions
- **GameLogicLibrary.sol**: Core game logic and utilities

### Mock ERC20 Tokens (contracts/)
- **MockERC20.sol**: Base mock ERC20 token with minting capabilities
- **MockUSDC.sol**: Mock USD Coin (6 decimals) with faucet function
- **MockUSDT.sol**: Mock Tether USD (6 decimals) with faucet function
- **MockBoltisToken.sol**: Mock Boltis game token (18 decimals) for rewards

The main game logic is implemented through the following key components:

### Key Components

- **Game State Management**: Tracks all active games, players, and game state
- **Card System**: Manages the deck, hand, and discard pile
- **Turn Management**: Handles player turns, timeouts, and game flow
- **Special Card Effects**: Implements unique behaviors for special cards
- **Bot Logic**: AI for non-human players

### Game Flow

1. **Game Creation**: A player creates a new game with custom settings
2. **Player Join**: Other players join the game
3. **Game Start**: Game begins when minimum players (2) join
4. **Gameplay**: Players take turns playing cards or drawing
5. **Winning**: First player to empty their hand wins

## Contract Interfaces

### Key Functions

- `createGame(playerName, settings)`: Create a new game
- `joinGame(gameId, playerName)`: Join an existing game
- `playCard(gameId, cardId)`: Play a card from your hand
- `drawCard(gameId)`: Draw a card from the deck
- `selectColor(gameId, color)`: Select color after playing a Void card
- `handleTimeout(gameId, playerIndex)`: Handle player timeout

### Events

- `GameCreated`: Emitted when a new game is created
- `PlayerJoined`: When a player joins a game
- `GameStarted`: When a game begins
- `CardPlayed`: When a card is played
- `CardDrawn`: When a card is drawn
- `GameEnded`: When a game concludes

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/boltis-contracts.git
   cd boltis-contracts
   ```

2. Install dependencies:
   ```bash
   yarn install
   ```

## Testing

Run the test suite:

```bash
yarn hardhat test
```

## Deployment

The project includes comprehensive deployment scripts for different scenarios:

### Available Deployment Scripts

1. **Full Deployment** - Deploys all contracts:
   ```bash
   yarn deploy
   # or for specific networks
   yarn deploy:localhost
   yarn deploy:testnet
   yarn deploy:mainnet
   ```

2. **Core Contracts Only** - Deploys game logic contracts:
   ```bash
   yarn deploy:core
   ```

3. **Mock Tokens Only** - Deploys ERC20 test tokens:
   ```bash
   yarn deploy:tokens
   ```

4. **Contract Verification** - Verifies deployed contracts on block explorer:
   ```bash
   yarn verify
   ```

5. **Environment Setup** - Sets up development environment with test data:
   ```bash
   yarn setup
   ```

### Manual Deployment

To deploy to a specific network manually:

1. Configure your environment variables in `.env`:
   ```env
   PRIVATE_KEY=your_private_key
   ETHERSCAN_API_KEY=your_etherscan_api_key
   INFURA_PROJECT_ID=your_infura_project_id
   ```

2. Run the deployment script:
   ```bash
   yarn hardhat run scripts/deploy.ts --network <network-name>
   ```

### Deployment Output

All deployment scripts save contract addresses and configuration to the `deployments/` directory:
- `{network}-deployment.json` - Full deployment info
- `{network}-core.json` - Core contracts only
- `{network}-tokens.json` - Mock tokens only
- `{network}-config.json` - Environment configuration

## Game Rules

### Card Types

1. **Number Cards (1-9)**: Play on matching number or element
2. **Skip**: Next player loses their turn
3. **Reverse**: Reverse turn direction
4. **Stack**: Remove matching element cards from play
5. **Void**: Wild card that lets you choose the next color

### Element Interactions

- Fire beats Plant
- Water beats Fire
- Plant beats Water
- Thunder beats Plant

## Mock ERC20 Tokens

The project includes several mock ERC20 tokens for testing and development:

### MockERC20
Base implementation with:
- Configurable name, symbol, and decimals
- Owner-only minting and burning
- Batch minting capabilities

### MockUSDC
- Symbol: USDC
- Decimals: 6
- Initial Supply: 1,000,000 USDC
- Faucet: Anyone can mint up to 1,000 USDC per call

### MockUSDT
- Symbol: USDT
- Decimals: 6
- Initial Supply: 1,000,000 USDT
- Faucet: Anyone can mint up to 1,000 USDT per call

### MockBoltisToken
- Symbol: BOLTIS
- Decimals: 18
- Initial Supply: 10,000,000 BOLTIS
- Faucet: Anyone can mint up to 100 BOLTIS per call
- Reward function for game contracts

## Security Considerations

- Uses OpenZeppelin's ReentrancyGuard for security
- Implements timeouts to prevent stalled games
- Includes emergency functions for game management
- Session key management for gasless transactions
- Clone pattern for gas-efficient match deployment

## License

MIT
