// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./IERC721Rentable.sol";

abstract contract ERC721Rentable is ERC721, IERC721Rentable {

    // struct containing info about the token's current rental
    struct TokenRental {
        bool isRented;
        address renter;
        address principalOwner;
        uint256 expiresAt;
        uint256 startsAt;
    }

    // mapping from token id to the corresponding TokenRental
    mapping(uint256 => TokenRental) _tokenRentals;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC721Rentable).interfaceId || super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal virtual override
    {
        // Call parent hook
        super._beforeTokenTransfer(from, to, tokenId);
        
        // Ensure that this token is NOT being rented before proceeding with the token transfer
        require(!_isRented(tokenId), "Token cannot be transferred while being rented");
    }

    function _isRented(uint256 tokenId) internal view returns (bool) {
        return _tokenRentals[tokenId].isRented;
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override(ERC721, IERC721) {
        // this check ensures that after this token has been rented out, 
        // the renter cannot change the approved address for this token
        // & prevent this token from being re-transfferred to the principal owner after the rental period is over
        require(!_isRented(tokenId), "Cannot approve an address for a rented token");
        super.approve(to, tokenId);
    }

    function rentOut(address renter, uint256 tokenId, uint256 expiresAt) external {
        require(_exists(tokenId), "Token id doesn't exist");
        require(!_isRented(tokenId), "Token cannot be rented out while being rented");

        address _owner = ownerOf(tokenId);        

        // transfer this token from the owner to the renter
        safeTransferFrom(_owner, renter, tokenId);

        // at this point, let's save this rental's information
        _tokenRentals[tokenId].renter = renter;
        _tokenRentals[tokenId].principalOwner = _owner;
        _tokenRentals[tokenId].startsAt = block.timestamp;
        _tokenRentals[tokenId].expiresAt = expiresAt;
        _tokenRentals[tokenId].isRented = true;

        // emit the Rented event
        emit Rented(tokenId, _owner, renter, expiresAt);
    }

    function finishRental(uint256 tokenId) external {
        require(_exists(tokenId), "Token id doesn't exist");
        require(_isRented(tokenId), "Token is not being rented");

        TokenRental memory _tokenRental = _tokenRentals[tokenId];

        address _principalOwner = _tokenRental.principalOwner;
        address _renter = _tokenRental.renter;
        address _tokenApprovedAddress = getApproved(tokenId);

        uint currentTimestamp = block.timestamp;
        uint256 _expiresAt = _tokenRental.expiresAt;

        if (_principalOwner == _tokenApprovedAddress) {
            // this rental is being done directly between the principal owner and the renter w/o any a 3rd party in the middle (e.g., a rental protocol, etc.)
            // in this case, msg.sender must be the principal owner or the renter
            require(
                msg.sender == _principalOwner || 
                msg.sender == _renter, "Only the principal owner or renter can finish this rental");

            if (currentTimestamp < _expiresAt) {
                // only the renter can finish this rental early
                require(msg.sender == _renter, "Only this token's renter can finish this rental before it expires");
            }
        } else {
            // this rental is being done between the principal owner and renter using a 3rd party (e.g., a rental protocol)
            // in this case, msg.sender must be the approved address for this token
            require(msg.sender == _tokenApprovedAddress, "Only the approved address for this token can finish this rental");
        }
        
        // at this point, let's finish this rental
        _tokenRentals[tokenId].renter = address(0);
        _tokenRentals[tokenId].principalOwner = address(0);
        _tokenRentals[tokenId].startsAt = 0;
        _tokenRentals[tokenId].expiresAt = 0;
        _tokenRentals[tokenId].isRented = false;

        safeTransferFrom(_renter, _principalOwner, tokenId);

        // emit the FinishedRental event
        emit FinishedRental(tokenId, _principalOwner, _renter, _expiresAt);
    }

    function principalOwner(uint256 tokenId) external view returns (address) {
        require(_exists(tokenId), "Token id doesn't exist");

        if (!_isRented(tokenId)) {
            // this token isn't being rented right now, 
            // so return the true owner of this token
            return ownerOf(tokenId);
        } else {
            // this token is being rented right now,
            // so return the principal owner
            return _tokenRentals[tokenId].principalOwner;
        }
    }

    function isRented(uint256 tokenId) external view returns (bool) {
        require(_exists(tokenId), "Token id doesn't exist");
        return _isRented(tokenId);
    }

    function getRentalExpiry(uint256 tokenId) external view returns (uint) {
        require(_exists(tokenId), "Token id doesn't exist");
        require(_isRented(tokenId), "Token is not being rented");
        return _tokenRentals[tokenId].expiresAt;
    }

    function getRentalStart(uint256 tokenId) external view returns (uint) {
        require(_exists(tokenId), "Token id doesn't exist");
        require(_isRented(tokenId), "Token is not being rented");
        return _tokenRentals[tokenId].startsAt;
    }
}