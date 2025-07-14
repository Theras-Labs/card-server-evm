# Boltis Game Server - Smart Contract

Boltis is an on-chain multiplayer card game built on Ethereum. This repository contains the Solidity smart contract that powers the game logic for the Boltis card game.

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

The main contract `BoltisGame.sol` implements the core game logic with the following key components:

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
   npm install
   ```

## Testing

Run the test suite:

```bash
npx hardhat test
```

## Deployment

To deploy to a testnet or mainnet:

1. Configure your environment variables in `.env`
2. Run the deployment script:
   ```bash
   npx hardhat run scripts/deploy.js --network <network-name>
   ```

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

## Security Considerations

- Uses OpenZeppelin's ReentrancyGuard for security
- Implements timeouts to prevent stalled games
- Includes emergency functions for game management

## License

MIT
