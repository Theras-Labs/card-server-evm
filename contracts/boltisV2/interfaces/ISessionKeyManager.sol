// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ==================== interfaces/ISessionKeyManager.sol ====================

interface ISessionKeyManager {
  function validateSessionKeyAction(address owner, address caller)
    external
    view
    returns (bool);

  function hasActiveSessionKey(address owner) external view returns (bool);

  function getSessionKeyBalance(address owner) external view returns (uint256);

  function relay(
    address owner,
    address target,
    uint256 value,
    bytes calldata data,
    bytes calldata signature
  ) external payable returns (bool success, bytes memory result);
}
