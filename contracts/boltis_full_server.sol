// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title BoltisGame - Multiplayer Card Game Smart Contract
 * @dev Handles multiple concurrent Boltis card games with full game logic
 */
contract BoltisGame is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    
    // ================================
    // ENUMS & STRUCTS
    // ================================
    
    enum ElementType { Fire, Water, Plant, Thunder }
    enum CardType { Number, Skip, Reverse, Stack, Void }
    enum GamePhase { Waiting, Playing, ColorSelection, Ended }
    enum PlayerType { Human, Bot }
    
    struct Card {
        uint8 id;
        ElementType element;
        CardType cardType;
        uint8 value; // 1-9 for number cards, 0 for special cards
    }
    
    struct Player {
        address playerAddress;
        string name;
        PlayerType playerType;
        uint8[] hand; // Array of card IDs
        bool isActive;
        uint256 lastActionTime;
        uint16 score;
    }
    
    struct GameSettings {
        uint16 turnTimeLimit; // seconds
        uint8 timeoutPenaltyCards;
        uint16 minDecisionTime; // milliseconds for bots
        uint16 maxDecisionTime; // milliseconds for bots
        bool showBotCards;
        bool stackModeDestroy; // true = destroy, false = move
    }
    
    struct GameState {
        uint256 gameId;
        Player[4] players;
        uint8 currentPlayerIndex;
        int8 direction; // 1 or -1
        uint8[] discardPile;
        uint8[] drawPile;
        uint8 topCard;
        GamePhase phase;
        bool skipNext;
        bool voidActive;
        ElementType pendingColorSelection;
        uint256 gameStartTime;
        uint8 humanPlayerCount;
        GameSettings settings;
        address winner;
        bool gameExists;
        uint256 lastMoveTime;
    }
    
    // ================================
    // STATE VARIABLES
    // ================================
    
    Counters.Counter private _gameIdCounter;
    
    // Game ID => Game State
    mapping(uint256 => GameState) public games;
    
    // Player address => Game ID (0 if not in game)
    mapping(address => uint256) public playerToGame;
    
    // Game ID => Player addresses
    mapping(uint256 => address[4]) public gameToPlayers;
    
    // Waiting games queue
    uint256[] public waitingGames;
    
    // Card definitions (108 total cards)
    Card[108] public cardDefinitions;
    
    // Constants
    uint256 public constant TURN_TIMEOUT = 15 seconds;
    uint256 public constant GAME_TIMEOUT = 1 hours;
    uint8 public constant CARDS_PER_PLAYER = 7;
    
    // ================================
    // EVENTS
    // ================================
    
    event GameCreated(uint256 indexed gameId, address indexed creator);
    event PlayerJoined(uint256 indexed gameId, address indexed player, uint8 playerIndex);
    event GameStarted(uint256 indexed gameId);
    event CardPlayed(uint256 indexed gameId, address indexed player, uint8 cardId);
    event CardDrawn(uint256 indexed gameId, address indexed player, uint8 cardId);
    event ColorSelected(uint256 indexed gameId, ElementType color);
    event TurnChanged(uint256 indexed gameId, uint8 newPlayerIndex);
    event GameEnded(uint256 indexed gameId, address indexed winner);
    event PlayerTimeout(uint256 indexed gameId, address indexed player);
    
    // ================================
    // CONSTRUCTOR
    // ================================
    
    constructor() {
        _initializeCardDefinitions();
    }
    
    // ================================
    // MODIFIERS
    // ================================
    
    modifier gameExists(uint256 gameId) {
        require(games[gameId].gameExists, "Game does not exist");
        _;
    }
    
    modifier playerInGame(uint256 gameId) {
        require(playerToGame[msg.sender] == gameId, "Player not in this game");
        _;
    }
    
    modifier gamePhase(uint256 gameId, GamePhase expectedPhase) {
        require(games[gameId].phase == expectedPhase, "Invalid game phase");
        _;
    }
    
    modifier isPlayerTurn(uint256 gameId) {
        GameState storage game = games[gameId];
        require(
            game.players[game.currentPlayerIndex].playerAddress == msg.sender,
            "Not your turn"
        );
        _;
    }
    
    // ================================
    // GAME CREATION & JOINING
    // ================================
    
    /**
     * @dev Create a new game
     */
    function createGame(
        string memory playerName,
        GameSettings memory settings
    ) external nonReentrant returns (uint256) {
        require(playerToGame[msg.sender] == 0, "Already in a game");
        require(bytes(playerName).length > 0, "Invalid player name");
        
        _gameIdCounter.increment();
        uint256 gameId = _gameIdCounter.current();
        
        GameState storage game = games[gameId];
        game.gameId = gameId;
        game.gameExists = true;
        game.phase = GamePhase.Waiting;
        game.settings = settings;
        game.humanPlayerCount = 1;
        game.lastMoveTime = block.timestamp;
        
        // Add creator as first player
        game.players[0] = Player({
            playerAddress: msg.sender,
            name: playerName,
            playerType: PlayerType.Human,
            hand: new uint8[](0),
            isActive: true,
            lastActionTime: block.timestamp,
            score: 0
        });
        
        gameToPlayers[gameId][0] = msg.sender;
        playerToGame[msg.sender] = gameId;
        waitingGames.push(gameId);
        
        emit GameCreated(gameId, msg.sender);
        emit PlayerJoined(gameId, msg.sender, 0);
        
        return gameId;
    }
    
    /**
     * @dev Join an existing waiting game
     */
    function joinGame(uint256 gameId, string memory playerName) 
        external 
        nonReentrant 
        gameExists(gameId) 
        gamePhase(gameId, GamePhase.Waiting) 
    {
        require(playerToGame[msg.sender] == 0, "Already in a game");
        require(bytes(playerName).length > 0, "Invalid player name");
        
        GameState storage game = games[gameId];
        require(game.humanPlayerCount < 4, "Game is full");
        
        uint8 playerIndex = game.humanPlayerCount;
        
        game.players[playerIndex] = Player({
            playerAddress: msg.sender,
            name: playerName,
            playerType: PlayerType.Human,
            hand: new uint8[](0),
            isActive: true,
            lastActionTime: block.timestamp,
            score: 0
        });
        
        gameToPlayers[gameId][playerIndex] = msg.sender;
        playerToGame[msg.sender] = gameId;
        game.humanPlayerCount++;
        
        emit PlayerJoined(gameId, msg.sender, playerIndex);
        
        // Auto-start game when enough players join
        if (game.humanPlayerCount >= 2) {
            _fillWithBots(gameId);
            _startGame(gameId);
        }
    }
    
    /**
     * @dev Join any available game or create one
     */
    function quickJoin(string memory playerName, GameSettings memory settings) 
        external 
        nonReentrant 
        returns (uint256) 
    {
        require(playerToGame[msg.sender] == 0, "Already in a game");
        
        // Try to join an existing waiting game
        for (uint i = 0; i < waitingGames.length; i++) {
            uint256 gameId = waitingGames[i];
            if (games[gameId].phase == GamePhase.Waiting && 
                games[gameId].humanPlayerCount < 4) {
                joinGame(gameId, playerName);
                return gameId;
            }
        }
        
        // No available games, create new one
        return createGame(playerName, settings);
    }
    
    // ================================
    // GAME LOGIC
    // ================================
    
    /**
     * @dev Play a card
     */
    function playCard(uint256 gameId, uint8 cardId) 
        external 
        nonReentrant
        gameExists(gameId)
        playerInGame(gameId)
        gamePhase(gameId, GamePhase.Playing)
        isPlayerTurn(gameId)
    {
        GameState storage game = games[gameId];
        Player storage currentPlayer = game.players[game.currentPlayerIndex];
        
        require(_hasCard(currentPlayer.hand, cardId), "Card not in hand");
        require(_canPlayCard(cardId, game.topCard), "Cannot play this card");
        
        // Remove card from hand
        _removeCardFromHand(currentPlayer.hand, cardId);
        
        // Handle special card effects
        Card memory playedCard = cardDefinitions[cardId];
        
        if (playedCard.cardType == CardType.Void) {
            _handleVoidCard(gameId, cardId);
        } else {
            _handleRegularCard(gameId, cardId);
        }
        
        // Update game state
        game.lastMoveTime = block.timestamp;
        currentPlayer.lastActionTime = block.timestamp;
        
        emit CardPlayed(gameId, msg.sender, cardId);
        
        // Check win condition
        if (currentPlayer.hand.length == 0) {
            _endGame(gameId, msg.sender);
            return;
        }
        
        // Move to next turn (unless it's a void card)
        if (playedCard.cardType != CardType.Void) {
            _nextTurn(gameId);
        }
    }
    
    /**
     * @dev Draw a card from the deck
     */
    function drawCard(uint256 gameId) 
        external 
        nonReentrant
        gameExists(gameId)
        playerInGame(gameId)
        gamePhase(gameId, GamePhase.Playing)
        isPlayerTurn(gameId)
    {
        GameState storage game = games[gameId];
        require(game.drawPile.length > 0, "No cards left to draw");
        
        Player storage currentPlayer = game.players[game.currentPlayerIndex];
        
        // Draw card
        uint8 drawnCard = game.drawPile[game.drawPile.length - 1];
        game.drawPile.pop();
        currentPlayer.hand.push(drawnCard);
        
        // Update timestamps
        game.lastMoveTime = block.timestamp;
        currentPlayer.lastActionTime = block.timestamp;
        
        emit CardDrawn(gameId, msg.sender, drawnCard);
        
        _nextTurn(gameId);
    }
    
    /**
     * @dev Select color after playing a void card
     */
    function selectColor(uint256 gameId, ElementType color) 
        external 
        nonReentrant
        gameExists(gameId)
        playerInGame(gameId)
        gamePhase(gameId, GamePhase.ColorSelection)
        isPlayerTurn(gameId)
    {
        GameState storage game = games[gameId];
        
        // Create virtual color card
        game.topCard = _createColorCard(color);
        game.phase = GamePhase.Playing;
        game.voidActive = false;
        
        emit ColorSelected(gameId, color);
        
        _nextTurn(gameId);
    }
    
    /**
     * @dev Handle player timeout
     */
    function handleTimeout(uint256 gameId, uint8 playerIndex) 
        external 
        gameExists(gameId)
        gamePhase(gameId, GamePhase.Playing)
    {
        GameState storage game = games[gameId];
        require(playerIndex == game.currentPlayerIndex, "Not current player");
        require(
            block.timestamp >= game.lastMoveTime + TURN_TIMEOUT,
            "Timeout not reached"
        );
        
        Player storage player = game.players[playerIndex];
        
        // Apply penalty cards
        uint8 penaltyCards = game.settings.timeoutPenaltyCards;
        for (uint8 i = 0; i < penaltyCards && game.drawPile.length > 0; i++) {
            uint8 card = game.drawPile[game.drawPile.length - 1];
            game.drawPile.pop();
            player.hand.push(card);
        }
        
        emit PlayerTimeout(gameId, player.playerAddress);
        
        _nextTurn(gameId);
    }
    
    // ================================
    // INTERNAL GAME LOGIC
    // ================================
    
    function _startGame(uint256 gameId) internal {
        GameState storage game = games[gameId];
        
        // Initialize deck and deal cards
        _initializeDeck(gameId);
        _dealCards(gameId);
        
        // Set starting player randomly
        game.currentPlayerIndex = uint8(_random() % 4);
        game.direction = 1;
        game.phase = GamePhase.Playing;
        game.gameStartTime = block.timestamp;
        game.lastMoveTime = block.timestamp;
        
        // Remove from waiting games
        _removeFromWaitingGames(gameId);
        
        emit GameStarted(gameId);
        emit TurnChanged(gameId, game.currentPlayerIndex);
    }
    
    function _fillWithBots(uint256 gameId) internal {
        GameState storage game = games[gameId];
        
        string[3] memory botNames = ["Bot Alpha", "Bot Beta", "Bot Gamma"];
        
        for (uint8 i = game.humanPlayerCount; i < 4; i++) {
            game.players[i] = Player({
                playerAddress: address(0),
                name: botNames[i - game.humanPlayerCount],
                playerType: PlayerType.Bot,
                hand: new uint8[](0),
                isActive: true,
                lastActionTime: block.timestamp,
                score: 0
            });
        }
    }
    
    function _handleRegularCard(uint256 gameId, uint8 cardId) internal {
        GameState storage game = games[gameId];
        Card memory card = cardDefinitions[cardId];
        
        // Add old top card to discard pile
        game.discardPile.push(game.topCard);
        game.topCard = cardId;
        
        // Handle special effects
        if (card.cardType == CardType.Skip) {
            game.skipNext = true;
        } else if (card.cardType == CardType.Reverse) {
            game.direction *= -1;
        } else if (card.cardType == CardType.Stack) {
            _handleStackCard(gameId, cardId);
        }
    }
    
    function _handleVoidCard(uint256 gameId, uint8 cardId) internal {
        GameState storage game = games[gameId];
        
        game.discardPile.push(game.topCard);
        game.topCard = cardId;
        game.phase = GamePhase.ColorSelection;
        game.voidActive = true;
    }
    
    function _handleStackCard(uint256 gameId, uint8 cardId) internal {
        GameState storage game = games[gameId];
        Card memory stackCard = cardDefinitions[cardId];
        Player storage currentPlayer = game.players[game.currentPlayerIndex];
        
        // Remove matching element cards from player's hand
        uint8[] memory newHand = new uint8[](currentPlayer.hand.length);
        uint8 newHandSize = 0;
        
        for (uint i = 0; i < currentPlayer.hand.length; i++) {
            Card memory handCard = cardDefinitions[currentPlayer.hand[i]];
            if (handCard.element != stackCard.element) {
                newHand[newHandSize] = currentPlayer.hand[i];
                newHandSize++;
            }
        }
        
        // Update hand
        delete currentPlayer.hand;
        for (uint i = 0; i < newHandSize; i++) {
            currentPlayer.hand.push(newHand[i]);
        }
        
        // Filter discard pile based on stack mode
        if (game.settings.stackModeDestroy) {
            _filterDiscardPileDestroy(gameId, stackCard.element);
        } else {
            _filterDiscardPileMove(gameId, stackCard.element);
        }
    }
    
    function _nextTurn(uint256 gameId) internal {
        GameState storage game = games[gameId];
        
        uint8 nextPlayer = game.currentPlayerIndex;
        
        if (game.direction == 1) {
            nextPlayer = (nextPlayer + 1) % 4;
        } else {
            nextPlayer = nextPlayer == 0 ? 3 : nextPlayer - 1;
        }
        
        if (game.skipNext) {
            if (game.direction == 1) {
                nextPlayer = (nextPlayer + 1) % 4;
            } else {
                nextPlayer = nextPlayer == 0 ? 3 : nextPlayer - 1;
            }
            game.skipNext = false;
        }
        
        game.currentPlayerIndex = nextPlayer;
        game.lastMoveTime = block.timestamp;
        
        emit TurnChanged(gameId, nextPlayer);
    }
    
    function _endGame(uint256 gameId, address winner) internal {
        GameState storage game = games[gameId];
        game.phase = GamePhase.Ended;
        game.winner = winner;
        
        // Clear player game mappings
        for (uint8 i = 0; i < 4; i++) {
            if (game.players[i].playerAddress != address(0)) {
                playerToGame[game.players[i].playerAddress] = 0;
            }
        }
        
        emit GameEnded(gameId, winner);
    }
    
    // ================================
    // DECK & CARD MANAGEMENT
    // ================================
    
    function _initializeCardDefinitions() internal {
        uint8 cardId = 0;
        
        // Number cards (72 total: 4 elements × 9 values × 2 copies)
        for (uint8 element = 0; element < 4; element++) {
            for (uint8 value = 1; value <= 9; value++) {
                for (uint8 copy = 0; copy < 2; copy++) {
                    cardDefinitions[cardId] = Card({
                        id: cardId,
                        element: ElementType(element),
                        cardType: CardType.Number,
                        value: value
                    });
                    cardId++;
                }
            }
        }
        
        // Special cards (24 total: 4 elements × 3 types × 2 copies)
        for (uint8 element = 0; element < 4; element++) {
            for (uint8 cardType = 1; cardType <= 3; cardType++) { // Skip=1, Reverse=2, Stack=3
                for (uint8 copy = 0; copy < 2; copy++) {
                    cardDefinitions[cardId] = Card({
                        id: cardId,
                        element: ElementType(element),
                        cardType: CardType(cardType),
                        value: 0
                    });
                    cardId++;
                }
            }
        }
        
        // Void cards (4 total)
        for (uint8 i = 0; i < 4; i++) {
            cardDefinitions[cardId] = Card({
                id: cardId,
                element: ElementType.Fire, // Placeholder
                cardType: CardType.Void,
                value: 0
            });
            cardId++;
        }
    }
    
    function _initializeDeck(uint256 gameId) internal {
        GameState storage game = games[gameId];
        
        // Create shuffled deck
        uint8[] memory deck = new uint8[](108);
        for (uint8 i = 0; i < 108; i++) {
            deck[i] = i;
        }
        
        // Shuffle deck
        for (uint8 i = 107; i > 0; i--) {
            uint8 j = uint8(_random() % (i + 1));
            (deck[i], deck[j]) = (deck[j], deck[i]);
        }
        
        // Find starting card (non-special)
        uint8 startCardIndex = 0;
        while (cardDefinitions[deck[startCardIndex]].cardType != CardType.Number) {
            startCardIndex++;
        }
        
        game.topCard = deck[startCardIndex];
        
        // Initialize draw pile (exclude starting card)
        delete game.drawPile;
        for (uint8 i = 0; i < 108; i++) {
            if (i != startCardIndex) {
                game.drawPile.push(deck[i]);
            }
        }
    }
    
    function _dealCards(uint256 gameId) internal {
        GameState storage game = games[gameId];
        
        for (uint8 player = 0; player < 4; player++) {
            delete game.players[player].hand;
            for (uint8 card = 0; card < CARDS_PER_PLAYER; card++) {
                uint8 drawnCard = game.drawPile[game.drawPile.length - 1];
                game.drawPile.pop();
                game.players[player].hand.push(drawnCard);
            }
        }
    }
    
    // ================================
    // UTILITY FUNCTIONS
    // ================================
    
    function _canPlayCard(uint8 cardId, uint8 topCardId) internal view returns (bool) {
        Card memory card = cardDefinitions[cardId];
        Card memory topCard = cardDefinitions[topCardId];
        
        // Void cards can always be played
        if (card.cardType == CardType.Void) return true;
        
        // Same element
        if (card.element == topCard.element) return true;
        
        // Same type (for special cards)
        if (card.cardType == topCard.cardType && card.cardType != CardType.Number) return true;
        
        // Same number value
        if (card.cardType == CardType.Number && 
            topCard.cardType == CardType.Number && 
            card.value == topCard.value) return true;
        
        return false;
    }
    
    function _hasCard(uint8[] memory hand, uint8 cardId) internal pure returns (bool) {
        for (uint i = 0; i < hand.length; i++) {
            if (hand[i] == cardId) return true;
        }
        return false;
    }
    
    function _removeCardFromHand(uint8[] storage hand, uint8 cardId) internal {
        for (uint i = 0; i < hand.length; i++) {
            if (hand[i] == cardId) {
                hand[i] = hand[hand.length - 1];
                hand.pop();
                break;
            }
        }
    }
    
    function _createColorCard(ElementType color) internal pure returns (uint8) {
        // Return a virtual card ID for color selection
        return uint8(color) + 200; // Virtual card IDs start at 200
    }
    
    function _filterDiscardPileDestroy(uint256 gameId, ElementType stackElement) internal {
        GameState storage game = games[gameId];
        uint8[] memory newDiscardPile = new uint8[](game.discardPile.length);
        uint8 newSize = 0;
        
        for (uint i = 0; i < game.discardPile.length; i++) {
            Card memory discardCard = cardDefinitions[game.discardPile[i]];
            
            // Keep void cards and cards that aren't weak to stack element
            if (discardCard.cardType == CardType.Void || 
                !_isWeakTo(discardCard.element, stackElement)) {
                newDiscardPile[newSize] = game.discardPile[i];
                newSize++;
            }
        }
        
        delete game.discardPile;
        for (uint i = 0; i < newSize; i++) {
            game.discardPile.push(newDiscardPile[i]);
        }
    }
    
    function _filterDiscardPileMove(uint256 gameId, ElementType stackElement) internal {
        GameState storage game = games[gameId];
        uint8[] memory newDiscardPile = new uint8[](game.discardPile.length);
        uint8 newSize = 0;
        
        for (uint i = 0; i < game.discardPile.length; i++) {
            Card memory discardCard = cardDefinitions[game.discardPile[i]];
            
            // Keep cards that aren't weak to stack element
            if (discardCard.cardType == CardType.Void || 
                discardCard.element == stackElement ||
                !_isWeakTo(discardCard.element, stackElement)) {
                newDiscardPile[newSize] = game.discardPile[i];
                newSize++;
            }
        }
        
        delete game.discardPile;
        for (uint i = 0; i < newSize; i++) {
            game.discardPile.push(newDiscardPile[i]);
        }
    }
    
    function _isWeakTo(ElementType defender, ElementType attacker) internal pure returns (bool) {
        // fire beats plant, water beats fire, plant beats water, thunder beats plant
        if (attacker == ElementType.Fire && defender == ElementType.Plant) return true;
        if (attacker == ElementType.Water && defender == ElementType.Fire) return true;
        if (attacker == ElementType.Plant && defender == ElementType.Water) return true;
        if (attacker == ElementType.Thunder && defender == ElementType.Plant) return true;
        return false;
    }
    
    function _removeFromWaitingGames(uint256 gameId) internal {
        for (uint i = 0; i < waitingGames.length; i++) {
            if (waitingGames[i] == gameId) {
                waitingGames[i] = waitingGames[waitingGames.length - 1];
                waitingGames.pop();
                break;
            }
        }
    }
    
    function _random() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.difficulty,
            block.number,
            msg.sender
        )));
    }
    
    // ================================
    // VIEW FUNCTIONS
    // ================================
    
    function getGame(uint256 gameId) external view returns (GameState memory) {
        return games[gameId];
    }
    
    function getPlayerHand(uint256 gameId, address player) external view returns (uint8[] memory) {
        GameState memory game = games[gameId];
        for (uint8 i = 0; i < 4; i++) {
            if (game.players[i].playerAddress == player) {
                return game.players[i].hand;
            }
        }
        revert("Player not found");
    }
    
    function getWaitingGames() external view returns (uint256[] memory) {
        return waitingGames;
    }
    
    function getCardDefinition(uint8 cardId) external view returns (Card memory) {
        return cardDefinitions[cardId];
    }
    
    function isPlayerTurn(uint256 gameId, address player) external view returns (bool) {
        GameState memory game = games[gameId];
        return game.players[game.currentPlayerIndex].playerAddress == player;
    }
    
    function getGameCount() external view returns (uint256) {
        return _gameIdCounter.current();
    }
    
    // ================================
    // ADMIN FUNCTIONS
    // ================================
    
    function emergencyEndGame(uint256 gameId) external onlyOwner gameExists(gameId) {
        _endGame(gameId, address(0));
    }
    
    function cleanupOldGames(uint256[] calldata gameIds) external onlyOwner {
        for (uint i = 0; i < gameIds.length; i++) {
            uint256 gameId = gameIds[i];
            if (games[gameId].gameExists && 
                block.timestamp >= games[gameId].lastMoveTime + GAME_TIMEOUT) {
                _endGame(gameId, address(0));
            }
        }
    }
}