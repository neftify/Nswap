// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Nswap is Ownable, Pausable {

    // Version helper for migrations
    uint256 migrateVersion;

    address public acceptedPayTokenAddress;
    uint256 public protocolFeesPercent;

    struct NswapForLend {
        uint256 durationHours;
        uint256 initialWorth;
        uint256 defiTokens;
        uint256 borrowedAtTimestamp;
        address lender;
        address borrower;
        bool lenderClaimedCollateral;
        uint256 protocolFeesPercent;
    }
    mapping(address => mapping(uint256 => NswapForLend)) public lentNswapList;

    struct NswapTokenEntry {
        address lenderAddress;
        address tokenAddress;
        uint256 tokenId;
    }
    NswapTokenEntry[] public lendersWithTokens;

    event NswapForLendUpdated(address tokenAddress, uint256 tokenId);
    event NswapForLendRemoved(address tokenAddress, uint256 tokenId);

    function pauseSmartContract() public onlyOwner whenNotPaused {
        _pause();
    }

    function unpauseSmartContract() public onlyOwner whenPaused {
        _unpause();
    }

    function setAcceptedPayTokenAddress(address tokenAddress) public onlyOwner whenNotPaused {
        acceptedPayTokenAddress = tokenAddress;
    }

    function setProtocolFeesPercent(uint256 feePercent) public onlyOwner whenNotPaused {
        protocolFeesPercent = feePercent;
    }

    function addToLending(address tokenAddress, uint256 tokenId, uint256 durationHours, uint256 initialWorth) public whenNotPaused {
        require(initialWorth > 0, 'Add: Initial token must be woth more than 0');
        require(durationHours > 24, 'Add: Lending duration must be 1 day or above');
        require(lentNswapList[tokenAddress][tokenId].borrower == address(0), 'Add: Token already lent');
        require(lentNswapList[tokenAddress][tokenId].lenderClaimedCollateral == false, 'Add: Time already expired and collateral was liquidated to lender');

        IERC721(tokenAddress).transferFrom(msg.sender, address(this), tokenId);

        lentNswapList[tokenAddress][tokenId] = NswapForLend(durationHours, initialWorth, 0, 0, msg.sender, address(0), false, protocolFeesPercent);

        lendersWithTokens.push(NswapTokenEntry(msg.sender, tokenAddress, tokenId));

        emit NswapForLendUpdated(tokenAddress, tokenId);
    }

    function removeFromLending(address tokenAddress, uint256 tokenId) public whenNotPaused {
        require(lentNswapList[tokenAddress][tokenId].lender == msg.sender, 'Remove: Only the lender can perform this action');
        require(lentNswapList[tokenAddress][tokenId].borrower == address(0), 'Remove: There is someone borrowing it, once they return it you can cancel lending');
        require(lentNswapList[tokenAddress][tokenId].lenderClaimedCollateral == false, 'Remove: Collateral was already claimed');

        // check if needs approval as some tokens fail due this
        (bool success,) = tokenAddress.call(abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            tokenId
        ));
        if (success) {
            IERC721(tokenAddress).approve(address(this), tokenId);
        }

        IERC721(tokenAddress).transferFrom(address(this), msg.sender, tokenId);

        // reset lenders to sent token mapping, swap with last element to fill the gap
        lentNswapList[tokenAddress][tokenId] = NswapForLend(0, 0, 0, 0, address(0), address(0), false, 0);
        removeFromLendersWithTokens(tokenAddress, tokenId);

        emit NswapForLendRemoved(tokenAddress, tokenId);
    }

    function claimBorrowerCollateral(address tokenAddress, uint256 tokenId) public whenNotPaused {
        require(lentNswapList[tokenAddress][tokenId].borrower != address(0), 'Claim: Cannot claim when borrowing has ended');
        require(lentNswapList[tokenAddress][tokenId].lender == msg.sender, 'Claim: Cannot claim if you are not the lender');
        require(isDurationExpired(tokenAddress, tokenId), 'Claim: Cannot claim before lending expires');
        require(lentNswapList[tokenAddress][tokenId].lenderClaimedCollateral == false, 'Claim: Already claimed collateral');

        ////////////////////////////
        //**  */
        //send collateral with interest to the lender minus platform fees
        //** to code */
        ////////////////////////////

        // reset lenders to sent token mapping, swap with last element to fill gap
        lentNswapList[tokenAddress][tokenId].lenderClaimedCollateral = true;
        removeFromLendersWithTokens(tokenAddress, tokenId);

        emit NswapForLendUpdated(tokenAddress, tokenId);
    }

    function startBorrowing(address tokenAddress, uint256 tokenId) public whenNotPaused {
        require(lentNswapList[tokenAddress][tokenId].borrower == address(0), 'Borrowing: Already lent');
        require(lentNswapList[tokenAddress][tokenId].initialWorth > 0, 'Borrowing: Collateral requirement has not been set by lender');

        uint256 _requiredSum = calculateLendSum(tokenAddress, tokenId);
        uint256 _allowedCollateral = IERC20(acceptedPayTokenAddress).allowance(msg.sender, address(this));

        require(_allowedCollateral >= _requiredSum, 'Borrowing: Not enough collateral received');

        IERC20(acceptedPayTokenAddress).transferFrom(msg.sender, address(this), _requiredSum);

        // check if needs approval as some tokens fail due this
        (bool success,) = tokenAddress.call(abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            tokenId
        ));
        if (success) {
            IERC721(tokenAddress).approve(address(this), tokenId);
        }

        IERC721(tokenAddress).transferFrom(address(this), msg.sender, tokenId);

        lentNswapList[tokenAddress][tokenId].borrower = msg.sender;
        lentNswapList[tokenAddress][tokenId].borrowedAtTimestamp = block.timestamp;

        ////////////////////////////
        // DEFI Protocol API - Send Collateral to work
        lentNswapList[tokenAddress][tokenId].defiTokens = 0;
        //  ** To CODE **
        ////////////////////////////

        emit NswapForLendUpdated(tokenAddress, tokenId);
    }

    function stopBorrowing(address tokenAddress, uint256 tokenId) public whenNotPaused {
        address _lender = lentNswapList[tokenAddress][tokenId].lender;

        address _borrower = lentNswapList[tokenAddress][tokenId].borrower;
        require(_borrower == msg.sender, 'Stop: Only the active borrower can stop borrowing');

        if (lentNswapList[tokenAddress][tokenId].lenderClaimedCollateral == false) {
            // Assuming NFT token transfer is approved
            IERC721(tokenAddress).transferFrom(msg.sender, address(this), tokenId);

            ////////////////////////////
            // Get the collateral from DEFI Protocol
            uint256 _initialWorth = lentNswapList[tokenAddress][tokenId].initialWorth;
            //uint256 _defiTokens = lentNswapList[tokenAddress][tokenId].defiTokens;
            uint256 _interestEarned = 0; //placeholder value for now
            ///
            //  ** To CODE **
            /////////////////////////////////////

            // Send back the collateral to the Borrower
            IERC20(acceptedPayTokenAddress).transfer(_borrower, _initialWorth);

            // Send the interest to the lender if there is interest to send
            if (_interestEarned > 0) {
                uint256 _platformFee = lentNswapList[tokenAddress][tokenId].protocolFeesPercent;
                uint256 _interestEarnedMinusFees = _interestEarned * (1-_platformFee);

                IERC20(acceptedPayTokenAddress).transfer(_lender, _interestEarnedMinusFees);
            }

            // Reset settings so the token can be borrowed again
            lentNswapList[tokenAddress][tokenId].borrower = address(0);
            lentNswapList[tokenAddress][tokenId].borrowedAtTimestamp = 0;
        }
        else {
            // Lender already claimed collateral, borrower can keep token it
            lentNswapList[tokenAddress][tokenId] = NswapForLend(0, 0, 0, 0, address(0), address(0), false, 0); //reset

            /////////////////////////////////////
            // Let the borrower know that he can keep the NFT
            //  ** To CODE **
            /////////////////////////////////////
        }

        emit NswapForLendUpdated(tokenAddress, tokenId);
    }

    function removeFromLendersWithTokens(address tokenAddress, uint256 tokenId) internal {
        /////////////////////////////////////
        // This for() function needs to be optimized to by gas efficient
        //  ** To CODE **
        /////////////////////////////////////     

        // Reset lenders to sent token mapping, swap with last element to fill the gap
        uint totalCount = lendersWithTokens.length;
        if (totalCount > 1) {
            for (uint i=0; i<totalCount; i++) {
                NswapTokenEntry memory tokenEntry = lendersWithTokens[i];
                if (tokenEntry.lenderAddress == msg.sender && tokenEntry.tokenAddress == tokenAddress && tokenEntry.tokenId == tokenId) {
                    lendersWithTokens[i] = lendersWithTokens[totalCount-1]; // insert last from array
                }
            }
            //lendersWithTokens.length--; 
        }
        else {
            delete lendersWithTokens[0];        
        }
    }

    function timeTillExpiration(address tokenAddress, uint256 tokenId) public view returns(uint hoursRemaining) {
        uint256 _borrowedAtTimestamp = lentNswapList[tokenAddress][tokenId].borrowedAtTimestamp;
        uint256 _durationHours = lentNswapList[tokenAddress][tokenId].durationHours;

        uint256 secondsPassed = block.timestamp - _borrowedAtTimestamp;
        uint256 hoursPassed = secondsPassed * 60 * 60;

        if (hoursPassed > _durationHours) {
            hoursRemaining = 0;
        }
        else {
            hoursRemaining = _durationHours - hoursPassed;
        }
    }

    function isDurationExpired(address tokenAddress, uint256 tokenId) public view returns(bool) {
        uint256 _borrowedAtTimestamp = lentNswapList[tokenAddress][tokenId].borrowedAtTimestamp;
        uint256 _durationHours = lentNswapList[tokenAddress][tokenId].durationHours;

        uint256 secondsPassed = block.timestamp - _borrowedAtTimestamp;
        uint256 hoursPassed = secondsPassed * 60 * 60;
        return hoursPassed > _durationHours;
    }

    function calculateLendSum(address tokenAddress, uint256 tokenId) public view returns(uint256) {
        uint256 _initialWorth = lentNswapList[tokenAddress][tokenId].initialWorth;
        return _initialWorth;
    }

    function isValidNFT(address tokenAddress, uint256 tokenId) public view returns(bool) {
        // No owner is most likely burnt NFT
        return IERC721(tokenAddress).ownerOf(tokenId) != address(0);
    }
}
