// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockERC20.sol";

/**
 * @title MockBoltisToken
 * @notice Mock Boltis game token for testing
 * @dev Game-specific token with 18 decimals for rewards and staking
 */
contract MockBoltisToken is MockERC20 {
  constructor() MockERC20("Mock Boltis Token", "BOLTIS", 18, 10000000) {
    // Initial supply: 10,000,000 BOLTIS
  }

  /**
   * @notice Faucet function for easy testing - anyone can mint small amounts
   * @param amount Amount to mint (max 100 BOLTIS per call)
   */
  function faucet(uint256 amount) external {
    require(amount <= 100 * 10**18, "Max 100 BOLTIS per faucet call");
    _mint(msg.sender, amount);
  }

  /**
   * @notice Reward function for game contracts to mint rewards
   * @param player Address of the player to reward
   * @param amount Amount to reward
   */
  function reward(address player, uint256 amount) external onlyOwner {
    _mint(player, amount);
  }
}
