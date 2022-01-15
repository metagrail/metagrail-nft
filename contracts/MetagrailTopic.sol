//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0 <0.9.0;



import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";
contract MetagrailTopic is AccessControl {

    using EnumerableSet for EnumerableSet.UintSet;

    address private REWARD_TOKEN;

    struct Topics {
        uint topicId;
        uint256 start;
        uint256 deadline;
        uint256 rewards;
        uint256 joined;
    }

    bytes32 public constant EDITOR_ROLE = keccak256("EDITOR_ROLE");


    /// @dev 2022-04-11 00:00:00
    uint private withdrawOpenTime = 1649606400; 

    EnumerableSet.UintSet allTopics;

    /// topic storages
    mapping(uint=>Topics) topicStorage;

    /// @dev
    mapping(address=>EnumerableSet.UintSet) joinedTopics;

    /// @dev when claimed the topic
    mapping(address=>mapping(uint=>uint)) topicRewardsClaimedTime;

    mapping(address=>mapping(uint=>uint)) joinedTopicTime;

    /// @dev store the token amount which can be withdraw to wallet
    mapping(address=>uint256) withdrawable;

    /// @notice when user withdraw the token, there'll be an event recorded 
    event WithdrawNotification(address withdrawWallet, uint256 amount, uint256 withdrawTime);

    /// @notice when user claim reward of topic
    event ClaimRewardNotification(address withdrawWallet, uint topicId, uint256 amount, uint256 claimTime);

    /// @notice when user join topic
    event JoinTopicNotification(address user, uint topicId, uint256 joinTime);

    function getEditorRole() public pure returns (bytes32) {
        return EDITOR_ROLE;
    }

    function updateRewardToken(address rewardTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE){
        REWARD_TOKEN = rewardTokenAddress;
    }

    constructor() {
        // Grant the contract deployer the default admin role: it will be able
        // to grant and revoke any roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    } 

    /// @dev the editor operation
    /// @param _topicId topic
    /// @param _start  the time user can start to join (timestamp) 
    /// @param _deadline deadline (timestamp) 
    /// @param _rewards  how many token will be divided to users joined that topic
    /// @notice 
    function bindTopic(uint _topicId, uint256 _start, uint256 _deadline, uint256 _rewards) external onlyRole(EDITOR_ROLE) {
        
        Topics storage t = topicStorage[_topicId];
        if (t.topicId == 0) {
            allTopics.add(_topicId);
            t.joined = 0;
        } 
        // override original data
        t.topicId = _topicId;
        t.start = _start;
        t.deadline = _deadline;
        // t.rewards = _rewards * 10 ** 18;
        t.rewards = _rewards;

    }


    /// @dev join the topic
    /// @param topicId the topic joined
    ///
    function joinTopic(uint topicId) external {
        
        address user = msg.sender;
        // require the topic can be join now
        Topics storage t = topicStorage[topicId];
        require(t.topicId > 0, "topic not exist");
        require(block.timestamp >= t.start && block.timestamp <= t.deadline, "topic can't be join now");
        EnumerableSet.UintSet storage myTopics = joinedTopics[user];
        require(!myTopics.contains(topicId), "already joined before");
        myTopics.add(topicId);
        joinedTopicTime[user][topicId] = block.timestamp;
        t.joined++;

        emit JoinTopicNotification(user, topicId, block.timestamp);
    }

    /// @dev check if the address joined topic before
    /// @param user wallet address
    /// @param topicId the topics
    function isJoinedTopic(address user, uint topicId) external view returns(bool isJoined) {

        // require the topic can be join now
        Topics storage t = topicStorage[topicId];
        require(t.topicId > 0, "topic not exist");

        EnumerableSet.UintSet storage myTopics = joinedTopics[user];
        isJoined = myTopics.contains(topicId); 
    
    }

    /// @dev
    
    function joinedAmount(uint topicId) external view returns(uint amount) {
        Topics storage t = topicStorage[topicId];
        require(t.topicId > 0, "topic not exist");
        amount = t.joined;
    }


    /// @dev claim rewards in the topic which joined before
    /// @param topicId the topic joined before
    ///
    function claimRewards(uint topicId) external {

        address claimUser = msg.sender;
        Topics storage t = topicStorage[topicId];
        require(t.topicId > 0, "topic not exist");
        require(block.timestamp > t.deadline, "topic can't withdraw now");
        
        EnumerableSet.UintSet storage joined = joinedTopics[claimUser];
        require(joined.contains(topicId), "didn't join before");
        require(topicRewardsClaimedTime[claimUser][topicId] == 0, "claimed already");

        topicRewardsClaimedTime[claimUser][topicId] = block.timestamp;
        uint256 claimableAmount = t.rewards / t.joined;
        withdrawable[claimUser] += claimableAmount;

        emit ClaimRewardNotification(claimUser, topicId, claimableAmount, block.timestamp);
    }


    /// @dev check whether the rewards of the topic  is claimed
    function isRewardClaim(uint topicId) external view returns(bool isClaimed) {

        address claimUser = msg.sender;
        Topics storage t = topicStorage[topicId];
        require(t.topicId > 0, "topic not exist");
                
        EnumerableSet.UintSet storage joined = joinedTopics[claimUser];
        require(joined.contains(topicId), "didn't join before");        

        isClaimed = (topicRewardsClaimedTime[claimUser][topicId] > 0);
            
    }


    /// @dev query my balance
    /// @return balance all the balance 
    ///
    function queryMyBalance() external view returns(uint256 balance) {
        balance = withdrawable[msg.sender];
    }


    function queryBalance(address wallet) external view returns(uint256 balance) {
        balance = withdrawable[wallet];
    }


    function queryTopicDetail(uint topicId) external view returns (Topics memory tp) {
        return topicStorage[topicId];
    }

    function queryTopicWithdrawStatus(address wallet, uint topicId) external view returns(bool isClaimed) {

        address claimUser = wallet;
        Topics storage t = topicStorage[topicId];
        require(t.topicId > 0, "topic not exist");
                
        EnumerableSet.UintSet storage joined = joinedTopics[claimUser];
        require(joined.contains(topicId), "didn't join before");        

        isClaimed = (topicRewardsClaimedTime[claimUser][topicId] > 0);
    }


    /// @dev withdraw my balance when the time reach
    ///
    ///
    function withdrawRewards() external {

        address targetAddress = msg.sender;

        uint256 amount = withdrawable[targetAddress];
        
        if (amount > 0 && block.timestamp > withdrawOpenTime ) {
            
            IERC20(REWARD_TOKEN).transfer(targetAddress, amount);
            withdrawable[targetAddress] = 0;
            emit WithdrawNotification(targetAddress, amount, block.timestamp);

        }

    }


    /// @dev query the time when can withdraw the token to the wallet
    function queryWithdrawOpenTime() external view returns (uint) {
        return withdrawOpenTime;
    }


    /// @dev check the topic is binded
    function isTopicBinded(uint topicId) external view returns (bool binded) {
        binded = allTopics.contains(topicId);
    } 


}

