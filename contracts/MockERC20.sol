// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing and development
 * @dev Basic ERC20 implementation with minting capabilities
 */
contract MockERC20 is ERC20, Ownable {
  uint8 private _decimals;

  constructor(
    string memory name,
    string memory symbol,
    uint8 decimals_,
    uint256 initialSupply
  ) ERC20(name, symbol) Ownable(msg.sender) {
    _decimals = decimals_;
    _mint(msg.sender, initialSupply * 10**decimals_);
  }

  /**
   * @notice Returns the number of decimals used to get its user representation
   */
  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }

  /**
   * @notice Mint tokens to specified address (only owner)
   * @param to Address to mint tokens to
   * @param amount Amount of tokens to mint (in wei)
   */
  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }

  /**
   * @notice Burn tokens from specified address (only owner)
   * @param from Address to burn tokens from
   * @param amount Amount of tokens to burn (in wei)
   */
  function burn(address from, uint256 amount) external onlyOwner {
    _burn(from, amount);
  }

  /**
   * @notice Mint tokens to multiple addresses at once
   * @param recipients Array of addresses to mint tokens to
   * @param amounts Array of amounts to mint to each address
   */
  function batchMint(address[] calldata recipients, uint256[] calldata amounts)
    external
    onlyOwner
  {
    require(recipients.length == amounts.length, "Arrays length mismatch");

    for (uint256 i = 0; i < recipients.length; i++) {
      _mint(recipients[i], amounts[i]);
    }
  }
}
