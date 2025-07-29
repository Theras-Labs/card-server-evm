// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ==================== interfaces/IGameMatch.sol ====================

interface IGameMatch {
  struct GameSettings {
    uint8 cardsPerPlayer;
    uint256 turnTimeLimit;
    uint256 matchDuration;
    bool pauseEnabled;
    uint8 penaltyCards;
  }

  function initialize(
    uint256 matchId,
    address[4] memory players,
    address host,
    GameSettings memory settings,
    uint256 stakePerPlayer,
    address sessionKeyManager,
    address matchRegistry
  ) external;

  function joinMatch() external payable;

  function executeAction(uint8 actionType, bytes calldata actionData) external;

  function handleTimeout() external;

  function emergencyCancel() external;

  function distributePrize(
    address winner,
    uint256 winnerAmount,
    address platformFeeRecipient,
    uint256 platformFee
  ) external;
}
