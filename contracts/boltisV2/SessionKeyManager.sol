// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SessionKeyManager
 * @notice Manages session keys for gasless transactions across all game contracts
 * @dev Supports EIP-712 typed signatures for secure session key operations
 */
contract SessionKeyManager is EIP712, ReentrancyGuard {
  using ECDSA for bytes32;

  // ==================== Types ====================

  struct SessionKey {
    address keyAddress;
    uint256 nonce;
    uint256 dailyGasLimit;
    uint256 dailyGasUsed;
    uint256 lastResetDay;
    bool active;
    mapping(address => bool) authorizedContracts;
  }

  struct SessionKeyView {
    address keyAddress;
    uint256 nonce;
    uint256 dailyGasLimit;
    uint256 dailyGasUsed;
    uint256 lastResetDay;
    bool active;
  }

  // ==================== State ====================

  mapping(address => SessionKey) public sessionKeys;
  mapping(address => address[]) public userAuthorizedContracts;

  // ==================== Events ====================

  event SessionKeyCreated(
    address indexed owner,
    address indexed sessionKey,
    uint256 dailyGasLimit
  );

  event SessionKeyRevoked(address indexed owner, address indexed sessionKey);

  event ContractAuthorized(
    address indexed owner,
    address indexed sessionKey,
    address indexed authorizedContract
  );

  event ActionRelayed(
    address indexed owner,
    address indexed sessionKey,
    address indexed targetContract,
    bool success
  );

  // ==================== Type Hashes ====================

  bytes32 private constant RELAY_TYPEHASH =
    keccak256(
      "RelayAction(address owner,address target,uint256 value,bytes data,uint256 nonce)"
    );

  // ==================== Constructor ====================

  constructor() EIP712("SessionKeyManager", "1") {}

  // ==================== Public Functions ====================

  /**
   * @notice Create or update a session key for the caller
   * @param _sessionKey Address of the session key wallet
   * @param _dailyGasLimit Daily gas limit in wei (0 = unlimited)
   * @param _authorizedContracts Initial list of authorized contracts
   */
  function createSessionKey(
    address _sessionKey,
    uint256 _dailyGasLimit,
    address[] calldata _authorizedContracts
  ) external {
    require(_sessionKey != address(0), "Invalid session key");
    require(_sessionKey != msg.sender, "Session key cannot be owner");

    // Revoke existing session key if active
    if (sessionKeys[msg.sender].active) {
      emit SessionKeyRevoked(msg.sender, sessionKeys[msg.sender].keyAddress);
    }

    // Create new session key
    SessionKey storage sk = sessionKeys[msg.sender];
    sk.keyAddress = _sessionKey;
    sk.nonce = 0;
    sk.dailyGasLimit = _dailyGasLimit;
    sk.dailyGasUsed = 0;
    sk.lastResetDay = block.timestamp / 86400;
    sk.active = true;

    // Clear previous authorizations
    address[] storage prevAuthorized = userAuthorizedContracts[msg.sender];
    for (uint256 i = 0; i < prevAuthorized.length; i++) {
      sk.authorizedContracts[prevAuthorized[i]] = false;
    }
    delete userAuthorizedContracts[msg.sender];

    // Set new authorizations
    for (uint256 i = 0; i < _authorizedContracts.length; i++) {
      require(
        _authorizedContracts[i] != address(0),
        "Invalid contract address"
      );
      sk.authorizedContracts[_authorizedContracts[i]] = true;
      userAuthorizedContracts[msg.sender].push(_authorizedContracts[i]);

      emit ContractAuthorized(msg.sender, _sessionKey, _authorizedContracts[i]);
    }

    emit SessionKeyCreated(msg.sender, _sessionKey, _dailyGasLimit);
  }

  /**
   * @notice Authorize additional contracts for existing session key
   * @param _contracts Contracts to authorize
   */
  function authorizeContracts(address[] calldata _contracts) external {
    SessionKey storage sk = sessionKeys[msg.sender];
    require(sk.active, "No active session key");

    for (uint256 i = 0; i < _contracts.length; i++) {
      require(_contracts[i] != address(0), "Invalid contract address");
      if (!sk.authorizedContracts[_contracts[i]]) {
        sk.authorizedContracts[_contracts[i]] = true;
        userAuthorizedContracts[msg.sender].push(_contracts[i]);

        emit ContractAuthorized(msg.sender, sk.keyAddress, _contracts[i]);
      }
    }
  }

  /**
   * @notice Relay an action from a session key
   * @param _owner Owner of the session key
   * @param _target Target contract
   * @param _value ETH value to send
   * @param _data Function calldata
   * @param _signature Session key signature
   */
  function relay(
    address _owner,
    address _target,
    uint256 _value,
    bytes calldata _data,
    bytes calldata _signature
  ) external payable nonReentrant returns (bool success, bytes memory result) {
    // Start gas tracking
    uint256 gasStart = gasleft();

    // Validate session key
    SessionKey storage sk = sessionKeys[_owner];
    require(sk.active, "No active session key");
    require(sk.authorizedContracts[_target], "Target not authorized");

    // Verify signature
    bytes32 structHash = keccak256(
      abi.encode(
        RELAY_TYPEHASH,
        _owner,
        _target,
        _value,
        keccak256(_data),
        sk.nonce++
      )
    );

    bytes32 hash = _hashTypedDataV4(structHash);
    address signer = hash.recover(_signature);
    require(signer == sk.keyAddress, "Invalid signature");

    // Check and update gas limits
    _checkAndUpdateGasLimit(sk, gasStart);

    // Execute the call
    require(msg.value >= _value, "Insufficient value");
    (success, result) = _target.call{ value: _value }(_data);

    emit ActionRelayed(_owner, sk.keyAddress, _target, success);

    // Refund excess ETH
    if (msg.value > _value) {
      (bool refunded, ) = msg.sender.call{ value: msg.value - _value }("");
      require(refunded, "Refund failed");
    }
  }

  /**
   * @notice Revoke the active session key
   */
  function revokeSessionKey() external {
    SessionKey storage sk = sessionKeys[msg.sender];
    require(sk.active, "No active session key");

    address sessionKeyAddr = sk.keyAddress;
    sk.active = false;

    emit SessionKeyRevoked(msg.sender, sessionKeyAddr);
  }

  /**
   * @notice Fund a session key with ETH
   * @param _owner Owner of the session key to fund
   */
  function fundSessionKey(address _owner) external payable {
    require(msg.value > 0, "Must send ETH");
    SessionKey storage sk = sessionKeys[_owner];
    require(sk.active, "No active session key");

    (bool success, ) = sk.keyAddress.call{ value: msg.value }("");
    require(success, "Transfer failed");
  }

  // ==================== View Functions ====================

  /**
   * @notice Get session key info for an owner
   */
  function getSessionKey(address _owner)
    external
    view
    returns (SessionKeyView memory)
  {
    SessionKey storage sk = sessionKeys[_owner];
    return
      SessionKeyView({
        keyAddress: sk.keyAddress,
        nonce: sk.nonce,
        dailyGasLimit: sk.dailyGasLimit,
        dailyGasUsed: sk.dailyGasUsed,
        lastResetDay: sk.lastResetDay,
        active: sk.active
      });
  }

  /**
   * @notice Check if an owner has an active session key
   */
  function hasActiveSessionKey(address _owner) external view returns (bool) {
    return sessionKeys[_owner].active;
  }

  /**
   * @notice Check if a contract is authorized for a session key
   */
  function isContractAuthorized(address _owner, address _contract)
    external
    view
    returns (bool)
  {
    return sessionKeys[_owner].authorizedContracts[_contract];
  }

  /**
   * @notice Get all authorized contracts for an owner
   */
  function getAuthorizedContracts(address _owner)
    external
    view
    returns (address[] memory)
  {
    return userAuthorizedContracts[_owner];
  }

  /**
   * @notice Get session key balance
   */
  function getSessionKeyBalance(address _owner)
    external
    view
    returns (uint256)
  {
    if (!sessionKeys[_owner].active) return 0;
    return sessionKeys[_owner].keyAddress.balance;
  }

  /**
   * @notice Validate a session key action (for external contracts to call)
   * @dev This allows contracts to validate without executing relay
   */
  function validateSessionKeyAction(address _owner, address _caller)
    external
    view
    returns (bool)
  {
    SessionKey storage sk = sessionKeys[_owner];
    return sk.active && sk.keyAddress == _caller;
  }

  // ==================== Internal Functions ====================

  /**
   * @notice Check and update gas limit for session key
   */
  function _checkAndUpdateGasLimit(SessionKey storage sk, uint256 gasStart)
    internal
  {
    if (sk.dailyGasLimit == 0) return; // Unlimited

    // Reset daily usage if needed
    uint256 currentDay = block.timestamp / 86400;
    if (currentDay > sk.lastResetDay) {
      sk.dailyGasUsed = 0;
      sk.lastResetDay = currentDay;
    }

    // Estimate gas cost (conservative estimate)
    uint256 gasUsed = (gasStart - gasleft() + 50000) * tx.gasprice;
    require(
      sk.dailyGasUsed + gasUsed <= sk.dailyGasLimit,
      "Daily gas limit exceeded"
    );

    sk.dailyGasUsed += gasUsed;
  }

  // ==================== Receive Function ====================

  receive() external payable {
    // Allow contract to receive ETH for funding session keys
  }
}
