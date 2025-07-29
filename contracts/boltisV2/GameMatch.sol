// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IMatchRegistry.sol";
import "./interfaces/ISessionKeyManager.sol";
import "./GameLogicLibrary.sol";

/**
 * @title GameMatch
 * @notice Individual match instance for 4-player card game
 * @dev Deployed as a clone for each game
 */
contract GameMatch is Initializable, ReentrancyGuard {
  using GameLogicLibrary for *;

  // ==================== Types ====================

  struct Player {
    address addr;
    uint8 cardCount;
    bool isEliminated;
    bool hasJoined;
    bytes32 handCommitment; // For future: ZK proof of hand
  }

  struct GameSettings {
    uint8 cardsPerPlayer;
    uint256 turnTimeLimit;
    uint256 matchDuration;
    bool pauseEnabled;
    uint8 penaltyCards;
  }

  enum Phase {
    WAITING_FOR_PLAYERS,
    PLAYING,
    COLOR_SELECTION,
    PAUSED,
    COMPLETED,
    CANCELLED
  }

  // ==================== State ====================

  // Match identification
  uint256 public matchId;
  address public host;
  address public matchRegistry;
  ISessionKeyManager public sessionKeyManager;

  // Game settings
  GameSettings public settings;
  uint256 public stakePerPlayer;
  uint256 public totalStake;

  // Players
  Player[4] public players;
  address[4] public playerAddresses;
  mapping(address => uint8) public playerIndex;
  mapping(address => bool) public isPlayer;
  uint8 public joinedCount;

  // Game state
  Phase public gamePhase;
  uint8 public currentPlayerIndex;
  int8 public direction = 1;
  uint256 public turnStartTime;
  uint256 public gameStartTime;
  address public winner;

  // Cards (simplified - in production would use commit-reveal)
  GameLogicLibrary.Card[] public discardPile;
  GameLogicLibrary.Card public topCard;
  uint256 public drawPileCount;

  // Special effects
  bool public skipNext;
  bool public voidActive;
  uint8 public voidSelectedColor;

  // Turn tracking
  uint256 public turnNumber;
  mapping(uint256 => address) public turnHistory;

  // ==================== Events ====================

  event PlayerJoined(address indexed player, uint8 playersJoined);
  event MatchStarted(uint256 timestamp, uint8 startingPlayer);
  event ActionExecuted(
    address indexed player,
    uint256 turnNumber,
    string action,
    bytes data
  );
  event CardPlayed(
    address indexed player,
    uint8 cardType,
    uint8 element,
    uint8 value
  );
  event TurnChanged(
    address indexed nextPlayer,
    uint256 turnNumber,
    uint256 timeLimit
  );
  event SpecialEffectActivated(string effect, bytes data);
  event PlayerEliminated(address indexed player, string reason);
  event MatchCompleted(address indexed winner, uint256[] finalScores);
  event TimeoutPenalty(address indexed player, uint8 cardsAdded);

  // ==================== Modifiers ====================

  modifier onlyPlayer() {
    require(isPlayer[msg.sender], "Not a player");
    _;
  }

  modifier onlyCurrentPlayer() {
    address currentPlayer = _getCurrentPlayerAddress();
    require(
      msg.sender == currentPlayer || _isValidSessionKey(currentPlayer),
      "Not current player"
    );
    _;
  }

  modifier gameActive() {
    require(
      gamePhase == Phase.PLAYING || gamePhase == Phase.COLOR_SELECTION,
      "Game not active"
    );
    _;
  }

  // ==================== Initialization ====================

  /**
   * @notice Initialize the match (called by MatchRegistry)
   */
  function initialize(
    uint256 _matchId,
    address[4] memory _players,
    address _host,
    GameSettings memory _settings,
    uint256 _stakePerPlayer,
    address _sessionKeyManager,
    address _matchRegistry
  ) external initializer {
    matchId = _matchId;
    host = _host;
    settings = _settings;
    stakePerPlayer = _stakePerPlayer;
    sessionKeyManager = ISessionKeyManager(_sessionKeyManager);
    matchRegistry = _matchRegistry;

    // Initialize players
    for (uint8 i = 0; i < 4; i++) {
      playerAddresses[i] = _players[i];
      players[i] = Player({
        addr: _players[i],
        cardCount: 0,
        isEliminated: false,
        hasJoined: false,
        handCommitment: bytes32(0)
      });
      playerIndex[_players[i]] = i;
      isPlayer[_players[i]] = true;
    }

    gamePhase = Phase.WAITING_FOR_PLAYERS;
    drawPileCount = 108 - (4 * _settings.cardsPerPlayer) - 1; // -1 for top card

    // Auto-join the host
    _joinMatch(host);
  }

  // ==================== Player Actions ====================

  /**
   * @notice Join the match (via session key)
   */
  function joinMatch() external payable nonReentrant {
    address player = _getSessionKeyOwner();
    require(isPlayer[player], "Not allowed in this match");

    // Handle stake
    if (stakePerPlayer > 0) {
      require(msg.value == stakePerPlayer, "Incorrect stake");
      totalStake += msg.value;
    }

    _joinMatch(player);
  }

  /**
   * @notice Execute a game action (via session key)
   * @param actionType 0: DISCARD, 1: DRAW, 2: SELECT_COLOR
   * @param actionData Encoded action data
   */
  function executeAction(uint8 actionType, bytes calldata actionData)
    external
    gameActive
    nonReentrant
  {
    address actor = _validateAndGetCurrentPlayer();

    if (actionType == 0) {
      _executeDiscard(actor, actionData);
    } else if (actionType == 1) {
      _executeDraw(actor);
    } else if (actionType == 2) {
      _executeColorSelection(actor, actionData);
    } else {
      revert("Invalid action type");
    }

    emit ActionExecuted(
      actor,
      turnNumber,
      _getActionName(actionType),
      actionData
    );

    // Check win conditions
    (bool hasWinner, uint8 winnerIndex) = GameLogicLibrary.checkWinCondition(
      _getCardCounts(),
      _getEliminationStatus()
    );

    if (hasWinner) {
      _endMatch(players[winnerIndex].addr);
    } else if (gamePhase != Phase.COLOR_SELECTION) {
      _advanceTurn();
    }
  }

  /**
   * @notice Handle turn timeout - anyone can call
   */
  function handleTimeout() external gameActive {
    require(
      block.timestamp > turnStartTime + settings.turnTimeLimit,
      "Turn not timed out"
    );

    address timedOutPlayer = _getCurrentPlayerAddress();
    uint8 playerIdx = playerIndex[timedOutPlayer];

    // Apply penalty
    uint8 newCardCount = GameLogicLibrary.applyTimeoutPenalty(
      players[playerIdx].cardCount,
      settings.penaltyCards
    );

    players[playerIdx].cardCount = newCardCount;

    emit TimeoutPenalty(timedOutPlayer, settings.penaltyCards);
    emit ActionExecuted(
      timedOutPlayer,
      turnNumber,
      "TIMEOUT",
      abi.encode(settings.penaltyCards)
    );

    // Check if player should be eliminated (too many cards)
    if (newCardCount > 50) {
      players[playerIdx].isEliminated = true;
      emit PlayerEliminated(timedOutPlayer, "Too many cards");
    }

    // Check win condition
    (bool hasWinner, uint8 winnerIndex) = GameLogicLibrary.checkWinCondition(
      _getCardCounts(),
      _getEliminationStatus()
    );

    if (hasWinner) {
      _endMatch(players[winnerIndex].addr);
    } else {
      _advanceTurn();
    }
  }

  /**
   * @notice Declare winner (temporary MVP function)
   * @dev In production, this would be validated with ZK proofs
   */
  function declareWinner(address _winner, uint8[4] calldata finalCardCounts)
    external
    onlyPlayer
  {
    require(gamePhase == Phase.PLAYING, "Game not active");
    require(isPlayer[_winner], "Winner must be a player");

    // Basic validation - at least one player should have 0 cards
    bool validWin = false;
    for (uint256 i = 0; i < 4; i++) {
      if (finalCardCounts[i] == 0 && players[i].addr == _winner) {
        validWin = true;
        // Update card counts
        players[i].cardCount = finalCardCounts[i];
      } else {
        players[i].cardCount = finalCardCounts[i];
      }
    }
    require(validWin, "Invalid winner - must have 0 cards");

    _endMatch(_winner);
  }

  // ==================== Internal Game Logic ====================

  function _joinMatch(address player) internal {
    uint8 idx = playerIndex[player];
    require(!players[idx].hasJoined, "Already joined");
    require(gamePhase == Phase.WAITING_FOR_PLAYERS, "Match already started");

    players[idx].hasJoined = true;
    joinedCount++;

    emit PlayerJoined(player, joinedCount);

    // Auto-start when all players join
    if (joinedCount == 4) {
      _startMatch();
    }
  }

  function _startMatch() internal {
    gamePhase = Phase.PLAYING;
    gameStartTime = block.timestamp;

    // Initialize card counts
    for (uint8 i = 0; i < 4; i++) {
      if (players[i].hasJoined) {
        players[i].cardCount = settings.cardsPerPlayer;
      } else {
        players[i].isEliminated = true;
        emit PlayerEliminated(players[i].addr, "Did not join");
      }
    }

    // Select random starting player
    address[] memory playerAddressArray = new address[](4);
    for (uint8 i = 0; i < 4; i++) {
      playerAddressArray[i] = playerAddresses[i];
    }
    uint256 seed = GameLogicLibrary.generateShuffleSeed(
      playerAddressArray,
      block.timestamp
    );
    currentPlayerIndex = GameLogicLibrary.selectStartingPlayer(seed, 4);

    // Ensure starting player has joined
    while (!players[currentPlayerIndex].hasJoined) {
      currentPlayerIndex = (currentPlayerIndex + 1) % 4;
    }

    turnStartTime = block.timestamp;
    turnNumber = 1;

    // Initialize top card (simplified - would use VRF in production)
    topCard = GameLogicLibrary.Card({
      cardType: 0, // Number card
      element: uint8(block.timestamp % 4),
      value: uint8(block.timestamp % 10)
    });
    discardPile.push(topCard);

    // Update registry
    IMatchRegistry(matchRegistry).updateMatchStatus(
      matchId,
      IMatchRegistry.MatchStatus.PLAYING
    );

    emit MatchStarted(block.timestamp, currentPlayerIndex);
    emit TurnChanged(
      players[currentPlayerIndex].addr,
      turnNumber,
      settings.turnTimeLimit
    );
  }

  function _executeDiscard(address actor, bytes calldata actionData) internal {
    (GameLogicLibrary.Card memory card, ) = abi.decode(
      actionData,
      (GameLogicLibrary.Card, bytes32)
    );

    // Validate card can be played
    require(
      GameLogicLibrary.canPlayCard(
        card,
        topCard,
        voidActive,
        voidSelectedColor
      ),
      "Cannot play this card"
    );

    uint8 playerIdx = playerIndex[actor];
    require(players[playerIdx].cardCount > 0, "No cards to play");

    // Update game state
    players[playerIdx].cardCount--;
    topCard = card;
    discardPile.push(card);

    // Process special effects
    _processSpecialEffects(card);

    // Reset void effect after non-void card is played
    if (voidActive && card.cardType != 3) {
      voidActive = false;
      voidSelectedColor = 0;
    }

    emit CardPlayed(actor, card.cardType, card.element, card.value);
  }

  function _executeDraw(address actor) internal {
    uint8 playerIdx = playerIndex[actor];

    // Check draw pile
    require(drawPileCount > 0, "No cards to draw");

    players[playerIdx].cardCount++;
    drawPileCount--;

    // If draw pile is empty, reshuffle (simplified)
    if (drawPileCount == 0 && discardPile.length > 10) {
      drawPileCount = discardPile.length - 1;
      // Keep only top card in discard
    }
  }

  function _executeColorSelection(address actor, bytes calldata actionData)
    internal
  {
    require(gamePhase == Phase.COLOR_SELECTION, "Not in color selection");
    require(actor == _getCurrentPlayerAddress(), "Not your turn");

    uint8 selectedColor = abi.decode(actionData, (uint8));
    require(selectedColor < 4, "Invalid color");

    voidSelectedColor = selectedColor;
    voidActive = true;
    gamePhase = Phase.PLAYING;

    emit SpecialEffectActivated(
      "void_color_selected",
      abi.encode(selectedColor)
    );

    _advanceTurn();
  }

  function _processSpecialEffects(GameLogicLibrary.Card memory card) internal {
    if (card.cardType == 1) {
      // Skip
      skipNext = true;
      emit SpecialEffectActivated("skip", "");
    } else if (card.cardType == 2) {
      // Reverse
      direction *= -1;
      emit SpecialEffectActivated("reverse", abi.encode(direction));
    } else if (card.cardType == 3) {
      // Void
      gamePhase = Phase.COLOR_SELECTION;
      voidActive = false; // Will be set after color selection
      emit SpecialEffectActivated("void", "");
    }
  }

  function _advanceTurn() internal {
    // Update turn history
    turnHistory[turnNumber] = players[currentPlayerIndex].addr;

    // Get next player
    uint8 nextIndex = GameLogicLibrary.getNextPlayerIndex(
      currentPlayerIndex,
      direction,
      4,
      skipNext
    );

    // Skip eliminated players
    uint8 attempts = 0;
    while (
      (players[nextIndex].isEliminated || !players[nextIndex].hasJoined) &&
      attempts < 4
    ) {
      nextIndex = GameLogicLibrary.getNextPlayerIndex(
        nextIndex,
        direction,
        4,
        false
      );
      attempts++;
    }

    currentPlayerIndex = nextIndex;
    turnStartTime = block.timestamp;
    turnNumber++;
    skipNext = false;

    emit TurnChanged(
      players[currentPlayerIndex].addr,
      turnNumber,
      settings.turnTimeLimit
    );
  }

  function _endMatch(address _winner) internal {
    gamePhase = Phase.COMPLETED;
    winner = _winner;

    // Calculate final scores
    uint256[] memory scores = new uint256[](4);
    for (uint8 i = 0; i < 4; i++) {
      if (!players[i].isEliminated) {
        // Simple scoring - just card count for now
        scores[i] = players[i].cardCount;
      } else {
        scores[i] = 999; // High score for eliminated players
      }
    }

    // Report to registry
    IMatchRegistry(matchRegistry).reportWinner(matchId, winner);
    IMatchRegistry(matchRegistry).updateMatchStatus(
      matchId,
      IMatchRegistry.MatchStatus.COMPLETED
    );

    emit MatchCompleted(winner, scores);
  }

  // ==================== Helper Functions ====================

  function _getCurrentPlayerAddress() internal view returns (address) {
    return players[currentPlayerIndex].addr;
  }

  function _getSessionKeyOwner() internal view returns (address) {
    // If called directly, return msg.sender
    // If called via session key, validate and return owner
    if (msg.sender == address(sessionKeyManager)) {
      // In production, SessionKeyManager would pass owner info
      return tx.origin; // Simplified
    }
    return msg.sender;
  }

  function _isValidSessionKey(address player) internal view returns (bool) {
    return sessionKeyManager.validateSessionKeyAction(player, msg.sender);
  }

  function _validateAndGetCurrentPlayer() internal view returns (address) {
    address currentPlayer = _getCurrentPlayerAddress();
    address caller = _getSessionKeyOwner();

    require(caller == currentPlayer, "Not your turn");
    require(!players[currentPlayerIndex].isEliminated, "Player eliminated");

    return currentPlayer;
  }

  function _getCardCounts() internal view returns (uint8[] memory) {
    uint8[] memory counts = new uint8[](4);
    for (uint8 i = 0; i < 4; i++) {
      counts[i] = players[i].cardCount;
    }
    return counts;
  }

  function _getEliminationStatus() internal view returns (bool[] memory) {
    bool[] memory eliminated = new bool[](4);
    for (uint8 i = 0; i < 4; i++) {
      eliminated[i] = players[i].isEliminated || !players[i].hasJoined;
    }
    return eliminated;
  }

  function _getActionName(uint8 actionType)
    internal
    pure
    returns (string memory)
  {
    if (actionType == 0) return "DISCARD";
    if (actionType == 1) return "DRAW";
    if (actionType == 2) return "SELECT_COLOR";
    return "UNKNOWN";
  }

  // ==================== View Functions ====================

  /**
   * @notice Get current game state
   */
  function getGameState()
    external
    view
    returns (
      Phase phase,
      address currentPlayer,
      uint256 timeRemaining,
      uint8[4] memory cardCounts,
      bool[4] memory joined,
      bool[4] memory eliminated
    )
  {
    phase = gamePhase;
    currentPlayer = gamePhase == Phase.PLAYING
      ? _getCurrentPlayerAddress()
      : address(0);

    if (turnStartTime + settings.turnTimeLimit > block.timestamp) {
      timeRemaining = turnStartTime + settings.turnTimeLimit - block.timestamp;
    } else {
      timeRemaining = 0;
    }

    for (uint8 i = 0; i < 4; i++) {
      cardCounts[i] = players[i].cardCount;
      joined[i] = players[i].hasJoined;
      eliminated[i] = players[i].isEliminated;
    }
  }

  /**
   * @notice Get discard pile info
   */
  function getDiscardPileInfo()
    external
    view
    returns (
      uint256 count,
      GameLogicLibrary.Card memory currentTopCard,
      bool voidIsActive,
      uint8 selectedColor
    )
  {
    count = discardPile.length;
    currentTopCard = topCard;
    voidIsActive = voidActive;
    selectedColor = voidSelectedColor;
  }

  // ==================== Admin Functions ====================

  /**
   * @notice Force start with current players (host only)
   */
  function forceStart() external {
    require(msg.sender == host, "Only host");
    require(joinedCount >= 2, "Need at least 2 players");
    require(gamePhase == Phase.WAITING_FOR_PLAYERS, "Already started");

    _startMatch();
  }

  /**
   * @notice Emergency cancel (via registry)
   */
  function emergencyCancel() external {
    require(msg.sender == matchRegistry, "Only registry");

    gamePhase = Phase.CANCELLED;

    // Refund stakes
    if (totalStake > 0) {
      for (uint8 i = 0; i < 4; i++) {
        if (players[i].hasJoined) {
          payable(players[i].addr).transfer(stakePerPlayer);
        }
      }
    }
  }

  /**
   * @notice Distribute prize (called by registry)
   */
  function distributePrize(
    address _winner,
    uint256 winnerAmount,
    address platformFeeRecipient,
    uint256 platformFee
  ) external {
    require(msg.sender == matchRegistry, "Only registry");
    require(
      address(this).balance >= winnerAmount + platformFee,
      "Insufficient balance"
    );

    if (winnerAmount > 0) {
      payable(_winner).transfer(winnerAmount);
    }

    if (platformFee > 0) {
      payable(platformFeeRecipient).transfer(platformFee);
    }
  }

  // ==================== Receive Function ====================

  receive() external payable {
    // Accept stakes
  }
}
