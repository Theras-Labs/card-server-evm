// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ==================== interfaces/IMatchRegistry.sol ====================

interface IMatchRegistry {
  enum MatchStatus {
    WAITING,
    PLAYING,
    COMPLETED,
    CANCELLED,
    EXPIRED
  }

  function updateMatchStatus(uint256 matchId, MatchStatus status) external;

  function reportWinner(uint256 matchId, address winner) external;
}
