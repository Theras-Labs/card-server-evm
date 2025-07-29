// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockERC20.sol";

/**
 * @title MockUSDT
 * @notice Mock Tether USD token for testing
 * @dev Mimics USDT with 6 decimals
 */
contract MockUSDT is MockERC20 {
  constructor() MockERC20("Mock Tether USD", "USDT", 6, 1000000) {
    // Initial supply: 1,000,000 USDT
  }

  /**
   * @notice Faucet function for easy testing - anyone can mint small amounts
   * @param amount Amount to mint (max 1000 USDT per call)
   */
  function faucet(uint256 amount) external {
    require(amount <= 1000 * 10**6, "Max 1000 USDT per faucet call");
    _mint(msg.sender, amount);
  }
}
