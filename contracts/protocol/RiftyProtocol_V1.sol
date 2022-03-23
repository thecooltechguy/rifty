// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../token/IERC721Rentable_V1.sol";
import "../token/ERC721Rentable_V1.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RiftyProtocol_V1 {

    struct Rental {
        bool active;
        uint256 numRentalDays;
        uint256 paidRentalCost;
        uint256 paidProtocolCost;
    }

    // TODO: Move from "days" as being the rental frequency to something more smaller/dynamic, like seconds
    struct Listing {
        bool active;
        address listingOwner;
        address tokenAddress;
        uint256 tokenId;
        address erc20ContractAddress;
        uint256 rentPerDay;
        uint256 maxRentalDays;
        bool strictlyFinishRentals; // If true, only the owner or renter can finish a rental. Otherwise, anyone can finish a rental (only when applicable/possible)
        Rental currentRental;
    }

    Listing[] private listings;
    uint protocolFeePercentBp = 250;

    uint constant NUM_SECONDS_PER_DAY = 86400;

    function createListing(address tokenAddress, uint256 tokenId, address erc20ContractAddress, uint rentPerDay, uint maxRentalDays, bool strictlyFinishRentals) public returns (uint) {        
        // Sanity check all values
        // the first check below should be changed once we switch to a more granular rental frequency vs. days
        require(maxRentalDays >= 1, "The maximum rental period cannot be less than 1");
        
        // Retrieve the token
        IERC721Rentable_V1 tokenContract = IERC721Rentable_V1(tokenAddress);
        
        // TODO: Ensure that it supports the rentable interface...

        // Ensure that the person creating this listing is the owner of this token
        require(msg.sender == tokenContract.ownerOf(tokenId), "Only the token owner can create a listing for it");

        Listing memory newListing = Listing({
            active: true,
            listingOwner: msg.sender,
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            erc20ContractAddress: erc20ContractAddress,
            rentPerDay: rentPerDay,
            maxRentalDays: maxRentalDays,
            strictlyFinishRentals:strictlyFinishRentals,
            currentRental: Rental({active: false, numRentalDays: 0, paidRentalCost:0, paidProtocolCost:0})
        });
        listings.push(newListing);

        return listings.length - 1;
    }

    function createRental(uint listingIndex, uint numRentalDays) public {
        require(numRentalDays > 0, "Cannot create a rental for 0 days");
        
        Listing memory listing = listings[listingIndex];
        require(listing.active, "Cannot create a rental from an inactive listing");
        require(numRentalDays <= listing.maxRentalDays, "Cannot create a rental longer than the listing's maximum rental period");

        IERC721Rentable_V1 tokenContract = IERC721Rentable_V1(listing.tokenAddress);

        // 1. Ensure the token isn't rented out
        require(!tokenContract.isRented(listing.tokenId), "Cannot create a rental for a token that is already rented out");

        // 2. Transfer the total cost from the renter to this protocol
        uint rentalCost = numRentalDays * listing.rentPerDay;
        uint protocolRevenue = rentalCost * protocolFeePercentBp / 100;
        uint totalCost = rentalCost + protocolRevenue;

        IERC20 erc20Contract = IERC20(listing.erc20ContractAddress);
        erc20Contract.transferFrom(msg.sender, address(this), totalCost);

        // 3. Rent out the token to the renter
        uint expiresAt = block.timestamp + (numRentalDays * NUM_SECONDS_PER_DAY);
        tokenContract.rentOut(msg.sender, listing.tokenId, expiresAt);

        // 4. Update the current rental for this listing
        listings[listingIndex].currentRental.active = true;
        listings[listingIndex].currentRental.numRentalDays = numRentalDays;
        listings[listingIndex].currentRental.paidRentalCost = rentalCost;
        listings[listingIndex].currentRental.paidProtocolCost = protocolRevenue;
    }
    
    function finishRental(uint listingIndex) public {
        uint currentTimestamp = block.timestamp;

        Listing memory listing = listings[listingIndex];
        require(listing.active, "Cannot finish a rental for an inactive listing");

        IERC721Rentable_V1 tokenContract = IERC721Rentable_V1(listing.tokenAddress);
        IERC20 erc20Contract = IERC20(listing.erc20ContractAddress);

        // Ensure that the token is currently being rented out
        require(tokenContract.isRented(listing.tokenId), "Cannot finish rental for a token that is not being rented");

        // Ensure that the token's approved address is this contract
        // This check exists because this contract can only finish rentals that were created by this contract.
        // In order for this contract to create a rental, it must have been the token's approved address.
        // And since renter's cannot change the token's approved address, this contract would remain as the token's approved address.
        require(tokenContract.getApproved(listing.tokenId) == address(this), "Cannot finish a rental that is not managed by this protocol");

        address _renter = tokenContract.ownerOf(listing.tokenId);

        if (listing.strictlyFinishRentals) {
            // When listing.strictlyFinishRentals is true,
            // only the token's renter (ie., the token's current owner) or listing creator can call this function
            // note: listing owner should be the same as the token's principal owner
            address renter = tokenContract.ownerOf(listing.tokenId);
            require(msg.sender == listing.listingOwner || msg.sender == renter, "Only the token's principal owner or renter can finish this rental");
        }

        uint rentalExpiresAt = tokenContract.getRentalExpiry(listing.tokenId);
        if (currentTimestamp < rentalExpiresAt) {
            require(msg.sender == _renter, "Only the renter can finish this rental before its expiry timestamp");

            // Get the rental's starting timestamp
            uint256 rentalStartedAt = tokenContract.getRentalStart(listing.tokenId);

            // Compute the number of days between rentalStartedAt and currentTimestamp
            uint256 numDaysRented = (currentTimestamp - rentalStartedAt) / NUM_SECONDS_PER_DAY;

            uint256 paidTotalCost = listing.currentRental.paidRentalCost + listing.currentRental.paidProtocolCost;
            uint256 revisedRentalCost = numDaysRented * listing.rentPerDay;
            uint256 revisedProtocolRevenue = revisedRentalCost * protocolFeePercentBp / 100;
            uint256 revisedTotalCost = revisedRentalCost + revisedProtocolRevenue;

            // Refund `paidTotalCost - revisedTotalCost` back to the renter
            erc20Contract.transferFrom(address(this), _renter, paidTotalCost - revisedTotalCost);
            
            // Transfer the revised rent amount to the listing owner
            erc20Contract.transferFrom(address(this), listing.listingOwner, revisedRentalCost);
        } else {
            // Transfer the paid rent amount to the listing owner
            erc20Contract.transferFrom(address(this), listing.listingOwner, listing.currentRental.paidRentalCost);
        }

        // Finish rental
        tokenContract.finishRental(listing.tokenId);

        // Clear the listing's current rental
        listings[listingIndex].currentRental.active = false;
        listing.currentRental.numRentalDays = 0;
        listing.currentRental.paidRentalCost = 0;
        listing.currentRental.paidProtocolCost = 0;
    }
}