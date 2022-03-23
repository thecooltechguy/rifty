// SPDX-License-Identifier: MIT
// Adapted from source: https://github.com/ethereum/EIPs/pull/4884

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Rentable_V1 is IERC721 {
    /**
        @dev This event will be emitted when token is rented
        tokenId: token id to be rented
        owner:  principal owner address
        renter: renter address
        expiresAt:  end of renting period as timestamp
    */
    event Rented(uint256 indexed tokenId, address indexed owner, address indexed renter, uint256 expiresAt);

    /**
        @dev This event will be emitted when renting is finished by the owner or renter
        tokenId: token id to be rented
        owner:  principal owner address
        renter: renter address
        expiresAt:  end of renting period as timestamp
    */
    event FinishedRental(uint256 indexed tokenId, address indexed owner, address indexed renter, uint256 expiresAt);

    /**
        @notice rentOut
        @dev Rent a token to another address. This will change the owner.
        @param renter: renter address
        @param tokenId: token id to be rented
        @param expiresAt: end of renting period as timestamp 
    */
    function rentOut(address renter, uint256 tokenId, uint256 expiresAt) external;

    /**
        @notice finishRental
        @dev This will returns the token, back to the actual owner. Renter can run this anytime but owner can run after expire time.
             This is to be called by the token's renter or principal owner.
        @param tokenId: token id
    */
    function finishRental(uint256 tokenId) external;

    /**
        @notice principalOwner
        @dev  Get the actual owner of the rented token
        @param tokenId: token id
    */
    function principalOwner(uint256 tokenId) external returns (address);

    /**
        @notice isRented
        @dev  Get whether or not the token is rented
        @param tokenId: token id
    */
    function isRented(uint256 tokenId) external view returns (bool);

    /**
        @notice getRentalExpiry
        @dev  Returns the expiry timestamp of the token's current rental
        @param tokenId: token id
    */
    function getRentalExpiry(uint256 tokenId) external view returns (uint);

    /**
        @notice getRentalStart
        @dev  Returns the starting timestamp of the token's current rental
        @param tokenId: token id
    */
    function getRentalStart(uint256 tokenId) external view returns (uint);
}