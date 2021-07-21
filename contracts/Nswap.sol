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
    uint256 public platformFeesPercent;

    struct NswapForLend {
        uint256 durationHours;
        uint256 initialWorth;
        uint256 defiTokens;
        uint256 borrowedAtTimestamp;
        address lender;
        address borrower;
        bool lenderClaimedCollateral;
        uint256 platformFeesPercent;
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

    function setAcceptedPayTokenAddress(address tokenAddress) public onlyOwner {
        acceptedPayTokenAddress = tokenAddress;
    }

    function setPlatformFeesPercent(uint256 feePercent) public onlyOwner {
        platformFeesPercent = feePercent;
    }

    function pauseSmartContract() public onlyOwner whenNotPaused {
        _pause();
    }

    function unpauseSmartContract() public onlyOwner whenPaused {
        _unpause();
    }

    function setLendSettings(address tokenAddress, uint256 tokenId, uint256 durationHours, uint256 initialWorth) public whenNotPaused {
        require(initialWorth > 0, 'Initial token must be woth more than 0');
        require(durationHours > 24, 'Lending duration must be 1 day or above');
        require(lentNswapList[tokenAddress][tokenId].borrower == address(0), 'Token already lent');
        require(lentNswapList[tokenAddress][tokenId].lenderClaimedCollateral == false, 'Time already expired and collateral was liquidated to lender');

        IERC721(tokenAddress).transferFrom(msg.sender, address(this), tokenId);

        lentNswapList[tokenAddress][tokenId] = NswapForLend(durationHours, initialWorth, 0, 0, msg.sender, address(0), false, platformFeesPercent);

        lendersWithTokens.push(NswapTokenEntry(msg.sender, tokenAddress, tokenId));

        emit NswapForLendUpdated(tokenAddress, tokenId);
    }

    function startBorrowing(address tokenAddress, uint256 tokenId) public whenNotPaused {
        require(lentNswapList[tokenAddress][tokenId].borrower == address(0), 'Already lent');
        require(lentNswapList[tokenAddress][tokenId].initialWorth > 0, 'Collateral requirement has not been set by lender');

        IERC_20 _payToken = IERC20(acceptedPayTokenAddress);
        uint256 _requireSum = calculateLendSum(tokenAddress, tokenId);
        uint256 _allowedCollateral = _payToken.allowance(msg.sender, address(this));

        require(_allowedCollateral >= _requiredSum, 'Not enough collateral received');

        IERC20(acceptedPayTokenAddress).transferfrom(msg.sender, address(this), _requiredSum);

        // check if needs approval as some tokens fail due this
        (bool success,) = tokenAddress.call(abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            tokenId
        ));

        if (success) {
            IERC721(tokenAddress).approve(address(this), tokenId);

            IERC721(tokenAddress).transferFrom(address(this), msg.sender, tokenId);

            lentNswapList[tokenAddress][tokenId].borrower = msg.sender;
            lentNswapList[tokenAddress][tokenId].borrowedAtTimestamp = now;

            // DEFI Protocol API - Send Collateral to work
            lentNswapList[tokenAddress][tokenId].defiTokens = 0;
            //  ** To CODE **
            ///////////////////////////////////////////////

            emit NswapForLendUpdated(tokenAddress, tokenId);
        }
    }

    function stopBorrowing(address tokenAddress, uint256 tokenId) public whenNotPaused {
        address _lender = lentNswapList[tokenAddress][tokenId].lender;

        address _borrower = lentNswapList[tokenAddress][tokenId].borrower;
        require(_borrower = msg.sender, 'Only the active borrower can stop borrowing');

        if (lentNswapList[tokenAddress][tokenId].lenderClaimedCollateral == false) {
            // Assuming NFT token transfer is approved
            IERC721(tokenAddress).transferFrom(msg.sender, address(this), tokenId);

            // Get the collateral from DEFI Protocol
            uint256 _initialWorth = lendNswapList[tokenAddress][tokenId].initialWorth;
            uint256 _defiTokens = lendNswapList[tokenAddress][tokenId].defiTokens;
            uint256 _interestEarned = 0; //placeholder value for now
            ///
            //  ** To CODE **
            /////////////////////////////////////

            // Send back the collateral to the Borrower
            IERC20(acceptedPayTokenAddress).transfer(_borrower, _initialWorth);

            // Send the interest to the lender if there is interest to send
            if (_interestEarned > 0) {
                uint256 _platformFee = lendNswapList[tokenAddress][tokenId].platformFeesPercent;
                uint256 _interestEarnedtMinusFees = _interestEarned * (1-_platformFee);

                IERC20(acceptedPayTokenAddress).transfer(_lender, _interestEarnedMinusFees);
            }

            // Reset settings so the token can be borrowed again
            lentNswapList[tokenAddress][tokenId].borrower = address(0);
            lentNswapList[tokenAddress][tokenId].borrowedAtTimestamp = 0;
        }
        else {
            // Lender already claimed collateral, borrower can keep token it
            lentNswapList[tokenAddress][tokenId] = ERC721ForLend(0, 0, 0, 0, address(0), address(0), false, 0);
        }

        emit NswapForLendUpdated(tokenAddress, tokenId);
    }

    function removeFromLendersWithTokens(address tokenAddress, uint256 tokenId) internal {
        // Reset lenders to sent token mapping, swap with last element to fill the gap
        uint totalCount = lendersWithTokens.length;
        if (totalCount > 1) {
            for (uint i=0; i<totalCount; i++) {
                NswapTokenEntry memory tokenEntry = lendersWithTokens[i];
                if (tokenEntry.lenderAddress == msg.sender && tokenEntry.tokenAddress == tokenAddress && tokenEntry.tokenId == tokenId) {
                    lenderWithTokens[i] = lendersWithTokens[totalCount-1]; // insert last from array
                }
            }
            lenderWithTokens.length--; 
        }
        else {
            delete lenderWithTokens[0];        
        }
    }

    function isDurationExpired(uint256 borrowedAtTimestamp, uint256 durationHours) public view returns(bool) {
        uint256 secondsPassed = now - borrowedAtTimestamp;
        uint256 hoursPassed = secondsPassed * 60 * 60;
        return hoursPassed > durationHours;
    }

    function calculateLendSum(address tokenAddress, uint256 tokenId) public view returns(bool) {
        uint256 _initialWorth = lentNswapList[tokenAddress][tokenId].initialWorth;
        return _initialWorth;
    }

    function isValidNFT(address tokenAddress, uint256 tokenId) public view returns(bool) {
        // No owner is most likely burnt NFT
        return IERC721(tokenAddress).ownerOf(tokenId) != address(0);
    }
}