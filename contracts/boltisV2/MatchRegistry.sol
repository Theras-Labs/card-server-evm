// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IGameMatch.sol";
import "./interfaces/ISessionKeyManager.sol";
import "./GameLogicLibrary.sol";

/**
 * @title MatchRegistry
 * @notice Central registry for creating and managing game matches
 * @dev Uses clone pattern for gas-efficient match deployment
 */
contract MatchRegistry is Ownable, Pausable {
  using Clones for address;

  // ==================== Types ====================

  struct MatchInfo {
    uint256 matchId;
    address matchContract;
    address host;
    address[4] players;
    uint256 createdAt;
    uint256 startedAt;
    uint256 endedAt;
    MatchStatus status;
    uint256 stakeAmount;
    address winner;
  }

  struct GameSettings {
    uint8 cardsPerPlayer;
    uint256 turnTimeLimit;
    uint256 matchDuration;
    bool pauseEnabled;
    uint8 penaltyCards;
  }

  enum MatchStatus {
    WAITING, // Waiting for players to join
    PLAYING, // Game in progress
    COMPLETED, // Game ended normally
    CANCELLED, // Game cancelled
    EXPIRED // Game expired due to inactivity
  }

  // ==================== State ====================

  uint256 public matchCounter;
  address public gameMatchImplementation;
  ISessionKeyManager public immutable sessionKeyManager;

  mapping(uint256 => MatchInfo) public matches;
  mapping(address => uint256[]) public playerActiveMatches;
  mapping(address => uint256[]) public playerMatchHistory;
  mapping(address => bool) public authorizedCallers;

  // Fee configuration
  uint256 public platformFeePercent = 500; // 5% = 500 basis points
  uint256 public constant MAX_FEE = 1000; // 10% max
  address public feeRecipient;

  // ==================== Events ====================

  event MatchCreated(
    uint256 indexed matchId,
    address indexed matchContract,
    address indexed host,
    address[4] players,
    uint256 stakeAmount
  );

  event MatchStatusUpdated(
    uint256 indexed matchId,
    MatchStatus oldStatus,
    MatchStatus newStatus
  );

  event MatchStarted(uint256 indexed matchId, uint256 timestamp);

  event MatchCompleted(
    uint256 indexed matchId,
    address indexed winner,
    uint256 prize,
    uint256 platformFee
  );

  event GameImplementationUpdated(
    address indexed oldImplementation,
    address indexed newImplementation
  );

  // ==================== Constructor ====================

  constructor(
    address _sessionKeyManager,
    address _gameMatchImplementation,
    address _feeRecipient
  ) Ownable(msg.sender) {
    require(_sessionKeyManager != address(0), "Invalid session key manager");
    require(_gameMatchImplementation != address(0), "Invalid implementation");
    require(_feeRecipient != address(0), "Invalid fee recipient");

    sessionKeyManager = ISessionKeyManager(_sessionKeyManager);
    gameMatchImplementation = _gameMatchImplementation;
    feeRecipient = _feeRecipient;
  }

  // ==================== Public Functions ====================

  /**
   * @notice Create a new match (via session key)
   * @param players Array of 4 player addresses (including host)
   * @param settings Game settings
   * @param stakeAmount Stake per player in wei
   * @return matchId The created match ID
   */
  function createMatch(
    address[4] memory players,
    GameSettings memory settings,
    uint256 stakeAmount
  ) external payable whenNotPaused returns (uint256 matchId) {
    // Validate caller is using session key
    address matchHost = _validateSessionKeyCaller();

    // Validate host is in player list
    bool hostFound = false;
    for (uint256 i = 0; i < 4; i++) {
      if (players[i] == matchHost) {
        hostFound = true;
        break;
      }
    }
    require(hostFound, "Host must be in player list");

    // Validate all addresses are unique and not zero
    for (uint256 i = 0; i < 4; i++) {
      require(players[i] != address(0), "Invalid player address");
      for (uint256 j = i + 1; j < 4; j++) {
        require(players[i] != players[j], "Duplicate players");
      }
    }

    // Validate game settings
    (bool validSettings, string memory reason) = GameLogicLibrary
      .validateGameSettings(
        4, // Always 4 players
        settings.cardsPerPlayer,
        settings.turnTimeLimit
      );
    require(validSettings, reason);

    // Handle stake if provided
    if (stakeAmount > 0) {
      require(msg.value == stakeAmount, "Incorrect stake amount");
    }

    // Generate match ID
    matchId = ++matchCounter;

    // Deploy match contract using clone
    address matchContract = gameMatchImplementation.clone();

    // Initialize the match
    IGameMatch(matchContract).initialize(
      matchId,
      players,
      matchHost,
      IGameMatch.GameSettings({
        cardsPerPlayer: settings.cardsPerPlayer,
        turnTimeLimit: settings.turnTimeLimit,
        matchDuration: settings.matchDuration,
        pauseEnabled: settings.pauseEnabled,
        penaltyCards: settings.penaltyCards
      }),
      stakeAmount,
      address(sessionKeyManager),
      address(this)
    );

    // Store match info
    matches[matchId] = MatchInfo({
      matchId: matchId,
      matchContract: matchContract,
      host: matchHost,
      players: players,
      createdAt: block.timestamp,
      startedAt: 0,
      endedAt: 0,
      status: MatchStatus.WAITING,
      stakeAmount: stakeAmount,
      winner: address(0)
    });

    // Track for all players
    for (uint256 i = 0; i < 4; i++) {
      playerActiveMatches[players[i]].push(matchId);
    }

    // Transfer stake to match contract if provided
    if (stakeAmount > 0) {
      payable(matchContract).transfer(msg.value);
    }

    emit MatchCreated(matchId, matchContract, matchHost, players, stakeAmount);
  }

  /**
   * @notice Update match status (called by match contracts)
   * @param matchId Match ID
   * @param newStatus New status
   */
  function updateMatchStatus(uint256 matchId, MatchStatus newStatus) external {
    MatchInfo storage matchInfo = matches[matchId];
    require(msg.sender == matchInfo.matchContract, "Only match contract");

    MatchStatus oldStatus = matchInfo.status;
    matchInfo.status = newStatus;

    // Update timestamps
    if (newStatus == MatchStatus.PLAYING && matchInfo.startedAt == 0) {
      matchInfo.startedAt = block.timestamp;
      emit MatchStarted(matchId, block.timestamp);
    } else if (
      (newStatus == MatchStatus.COMPLETED ||
        newStatus == MatchStatus.CANCELLED ||
        newStatus == MatchStatus.EXPIRED) && matchInfo.endedAt == 0
    ) {
      matchInfo.endedAt = block.timestamp;
      _handleMatchEnd(matchId);
    }

    emit MatchStatusUpdated(matchId, oldStatus, newStatus);
  }

  /**
   * @notice Report match winner (called by match contract)
   * @param matchId Match ID
   * @param winner Winner address
   */
  function reportWinner(uint256 matchId, address winner) external {
    MatchInfo storage matchInfo = matches[matchId];
    require(msg.sender == matchInfo.matchContract, "Only match contract");

    matchInfo.winner = winner;

    // Distribute prize if there was a stake
    if (matchInfo.stakeAmount > 0) {
      uint256 totalPrize = matchInfo.stakeAmount * 4; // 4 players
      uint256 platformFee = (totalPrize * platformFeePercent) / 10000;
      uint256 winnerPrize = totalPrize - platformFee;

      // Transfer from match contract
      IGameMatch(matchInfo.matchContract).distributePrize(
        winner,
        winnerPrize,
        feeRecipient,
        platformFee
      );

      emit MatchCompleted(matchId, winner, winnerPrize, platformFee);
    } else {
      emit MatchCompleted(matchId, winner, 0, 0);
    }
  }

  // ==================== View Functions ====================

  /**
   * @notice Get all active matches for a player
   */
  function getPlayerActiveMatches(address player)
    external
    view
    returns (uint256[] memory)
  {
    return playerActiveMatches[player];
  }

  /**
   * @notice Get match history for a player
   */
  function getPlayerMatchHistory(address player)
    external
    view
    returns (uint256[] memory)
  {
    return playerMatchHistory[player];
  }

  /**
   * @notice Get detailed match info
   */
  function getMatchInfo(uint256 matchId)
    external
    view
    returns (MatchInfo memory)
  {
    return matches[matchId];
  }

  /**
   * @notice Get all matches with a specific status
   */
  function getMatchesByStatus(MatchStatus status)
    external
    view
    returns (uint256[] memory matchIds)
  {
    uint256 count = 0;
    for (uint256 i = 1; i <= matchCounter; i++) {
      if (matches[i].status == status) {
        count++;
      }
    }

    matchIds = new uint256[](count);
    uint256 index = 0;
    for (uint256 i = 1; i <= matchCounter; i++) {
      if (matches[i].status == status) {
        matchIds[index++] = i;
      }
    }
  }

  // ==================== Admin Functions ====================

  /**
   * @notice Update game implementation contract
   */
  function updateGameImplementation(address newImplementation)
    external
    onlyOwner
  {
    require(newImplementation != address(0), "Invalid implementation");
    address oldImplementation = gameMatchImplementation;
    gameMatchImplementation = newImplementation;

    emit GameImplementationUpdated(oldImplementation, newImplementation);
  }

  /**
   * @notice Update platform fee
   */
  function updatePlatformFee(uint256 newFeePercent) external onlyOwner {
    require(newFeePercent <= MAX_FEE, "Fee too high");
    platformFeePercent = newFeePercent;
  }

  /**
   * @notice Update fee recipient
   */
  function updateFeeRecipient(address newRecipient) external onlyOwner {
    require(newRecipient != address(0), "Invalid recipient");
    feeRecipient = newRecipient;
  }

  /**
   * @notice Pause match creation
   */
  function pause() external onlyOwner {
    _pause();
  }

  /**
   * @notice Resume match creation
   */
  function unpause() external onlyOwner {
    _unpause();
  }

  /**
   * @notice Emergency cancel a stuck match
   */
  function emergencyCancelMatch(uint256 matchId) external onlyOwner {
    MatchInfo storage matchInfo = matches[matchId];
    require(
      matchInfo.status == MatchStatus.WAITING ||
        matchInfo.status == MatchStatus.PLAYING,
      "Match not active"
    );

    // Let the match contract handle refunds
    IGameMatch(matchInfo.matchContract).emergencyCancel();

    matchInfo.status = MatchStatus.CANCELLED;
    _handleMatchEnd(matchId);
  }

  // ==================== Internal Functions ====================

  /**
   * @notice Validate that caller is using session key
   */
  function _validateSessionKeyCaller() internal view returns (address) {
    // For session key calls, tx.origin is the session key
    // and msg.sender is the SessionKeyManager
    if (msg.sender == address(sessionKeyManager)) {
      // SessionKeyManager should pass the owner address
      // This would be implemented in the relay function
      return tx.origin; // Simplified - in production use proper validation
    }

    // For testing/development, allow direct calls
    return msg.sender;
  }

  /**
   * @notice Handle match ending - move to history
   */
  function _handleMatchEnd(uint256 matchId) internal {
    MatchInfo storage matchInfo = matches[matchId];

    // Move from active to history for all players
    for (uint256 i = 0; i < 4; i++) {
      address player = matchInfo.players[i];

      // Remove from active matches
      uint256[] storage active = playerActiveMatches[player];
      for (uint256 j = 0; j < active.length; j++) {
        if (active[j] == matchId) {
          active[j] = active[active.length - 1];
          active.pop();
          break;
        }
      }

      // Add to history
      playerMatchHistory[player].push(matchId);
    }
  }

  // ==================== Receive Function ====================

  receive() external payable {
    // Allow contract to receive ETH for stakes
  }
}
