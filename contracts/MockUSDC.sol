// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockERC20.sol";

/**
 * @title MockUSDC
 * @notice Mock USDC token for testing
 * @dev Mimics USDC with 6 decimals and standard supply
 */
contract MockUSDC is MockERC20 {
  constructor() MockERC20("Mock USD Coin", "USDC", 6, 1000000) {
    // Initial supply: 1,000,000 USDC
  }

  /**
   * @notice Faucet function for easy testing - anyone can mint small amounts
   * @param amount Amount to mint (max 1000 USDC per call)
   */
  function faucet(uint256 amount) external {
    require(amount <= 1000 * 10**6, "Max 1000 USDC per faucet call");
    _mint(msg.sender, amount);
  }
}
