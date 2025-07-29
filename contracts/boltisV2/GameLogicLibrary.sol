// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GameLogicLibrary
 * @notice Pure functions for card game logic - no state storage
 * @dev All game rules and calculations in one reusable library
 */
library GameLogicLibrary {
  // ==================== Constants ====================

  // Card types
  uint8 constant CARD_TYPE_NUMBER = 0;
  uint8 constant CARD_TYPE_SKIP = 1;
  uint8 constant CARD_TYPE_REVERSE = 2;
  uint8 constant CARD_TYPE_VOID = 3;
  uint8 constant CARD_TYPE_STRIKE = 4;
  uint8 constant CARD_TYPE_STACK = 5;
  uint8 constant CARD_TYPE_BOMB = 6;

  // Elements
  uint8 constant ELEMENT_FIRE = 0;
  uint8 constant ELEMENT_WATER = 1;
  uint8 constant ELEMENT_PLANT = 2;
  uint8 constant ELEMENT_THUNDER = 3;

  // ==================== Structs ====================

  struct Card {
    uint8 cardType;
    uint8 element;
    uint8 value; // For number cards (0-9)
  }

  // ==================== Pure Functions ====================

  /**
   * @notice Check if a card can be played on top of another card
   * @param cardToPlay The card the player wants to play
   * @param topCard The current top card on the discard pile
   * @param voidActive Whether a void card effect is active
   * @param voidSelectedColor The color selected by void card
   * @return canPlay Whether the card can be played
   */
  function canPlayCard(
    Card memory cardToPlay,
    Card memory topCard,
    bool voidActive,
    uint8 voidSelectedColor
  ) internal pure returns (bool canPlay) {
    // Void card can always be played
    if (cardToPlay.cardType == CARD_TYPE_VOID) {
      return true;
    }

    // If void is active, only the selected color can be played
    if (voidActive) {
      return cardToPlay.element == voidSelectedColor;
    }

    // Bomb cards have special rules (optional feature)
    if (cardToPlay.cardType == CARD_TYPE_BOMB) {
      return _canPlayBomb(cardToPlay, topCard);
    }

    // Same element always matches
    if (cardToPlay.element == topCard.element) {
      return true;
    }

    // For number cards, same value matches
    if (
      cardToPlay.cardType == CARD_TYPE_NUMBER &&
      topCard.cardType == CARD_TYPE_NUMBER &&
      cardToPlay.value == topCard.value
    ) {
      return true;
    }

    // For special cards, same type matches
    if (
      cardToPlay.cardType != CARD_TYPE_NUMBER &&
      topCard.cardType != CARD_TYPE_NUMBER &&
      cardToPlay.cardType == topCard.cardType
    ) {
      return true;
    }

    return false;
  }

  /**
   * @notice Calculate the next player index based on direction and special effects
   * @param currentIndex Current player index
   * @param direction Game direction (1 or -1)
   * @param playerCount Total number of players
   * @param skipNext Whether to skip the next player
   * @return nextIndex The next player's index
   */
  function getNextPlayerIndex(
    uint8 currentIndex,
    int8 direction,
    uint8 playerCount,
    bool skipNext
  ) internal pure returns (uint8 nextIndex) {
    require(playerCount > 0, "Invalid player count");
    require(currentIndex < playerCount, "Invalid current index");
    require(direction == 1 || direction == -1, "Invalid direction");

    // Calculate next index with direction
    if (direction == 1) {
      nextIndex = (currentIndex + 1) % playerCount;
    } else {
      nextIndex = currentIndex == 0 ? playerCount - 1 : currentIndex - 1;
    }

    // Apply skip if needed
    if (skipNext) {
      if (direction == 1) {
        nextIndex = (nextIndex + 1) % playerCount;
      } else {
        nextIndex = nextIndex == 0 ? playerCount - 1 : nextIndex - 1;
      }
    }

    return nextIndex;
  }

  /**
   * @notice Calculate score for a hand of cards
   * @param cards Array of cards in hand
   * @return score Total score
   */
  function calculateHandScore(Card[] memory cards)
    internal
    pure
    returns (uint256 score)
  {
    for (uint256 i = 0; i < cards.length; i++) {
      score += getCardValue(cards[i]);
    }
    return score;
  }

  /**
   * @notice Get point value of a single card
   * @param card The card to evaluate
   * @return value Point value
   */
  function getCardValue(Card memory card)
    internal
    pure
    returns (uint256 value)
  {
    if (card.cardType == CARD_TYPE_NUMBER) {
      return card.value; // 0-9 points
    } else if (
      card.cardType == CARD_TYPE_SKIP || card.cardType == CARD_TYPE_REVERSE
    ) {
      return 20; // Special cards worth 20
    } else if (card.cardType == CARD_TYPE_VOID) {
      return 50; // Void cards worth 50
    } else if (
      card.cardType == CARD_TYPE_STRIKE || card.cardType == CARD_TYPE_STACK
    ) {
      return 30; // Advanced special cards
    } else if (card.cardType == CARD_TYPE_BOMB) {
      return 40; // Bomb cards worth 40
    }
    return 0;
  }

  /**
   * @notice Check if the game should end (winner conditions)
   * @param playerCardCounts Array of card counts per player
   * @param playerEliminated Array of elimination status
   * @return hasWinner Whether there's a winner
   * @return winnerIndex Index of the winner
   */
  function checkWinCondition(
    uint8[] memory playerCardCounts,
    bool[] memory playerEliminated
  ) internal pure returns (bool hasWinner, uint8 winnerIndex) {
    uint8 activePlayers = 0;
    uint8 lastActiveIndex = 0;

    for (uint8 i = 0; i < playerCardCounts.length; i++) {
      if (!playerEliminated[i]) {
        // Check for empty hand (instant win)
        if (playerCardCounts[i] == 0) {
          return (true, i);
        }
        activePlayers++;
        lastActiveIndex = i;
      }
    }

    // If only one player remains, they win
    if (activePlayers <= 1) {
      return (true, lastActiveIndex);
    }

    return (false, 0);
  }

  /**
   * @notice Get elemental advantage bonus
   * @param attackElement Attacking element
   * @param defendElement Defending element
   * @return hasAdvantage Whether attacker has advantage
   */
  function getElementalAdvantage(uint8 attackElement, uint8 defendElement)
    internal
    pure
    returns (bool hasAdvantage)
  {
    // Fire > Plant, Plant > Water, Water > Fire, Thunder is neutral
    if (attackElement == ELEMENT_FIRE && defendElement == ELEMENT_PLANT)
      return true;
    if (attackElement == ELEMENT_PLANT && defendElement == ELEMENT_WATER)
      return true;
    if (attackElement == ELEMENT_WATER && defendElement == ELEMENT_FIRE)
      return true;
    return false;
  }

  /**
   * @notice Validate initial game settings
   * @param playerCount Number of players
   * @param cardsPerPlayer Cards dealt to each player
   * @param turnTimeLimit Seconds per turn
   * @return valid Whether settings are valid
   * @return reason Error message if invalid
   */
  function validateGameSettings(
    uint8 playerCount,
    uint8 cardsPerPlayer,
    uint256 turnTimeLimit
  ) internal pure returns (bool valid, string memory reason) {
    if (playerCount < 2 || playerCount > 4) {
      return (false, "Player count must be 2-4");
    }

    if (cardsPerPlayer < 5 || cardsPerPlayer > 10) {
      return (false, "Cards per player must be 5-10");
    }

    if (turnTimeLimit < 10 || turnTimeLimit > 300) {
      return (false, "Turn time must be 10-300 seconds");
    }

    // Check if we have enough cards for the game
    uint256 totalCardsNeeded = uint256(playerCount) *
      uint256(cardsPerPlayer) +
      20; // +20 for draw pile
    uint256 deckSize = 108; // Standard UNO-style deck size

    if (totalCardsNeeded > deckSize) {
      return (false, "Not enough cards in deck");
    }

    return (true, "");
  }

  /**
   * @notice Calculate timeout penalty
   * @param currentCards Current number of cards
   * @param penaltyCards Base penalty amount
   * @return newCardCount Cards after penalty
   */
  function applyTimeoutPenalty(uint8 currentCards, uint8 penaltyCards)
    internal
    pure
    returns (uint8 newCardCount)
  {
    uint16 total = uint16(currentCards) + uint16(penaltyCards);
    // Cap at 255 to prevent overflow
    return total > 255 ? 255 : uint8(total);
  }

  // ==================== Internal Helper Functions ====================

  /**
   * @notice Special rules for bomb cards
   */
  function _canPlayBomb(Card memory bombCard, Card memory topCard)
    private
    pure
    returns (bool)
  {
    // Bomb can be played if element matches or if top card is also a bomb
    return
      bombCard.element == topCard.element || topCard.cardType == CARD_TYPE_BOMB;
  }

  /**
   * @notice Generate a deterministic shuffle seed
   * @dev Used for generating random but deterministic game states
   */
  function generateShuffleSeed(address[] memory players, uint256 timestamp)
    internal
    pure
    returns (uint256)
  {
    return uint256(keccak256(abi.encodePacked(players, timestamp)));
  }

  /**
   * @notice Determine starting player index
   */
  function selectStartingPlayer(uint256 seed, uint8 playerCount)
    internal
    pure
    returns (uint8)
  {
    return uint8(seed % playerCount);
  }
}
