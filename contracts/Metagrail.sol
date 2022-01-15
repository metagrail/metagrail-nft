//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0 <0.9.0;


import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


contract Metagrail is ERC721, Ownable  {

    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;

    uint private TOTAL_SUPPLY = 10000;
    uint private LAST_IMPORT_TOKEN = 0;

    uint256 private PRICE = 50 * 10 ** 18;
    /// for rand
    uint256 private randNonce = 0;

    Counters.Counter private _totalSold;

    /// BSC
    address private PAYMENT_TOKEN = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; 
    /// ETH
    // address private PAYMENT_TOKEN = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; 

    mapping(address=>EnumerableSet.UintSet) private ownedCups;

    /// stored cup which can be sell
    EnumerableSet.UintSet private cupStorage;

    /// @dev is start to selling
    bool private START_SELLING = false;

    mapping(uint=>uint256) private tokenReceiveTime;

    struct CupCategory {
        uint startId;
        uint endId;
        uint category;
    }

    /// @dev 
    string private baseTokenURI="http://img.metagrail.io/"; 

    ///
    CupCategory[] private cupCategorys;

    /// 
    event PurchaseNotification(address purchaseWallet, uint256 amount, uint256 purchaseTime);


    function updatePaymentToken(address paymentToken) public onlyOwner {
        PAYMENT_TOKEN = paymentToken;
    } 

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseTokenURI = _baseURI;
    }

    function setStartSelling(bool start) public onlyOwner {
        START_SELLING = start;
    }

    /// @dev
    // uint256 currentCheerGrail;
    constructor() ERC721("Metagrail", "MTG") {
        /// when contract created, first batch of grails have been created
        // initialCups(1, 7, 32);
        // initialCups(64, 74, 16);
        // initialCups(163, 217, 8);
        // initialCups(658, 768, 4);
        // initialCups(1657, 1989, 2);
        // initialCups(4654, 5247, 1); 
    }


    /// @dev 
    /// @param cupsCategory = 32/16/8/4/2/1
    /// 
    function initialCups(uint startCupTokenId, uint endCupTokenId, uint cupsCategory) public onlyOwner {

        uint addedAmount = endCupTokenId - startCupTokenId + 1;
        require(addedAmount > 1, "cup size != cup category");
        require(addedAmount <= 1000, "add too many cups once");
        require(cupStorage.length() + totalSold() + addedAmount <= TOTAL_SUPPLY, "exceed total supply");

        // uint lastToken = LAST_IMPORT_TOKEN;

        for(uint i=startCupTokenId; i<=endCupTokenId; i++) {
            uint cupTokenId = i;
            // require(cupTokenId>lastToken, "the token has already been added"); 
            if (!cupStorage.contains(cupTokenId)) {
                require(validCupCategory(cupsCategory), "category is not valid");
                cupStorage.add(cupTokenId);
            }
        }
        
        CupCategory memory cupCategory = CupCategory({startId:startCupTokenId, endId: endCupTokenId, category:cupsCategory});
        cupCategorys.push(cupCategory);
        // LAST_IMPORT_TOKEN = lastToken;
    }

    
    ///    @dev 
    ///    @param tokenId the cup Id
    ///    @return category the cup category
    function queryCupCategory(uint tokenId) public view returns(uint category) {

        for (uint i=0; i<cupCategorys.length; i++) {
            CupCategory memory cc = cupCategorys[i];
            if (tokenId >= cc.startId && tokenId <=cc.endId) {
                category = cc.category;
                return category;
            }
        }
    }



    function queryStorage() external view returns (uint amount) {
        amount = cupStorage.length();
    }


    function validCupCategory(uint category) private pure returns (bool valid) {                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          
        valid = (category == 32 || category == 16 || category == 8 || category == 4 || category == 2 || category == 1);
    }
    
    ///
    ///
    ///
    function resetCupBlindBoxPrice(uint256 cupPrice) public onlyOwner {
        PRICE = cupPrice;
    }


    function basicCheck(uint amount) private view {

        require(START_SELLING == true, "Not start selling yet(1)");
        require(amount >= 1, "at least purchase 1");
        require(amount <= 10, "at most purchase 10 once");
        isEnoughSupply(amount, true);

    }

    /// @dev for user to purchase cup
    /// @param amount how many cups try to purchase
    ///
    function purchaseCup(uint amount) external {

        basicCheck(amount);
        
        address purchaseUser = msg.sender;
        uint256 totalFee = calculateFee(amount);
        // valid account
        require(IERC20(PAYMENT_TOKEN).balanceOf(purchaseUser) >= totalFee, "balance is not enough..");
        // valid storage
        IERC20(PAYMENT_TOKEN).transferFrom(purchaseUser, address(this), totalFee);
        /// mint
        mintToAddress(purchaseUser, amount);

    } 

    function mintToAddress(address purchaseUser, uint amount) private {

        EnumerableSet.UintSet storage myCupsSet = ownedCups[purchaseUser];

        for (uint i=0; i<amount; i++) {
            uint tokenId = randomToken(i);
            _mintOne(purchaseUser, tokenId);
            myCupsSet.add(tokenId);
            tokenReceiveTime[tokenId] = block.timestamp;
        }

        emit PurchaseNotification(purchaseUser, amount, block.timestamp);
    }


    function randomToken(uint seed) private returns (uint tokenId) {
        uint tokenIndex = random(seed, 1, cupStorage.length()) - 1;
        require(tokenIndex >= 0 && tokenIndex < cupStorage.length(), "Out of index");
        tokenId = cupStorage.at(tokenIndex);
        cupStorage.remove(tokenId);
    }


    function random(uint randomSeed, uint256 lrange, uint256 mrange) internal returns (uint) {

        randNonce++; 
        uint randomnumber = uint(keccak256(abi.encodePacked(randNonce, randomSeed, msg.sender ,block.timestamp, block.difficulty))) % (mrange - lrange + 1);
        randomnumber = randomnumber + lrange;
        return randomnumber;
    }


    function calculateFee(uint amount) private view returns (uint256 totalFee) {
        totalFee = amount * PRICE;
    }


    /**
        @dev overrided method of ERC721
        @param tokenId show metadata url of this token
        @return uri
     */
    function tokenURI(uint tokenId) public view override(ERC721) returns (string memory uri) {
        require(_exists(tokenId), "token not exist!");
        uri = string(abi.encodePacked(baseTokenURI, Strings.toString(tokenId), ".json"));
    }


    /**
        @dev mint one token one time
     */
    function _mintOne(address _to, uint _tokenId) private {
        _totalSold.increment();
        _safeMint(_to, _tokenId);
    }


    /**
        @dev list wallet's grails
        @return grails the wallet owned grails
    */
    function listMyGrails() public view returns (uint256[] memory grails) {
        return listOwnerGrails(msg.sender);
    }


    function listOwnerGrails(address ownerAddr) public view returns (uint256[] memory grails) {

        EnumerableSet.UintSet storage set = ownedCups[ownerAddr];
        uint length = set.length();
        grails = new uint256[](length);
        for (uint i=0;i<length;
         i++) {
            grails[i] = set.at(i);
        }
        
    }


    function isTokenOwner(uint256 tokenId, address owner) external view returns(bool isOwner) { 
        
        address ownerAddr = ownerOf(tokenId);
        require(ownerAddr != address(0), "No owner");
        isOwner = (ownerAddr == owner);

    } 


    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {

        EnumerableSet.UintSet storage original = ownedCups[from];
        original.remove(tokenId);

        super.transferFrom(from, to, tokenId);

        EnumerableSet.UintSet storage target = ownedCups[to];
        target.add(tokenId);

        tokenReceiveTime[tokenId] = block.timestamp;

    }

    function withdrawBalance(address targetAddress) public onlyOwner { 
        IERC20(PAYMENT_TOKEN).transfer(targetAddress, IERC20(PAYMENT_TOKEN).balanceOf(address(this)));
    }

    function getOwnedTokenAmount(address useraddress) external view returns(uint) {
        return ownedCups[useraddress].length();
    }


    function getTokenReceiveTime(uint256 tokenId) external view returns(uint256) {
        return tokenReceiveTime[tokenId];
    } 
    
    function batchMint(address wallet, uint amount) external onlyOwner {

        isEnoughSupply(amount, true);
        mintToAddress(wallet, amount);

    }

    function specificMint(uint tokenId, address wallet) public onlyOwner {
        EnumerableSet.UintSet storage myCupsSet = ownedCups[wallet];
        require(cupStorage.contains(tokenId), "already sold");
        cupStorage.remove(tokenId);
        _mintOne(wallet, tokenId);
        myCupsSet.add(tokenId);
        tokenReceiveTime[tokenId] = block.timestamp;
        emit PurchaseNotification(wallet, 1, block.timestamp);
    }


    function totalSold() public view returns (uint256) {
        return _totalSold.current();
    }


    function isEnoughSupply(uint amount, bool needReportError) private view returns (bool) {
        if (needReportError) {
            require(cupStorage.length() >= amount, "Max limit");
            return true;
        } else {
            if (cupStorage.length() >= amount) {
                return true;
            } else {
                return false;
            }

        }
    }    
}

