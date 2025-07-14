// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title BoltisGameRoom - Simplified Game Room & Prize Management
 * @dev Handles room creation, joining with fees, and prize distribution
 * Game logic is handled client-side
 */
contract BoltisGameRoom is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    
    // ================================
    // ENUMS & STRUCTS
    // ================================
    
    enum GameStatus { Waiting, Playing, Ended }
    
    struct GameRoom {
        uint256 roomId;
        address creator;
        address[4] players;
        uint8 playerCount;
        uint256 entryFee;
        uint256 prizePool;
        GameStatus status;
        uint256 createdAt;
        uint256 startedAt;
        uint256 endedAt;
        address winner;
        bool exists;
        string roomName;
        uint8 maxPlayers;
    }
    
    struct PlayerStats {
        uint256 gamesPlayed;
        uint256 gamesWon;
        uint256 totalEarnings;
        uint256 totalSpent;
    }
    
    // ================================
    // STATE VARIABLES
    // ================================
    
    Counters.Counter private _roomIdCounter;
    
    // Room ID => Game Room
    mapping(uint256 => GameRoom) public gameRooms;
    
    // Player address => Current Room ID (0 if not in game)
    mapping(address => uint256) public playerToRoom;
    
    // Player address => Player Stats
    mapping(address => PlayerStats) public playerStats;
    
    // Available rooms for quick join
    uint256[] public availableRooms;
    
    // Fee settings
    uint256 public platformFeePercent = 5; // 5% platform fee
    uint256 public minEntryFee = 0.001 ether;
    uint256 public maxEntryFee = 1 ether;
    
    // Platform earnings
    uint256 public platformEarnings;
    
    // ================================
    // EVENTS
    // ================================
    
    event RoomCreated(
        uint256 indexed roomId, 
        address indexed creator, 
        uint256 entryFee,
        string roomName,
        uint8 maxPlayers
    );
    
    event PlayerJoined(
        uint256 indexed roomId, 
        address indexed player, 
        uint8 playerIndex,
        uint256 amountPaid
    );
    
    event GameStarted(
        uint256 indexed roomId, 
        address[4] players,
        uint256 prizePool
    );
    
    event GameEnded(
        uint256 indexed roomId, 
        address indexed winner,
        uint256 prize,
        uint256 platformFee
    );
    
    event PlayerLeft(
        uint256 indexed roomId, 
        address indexed player
    );
    
    // ================================
    // MODIFIERS
    // ================================
    
    modifier roomExists(uint256 roomId) {
        require(gameRooms[roomId].exists, "Room does not exist");
        _;
    }
    
    modifier playerInRoom(uint256 roomId) {
        require(playerToRoom[msg.sender] == roomId, "Not in this room");
        _;
    }
    
    modifier roomStatus(uint256 roomId, GameStatus expectedStatus) {
        require(gameRooms[roomId].status == expectedStatus, "Invalid room status");
        _;
    }
    
    modifier validEntryFee(uint256 fee) {
        require(fee >= minEntryFee && fee <= maxEntryFee, "Invalid entry fee");
        _;
    }
    
    // ================================
    // ROOM MANAGEMENT
    // ================================
    
    /**
     * @dev Create a new game room
     */
    function createRoom(
        string memory roomName,
        uint256 entryFee,
        uint8 maxPlayers
    ) external payable nonReentrant validEntryFee(entryFee) returns (uint256) {
        require(playerToRoom[msg.sender] == 0, "Already in a room");
        require(msg.value == entryFee, "Incorrect entry fee");
        require(maxPlayers >= 2 && maxPlayers <= 4, "Invalid max players");
        require(bytes(roomName).length > 0, "Room name required");
        
        _roomIdCounter.increment();
        uint256 roomId = _roomIdCounter.current();
        
        GameRoom storage room = gameRooms[roomId];
        room.roomId = roomId;
        room.creator = msg.sender;
        room.players[0] = msg.sender;
        room.playerCount = 1;
        room.entryFee = entryFee;
        room.prizePool = entryFee;
        room.status = GameStatus.Waiting;
        room.createdAt = block.timestamp;
        room.exists = true;
        room.roomName = roomName;
        room.maxPlayers = maxPlayers;
        
        playerToRoom[msg.sender] = roomId;
        availableRooms.push(roomId);
        
        // Update player stats
        playerStats[msg.sender].totalSpent += entryFee;
        
        emit RoomCreated(roomId, msg.sender, entryFee, roomName, maxPlayers);
        emit PlayerJoined(roomId, msg.sender, 0, entryFee);
        
        return roomId;
    }
    
    /**
     * @dev Join an existing room
     */
    function joinRoom(uint256 roomId) 
        external 
        payable 
        nonReentrant 
        roomExists(roomId) 
        roomStatus(roomId, GameStatus.Waiting) 
    {
        require(playerToRoom[msg.sender] == 0, "Already in a room");
        
        GameRoom storage room = gameRooms[roomId];
        require(room.playerCount < room.maxPlayers, "Room is full");
        require(msg.value == room.entryFee, "Incorrect entry fee");
        
        // Add player to room
        room.players[room.playerCount] = msg.sender;
        room.playerCount++;
        room.prizePool += msg.value;
        
        playerToRoom[msg.sender] = roomId;
        
        // Update player stats
        playerStats[msg.sender].totalSpent += msg.value;
        
        emit PlayerJoined(roomId, msg.sender, room.playerCount - 1, msg.value);
        
        // Auto-start game if room is full
        if (room.playerCount == room.maxPlayers) {
            _startGame(roomId);
        }
    }
    
    /**
     * @dev Quick join any available room or create one
     */
    function quickJoin(
        string memory roomName,
        uint256 entryFee,
        uint8 maxPlayers
    ) external payable nonReentrant returns (uint256) {
        require(playerToRoom[msg.sender] == 0, "Already in a room");
        
        // Try to find an available room with matching entry fee
        for (uint i = 0; i < availableRooms.length; i++) {
            uint256 roomId = availableRooms[i];
            GameRoom storage room = gameRooms[roomId];
            
            if (room.status == GameStatus.Waiting && 
                room.playerCount < room.maxPlayers &&
                room.entryFee == entryFee) {
                
                // Join this room
                require(msg.value == room.entryFee, "Incorrect entry fee");
                
                room.players[room.playerCount] = msg.sender;
                room.playerCount++;
                room.prizePool += msg.value;
                
                playerToRoom[msg.sender] = roomId;
                playerStats[msg.sender].totalSpent += msg.value;
                
                emit PlayerJoined(roomId, msg.sender, room.playerCount - 1, msg.value);
                
                if (room.playerCount == room.maxPlayers) {
                    _startGame(roomId);
                }
                
                return roomId;
            }
        }
        
        // No suitable room found, create new one
        return createRoom(roomName, entryFee, maxPlayers);
    }
    
    /**
     * @dev Leave a room (only if game hasn't started)
     */
    function leaveRoom(uint256 roomId) 
        external 
        nonReentrant 
        roomExists(roomId) 
        playerInRoom(roomId) 
        roomStatus(roomId, GameStatus.Waiting) 
    {
        GameRoom storage room = gameRooms[roomId];
        
        // Find player and remove
        uint8 playerIndex = 255; // Invalid index
        for (uint8 i = 0; i < room.playerCount; i++) {
            if (room.players[i] == msg.sender) {
                playerIndex = i;
                break;
            }
        }
        
        require(playerIndex != 255, "Player not found");
        
        // Refund entry fee
        uint256 refund = room.entryFee;
        room.prizePool -= refund;
        
        // Remove player from array
        for (uint8 i = playerIndex; i < room.playerCount - 1; i++) {
            room.players[i] = room.players[i + 1];
        }
        room.players[room.playerCount - 1] = address(0);
        room.playerCount--;
        
        playerToRoom[msg.sender] = 0;
        playerStats[msg.sender].totalSpent -= refund;
        
        // If room is empty, mark as ended
        if (room.playerCount == 0) {
            room.status = GameStatus.Ended;
            _removeFromAvailableRooms(roomId);
        }
        
        // Send refund
        payable(msg.sender).transfer(refund);
        
        emit PlayerLeft(roomId, msg.sender);
    }
    
    // ================================
    // GAME FLOW
    // ================================
    
    /**
     * @dev Start the game (internal)
     */
    function _startGame(uint256 roomId) internal {
        GameRoom storage room = gameRooms[roomId];
        room.status = GameStatus.Playing;
        room.startedAt = block.timestamp;
        
        _removeFromAvailableRooms(roomId);
        
        // Update player stats
        for (uint8 i = 0; i < room.playerCount; i++) {
            playerStats[room.players[i]].gamesPlayed++;
        }
        
        emit GameStarted(roomId, room.players, room.prizePool);
    }
    
    /**
     * @dev Manually start game (for creator)
     */
    function startGame(uint256 roomId) 
        external 
        roomExists(roomId) 
        roomStatus(roomId, GameStatus.Waiting) 
    {
        GameRoom storage room = gameRooms[roomId];
        require(msg.sender == room.creator, "Only creator can start");
        require(room.playerCount >= 2, "Need at least 2 players");
        
        _startGame(roomId);
    }
    
    /**
     * @dev End game and distribute prizes (called by winner)
     */
    function endGame(uint256 roomId, address winner) 
        external 
        roomExists(roomId) 
        playerInRoom(roomId) 
        roomStatus(roomId, GameStatus.Playing) 
    {
        GameRoom storage room = gameRooms[roomId];
        
        // Verify winner is a player in the room
        bool isValidWinner = false;
        for (uint8 i = 0; i < room.playerCount; i++) {
            if (room.players[i] == winner) {
                isValidWinner = true;
                break;
            }
        }
        require(isValidWinner, "Invalid winner");
        
        // Calculate fees and prize
        uint256 platformFee = (room.prizePool * platformFeePercent) / 100;
        uint256 winnerPrize = room.prizePool - platformFee;
        
        // Update room state
        room.status = GameStatus.Ended;
        room.endedAt = block.timestamp;
        room.winner = winner;
        
        // Update platform earnings
        platformEarnings += platformFee;
        
        // Update winner stats
        playerStats[winner].gamesWon++;
        playerStats[winner].totalEarnings += winnerPrize;
        
        // Clear player room mappings
        for (uint8 i = 0; i < room.playerCount; i++) {
            playerToRoom[room.players[i]] = 0;
        }
        
        // Transfer prize to winner
        payable(winner).transfer(winnerPrize);
        
        emit GameEnded(roomId, winner, winnerPrize, platformFee);
    }
    
    // ================================
    // VIEW FUNCTIONS
    // ================================
    
    function getRoom(uint256 roomId) external view returns (GameRoom memory) {
        return gameRooms[roomId];
    }
    
    function getAvailableRooms() external view returns (uint256[] memory) {
        // Filter out non-waiting rooms
        uint256 validCount = 0;
        for (uint i = 0; i < availableRooms.length; i++) {
            if (gameRooms[availableRooms[i]].status == GameStatus.Waiting) {
                validCount++;
            }
        }
        
        uint256[] memory validRooms = new uint256[](validCount);
        uint256 index = 0;
        for (uint i = 0; i < availableRooms.length; i++) {
            if (gameRooms[availableRooms[i]].status == GameStatus.Waiting) {
                validRooms[index] = availableRooms[i];
                index++;
            }
        }
        
        return validRooms;
    }
    
    function getRoomPlayers(uint256 roomId) external view returns (address[4] memory) {
        return gameRooms[roomId].players;
    }
    
    function getPlayerStats(address player) external view returns (PlayerStats memory) {
        return playerStats[player];
    }
    
    function getCurrentRoomId(address player) external view returns (uint256) {
        return playerToRoom[player];
    }
    
    function getRoomCount() external view returns (uint256) {
        return _roomIdCounter.current();
    }
    
    // ================================
    // ADMIN FUNCTIONS
    // ================================
    
    function setPlatformFee(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= 20, "Fee too high"); // Max 20%
        platformFeePercent = newFeePercent;
    }
    
    function setEntryFeeLimits(uint256 minFee, uint256 maxFee) external onlyOwner {
        require(minFee < maxFee, "Invalid fee range");
        minEntryFee = minFee;
        maxEntryFee = maxFee;
    }
    
    function withdrawPlatformEarnings() external onlyOwner {
        uint256 amount = platformEarnings;
        platformEarnings = 0;
        payable(owner()).transfer(amount);
    }
    
    function emergencyEndGame(uint256 roomId) external onlyOwner roomExists(roomId) {
        GameRoom storage room = gameRooms[roomId];
        
        // Refund all players
        uint256 refundPerPlayer = room.prizePool / room.playerCount;
        for (uint8 i = 0; i < room.playerCount; i++) {
            if (room.players[i] != address(0)) {
                playerToRoom[room.players[i]] = 0;
                payable(room.players[i]).transfer(refundPerPlayer);
            }
        }
        
        room.status = GameStatus.Ended;
        room.endedAt = block.timestamp;
        
        _removeFromAvailableRooms(roomId);
    }
    
    // ================================
    // INTERNAL UTILITIES
    // ================================
    
    function _removeFromAvailableRooms(uint256 roomId) internal {
        for (uint i = 0; i < availableRooms.length; i++) {
            if (availableRooms[i] == roomId) {
                availableRooms[i] = availableRooms[availableRooms.length - 1];
                availableRooms.pop();
                break;
            }
        }
    }
    
    // ================================
    // EMERGENCY FUNCTIONS
    // ================================
    
    receive() external payable {
        revert("Direct payments not accepted");
    }
}