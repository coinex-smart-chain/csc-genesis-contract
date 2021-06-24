// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

import "./System.sol";
import "./Slash.sol";
import "./library/SafeMath.sol";

contract Validators is System {
    using SafeMath for uint256;

    uint16 public constant MaxValidatorNum = 101;
    // Validator have to wait StakingLockPeriod blocks to withdraw staking
    uint64 public constant StakingLockPeriod = 86400;
    // Validator have to wait WithdrawRewardPeriod blocks to withdraw his rewards
    uint64 public constant WithdrawRewardPeriod = 28800;
    uint256 public constant MinimalStakingCoin = 10000 ether;
    uint256 public constant ValidatorSlashAmount = 500 ether;
    uint256 public constant MinimalOfStaking = 1000 ether;

    enum Status {
        // validator not exist, default status
        NotExist,
        // validator created
        Created,
        // anyone has staked for the validator
        Staked,
        // validator's staked amount < MinimalStakingCoin
        Unstake,
        // validator is jailed by system(validator have to repropose)
        Jailed
    }

    struct Description {
        string moniker;
        string website;
        string email;
        string details;
    }

    struct Validator {
        address payable rewardAddr;
        Status status;
        uint256 stakingAmount;
        Description description;
        uint256 rewardAmount;
        uint256 slashAmount;
        uint256 lastWithdrawRewardBlock;
        // Address list of user who has staked for this validator
        address[] stakers;
    }

    struct StakingInfo {
        uint256 amount;
        // unstakeBlock != 0 means that you are unstaking your stake, so you can't stake or unstake
        uint256 unstakeBlock;
        // index of the staker list in validator
        uint256 index;
    }

    mapping(address => Validator) validatorInfo;
    // staker => validator => info
    mapping(address => mapping(address => StakingInfo)) stakerInfo;
    // validator candidate set (dynamic changed)
    address[] public validatorCandidateSet;
    // current activate validator set
    address[] public validatorSet;
    // total staking amount of all validators
    uint256 public totalStaking;

    // slash contract
    Slash slash;

    // Record the operations is done or not.
    uint256 distributedRewardNumber;
    uint256 updateValidatorNumber;

    event ValidatorCreated(address indexed validator, address indexed rewardAddr);
    event ValidatorUpdated(address indexed validator, address indexed rewardAddr);
    event ValidatorUnjailed(address indexed validator);
    event Unstake(address indexed staker, address indexed validator, uint256 amount, uint256 unLockHeight);
    event Staking(address indexed staker, address indexed validator, uint256 amount);
    event WithdrawStaking(address indexed staker, address indexed validator, uint256 amount);
    event WithdrawRewards(address indexed validator, address indexed rewardAddress, uint256 amount, uint256 nextWithdrawBlock);
    event RewardDistributed(address []validators, uint256 []rewards, uint256 rewardCount);
    //event RewardDistributed(address indexed validator, uint256 indexed reward);
    event ValidatorSlash(address indexed validator, uint256 amount);

    event ValidatorSetUpdated(address []validators);

    event AddToValidatorCandidate(address indexed validator);
    event RemoveFromValidatorCandidate(address indexed valdiator);

    modifier onlyNotRewarded() {
        require(
            block.number > distributedRewardNumber,
            "Block is already rewarded"
        );
        _;
        distributedRewardNumber = block.number;
    }

    modifier onlyNotUpdated() {
        require(
            block.number > updateValidatorNumber,
            "Validators already updated"
        );
        _;
        updateValidatorNumber = block.number;
    }

    function initialize(address[] calldata validators) external onlyNotInitialized {
        slash = Slash(SlashContractAddr);

        for (uint256 i = 0; i < validators.length; i++) {
            require(validators[i] != address(0), "Invalid validator address");

            if (!isValidatorCandidate(validators[i])) {
                validatorCandidateSet.push(validators[i]);
            }
            
            if (!isValidatorActivated(validators[i])) {
                validatorSet.push(validators[i]);
            }
            
            if (validatorInfo[validators[i]].rewardAddr == address(0)) {
                validatorInfo[validators[i]].rewardAddr = payable(validators[i]);
            }
            
            // Important: NotExist validator can't get rewards
            if (validatorInfo[validators[i]].status == Status.NotExist) {
                validatorInfo[validators[i]].status = Status.Staked;
            }
        }

        initialized = true;
    }

    function create(
        address payable rewardAddr,
        string calldata moniker,
        string calldata website,
        string calldata email,
        string calldata details
    ) external payable onlyInitialized returns (bool) {
        address payable validator = msg.sender;
        require(validatorInfo[validator].status == Status.NotExist, "validator already exist");
        uint256 stakingAmount = msg.value;
        _updateValidator(validator, rewardAddr, moniker, website, email, details);
        emit ValidatorCreated(validator, rewardAddr);
        if (stakingAmount <= 0) {
            return true;
        }

        return _stake(validator, validator, stakingAmount);
    }

    function edit(
        address payable rewardAddr,
        string calldata moniker,
        string calldata website,
        string calldata email,
        string calldata details
    ) external onlyInitialized returns (bool) {
        address payable validator = msg.sender;
        require(validatorInfo[validator].status != Status.NotExist, "validator isn't exist");
        _updateValidator(validator, rewardAddr, moniker, website, email, details);
        emit ValidatorUpdated(validator, rewardAddr);
        return true;
    }

    // stake for the validator
    function stake(address validator)
        external
        payable
        onlyInitialized
        returns (bool)
    {
        address payable staker = msg.sender;
        uint256 stakingAmount = msg.value;
        return _stake(staker, validator, stakingAmount);
    }

    function _stake(address staker, address validator, uint256 stakingAmount) private returns (bool) {
        require(
            validatorInfo[validator].status != Status.NotExist,
            "validator is not exist"
        );
        require(
            stakerInfo[staker][validator].unstakeBlock == 0,
            "can't stake when you are unstaking"
        );

        // staking amount must >= 1000cet
        require(
            stakingAmount >= MinimalOfStaking,
            "staking amount must more than 1000cet"
        );

        Validator storage valInfo = validatorInfo[validator];
        // The staked amount of validator must >= MinimalStakingCoin
        require(
            valInfo.stakingAmount.add(stakingAmount) >= MinimalStakingCoin,
            "staking amount must more than 10000cet"
        );

        // stake at first time to this valiadtor
        if (stakerInfo[staker][validator].amount == 0) {
            // add staker to validator's record list
            stakerInfo[staker][validator].index = valInfo.stakers.length;
            valInfo.stakers.push(staker);
        }

        valInfo.stakingAmount = valInfo.stakingAmount.add(stakingAmount);
        if (valInfo.status != Status.Staked && valInfo.status != Status.Jailed) {
            valInfo.status = Status.Staked;
        }

        // record staker's info
        stakerInfo[staker][validator].amount = stakerInfo[staker][validator].amount.add(stakingAmount);
        totalStaking = totalStaking.add(stakingAmount);
        emit Staking(staker, validator, stakingAmount);

        if (valInfo.status == Status.Staked) {
            addToValidatorCandidate(validator, valInfo.stakingAmount);
        }

        return true;
    }

    function unstake(address validator)
        external
        onlyInitialized
        returns (bool)
    {
        address staker = msg.sender;
        require(validatorInfo[validator].status != Status.NotExist, "validator is not exist");

        StakingInfo storage stakingInfo = stakerInfo[staker][validator];
        Validator storage valInfo = validatorInfo[validator];
        uint256 unstakeAmount = stakingInfo.amount;

        require(stakingInfo.unstakeBlock == 0, "you are already in unstaking status");
        require(unstakeAmount > 0, "you don't have any stake");
        // You can't unstake if the validator is the only one top validator and
        // this unstake operation will cause staked amount of validator < MinimalStakingCoin
        require(
            !(validatorSet.length == 1 &&
                isValidatorActivated(validator) &&
                valInfo.stakingAmount.sub(unstakeAmount) < MinimalStakingCoin),
            "you can't unstake, validator list will be empty after this operation"
        );

        // try to remove this staker out of validator stakers list.
        if (stakingInfo.index != valInfo.stakers.length - 1) {
            valInfo.stakers[stakingInfo.index] = valInfo.stakers[valInfo
                .stakers
                .length - 1];
            // update index of the changed staker.
            stakerInfo[valInfo.stakers[stakingInfo.index]][validator]
                .index = stakingInfo.index;
        }
        valInfo.stakers.pop();

        valInfo.stakingAmount = valInfo.stakingAmount.sub(unstakeAmount);
        stakingInfo.unstakeBlock = block.number;
        stakingInfo.index = 0;
        totalStaking = totalStaking.sub(unstakeAmount);

        // try to remove it out of active validator set if validator's stakingAmount < MinimalStakingCoin
        if (valInfo.stakingAmount < MinimalStakingCoin) {
            valInfo.status = Status.Unstake;
        }
        uint256 unLockHeight = block.number + StakingLockPeriod + 1;
        emit Unstake(staker, validator, unstakeAmount, unLockHeight);

        if (valInfo.status != Status.Staked) {
            removeFromValidatorCandidate(validator);
        }
        return true;
    }

    function _updateValidator(address payable validator, address payable rewardAddr,
        string calldata moniker,
        string calldata website,
        string calldata email,
        string calldata details
    ) private returns (bool) {
        require(rewardAddr != address(0), "invalid receive reward address");
        require(validateDescription(moniker, website, email,details), "invalid validator description");
        if (validatorInfo[validator].status == Status.NotExist) {
            validatorInfo[validator].status = Status.Created;
        }

        if (validatorInfo[validator].rewardAddr != rewardAddr) {
            validatorInfo[validator].rewardAddr = rewardAddr;
        }

        validatorInfo[validator].description = Description(
            moniker,
            website,
            email,
            details
        );

        return true;

    }

    function unjailed()
        external
        onlyInitialized
        returns (bool)
    {
        address validator = msg.sender;
        require(validatorInfo[validator].status == Status.Jailed, "validator isn't jailed");
        require(slash.clean(validator), "clean slash reward failed");

        if (validatorInfo[validator].stakingAmount >= MinimalStakingCoin) {
            validatorInfo[validator].status = Status.Staked;
            addToValidatorCandidate(validator, validatorInfo[validator].stakingAmount);
        } else {
            validatorInfo[validator].status = Status.Unstake;
        }

        emit ValidatorUnjailed(validator);
        return true;
    }

    function withdrawStaking(address validator) external returns (bool) {
        address payable staker = payable(msg.sender);
        StakingInfo storage stakingInfo = stakerInfo[staker][validator];
        require(
            validatorInfo[validator].status != Status.NotExist,
            "validator not exist"
        );
        require(stakingInfo.unstakeBlock != 0, "you have to unstake first");
        // Ensure staker can withdraw his staking back
        require(
            stakingInfo.unstakeBlock + StakingLockPeriod <= block.number,
            "your staking haven't unlocked yet"
        );
        require(stakingInfo.amount > 0, "you don't have any stake");

        uint256 staking = stakingInfo.amount;
        stakingInfo.amount = 0;
        stakingInfo.unstakeBlock = 0;

        // send stake back to staker
        staker.transfer(staking);

        emit WithdrawStaking(staker, validator, staking);
        return true;
    }

    // rewardAddress can withdraw reward of it's validator
    function withdrawRewards(address validator) external returns (bool) {
        address payable rewardAddr = payable(msg.sender);
        require(
            validatorInfo[validator].status != Status.NotExist,
            "validator not exist"
        );
        require(
            validatorInfo[validator].rewardAddr == rewardAddr,
            "you are not the reward receiver of this validator"
        );
        require(
            validatorInfo[validator].lastWithdrawRewardBlock +
                WithdrawRewardPeriod <=
                block.number,
            "you must wait enough blocks to withdraw your reward after latest withdraw of this validator"
        );
        uint256 rewardAmount = validatorInfo[validator].rewardAmount;
        require(rewardAmount > 0, "you don't have any reward");

        // update info
        validatorInfo[validator].rewardAmount = 0;
        validatorInfo[validator].lastWithdrawRewardBlock = block.number;

        // send reward to reward address
        if (rewardAmount > 0) {
            rewardAddr.transfer(rewardAmount);
        }
        uint256 nextWithdrawBlock = block.number + WithdrawRewardPeriod + 1;
        emit WithdrawRewards(validator, rewardAddr, rewardAmount, nextWithdrawBlock);

        return true;
    }

    // distributeBlockReward distributes block reward to all active validators
    function distributeBlockReward()
        external
        payable
        onlyCoinbase
        onlyNotRewarded
        onlyInitialized
    {
        address validator = msg.sender;
        uint256 amount = msg.value;

        if (validatorInfo[validator].status == Status.NotExist) {
            return;
        }

        _distributeRewardToActivatedValidators(amount, address(0));

    }

    function slashValidator(address validator) external onlySlashContract {
        if (!isValidatorActivated(validator)) {
            return;
        }

        Validator storage valInfo = validatorInfo[validator];
        valInfo.status = Status.Jailed;
        uint256 stakingAmount = valInfo.stakingAmount;
        deactivateValidator(validator);
        removeFromValidatorCandidate(validator);

        uint256 slashTotal = 0;
        for (uint256 i = 0; i < valInfo.stakers.length; i++) {
            StakingInfo storage stakingInfo = stakerInfo[valInfo.stakers[i]][validator];
            uint256 stakerSlashAmount = stakingInfo.amount.mul(ValidatorSlashAmount).div(stakingAmount);
            stakingInfo.amount = stakingInfo.amount.sub(stakerSlashAmount);
            slashTotal = slashTotal.add(stakerSlashAmount);
        }
        valInfo.stakingAmount = valInfo.stakingAmount.sub(slashTotal);
        valInfo.slashAmount = valInfo.slashAmount.add(slashTotal);

        _distributeRewardToActivatedValidators(slashTotal, validator);
        emit ValidatorSlash(validator, slashTotal);
    }

    function _distributeRewardToActivatedValidators(uint256 rewardAmount, address exceptAddress) private {
        if (rewardAmount == 0) {
            return;
        }

        uint256 totalRewardStaking = 0;
        uint256 rewardValidatorLen = 0;
        for (uint256 i = 0; i < validatorSet.length; i++) {
            if (validatorInfo[validatorSet[i]].status != Status.Jailed && validatorSet[i] != exceptAddress) {
                totalRewardStaking = totalRewardStaking.add(validatorInfo[validatorSet[i]].stakingAmount);
                rewardValidatorLen++;
            }
        }
        if (rewardValidatorLen == 0) {
            return;
        }

        uint256 remain;
        address last;
        uint256 distributedAmount;
        address[] memory rewardValidators = new address[](validatorSet.length);
        uint256[] memory validatorRewardAmount = new uint256[](validatorSet.length);
        uint256 rewardCount = 0;
        uint256 reward = 0;
        for (uint256 i = 0; i < validatorSet.length; i++) {
            if (validatorInfo[validatorSet[i]].status != Status.Jailed && validatorSet[i] != exceptAddress) {
                if (totalRewardStaking == 0) {
                    reward = rewardAmount.div(rewardValidatorLen);
                } else {
                    reward = rewardAmount.mul(validatorInfo[validatorSet[i]].stakingAmount).div(totalRewardStaking);
                }
                validatorInfo[validatorSet[i]].rewardAmount = validatorInfo[validatorSet[i]].rewardAmount.add(reward);
                last = validatorSet[i];
                distributedAmount = distributedAmount.add(reward);
                rewardValidators[rewardCount] = validatorSet[i];
                validatorRewardAmount[rewardCount] = reward;
                rewardCount++;
            }
        }

        remain = rewardAmount.sub(distributedAmount);
        if (remain > 0 && last != address(0)) {
            validatorInfo[last].rewardAmount = validatorInfo[last].rewardAmount.add(remain);
            validatorRewardAmount[validatorRewardAmount.length-1] = validatorRewardAmount[validatorRewardAmount.length-1].add(remain);
        }

        emit RewardDistributed(rewardValidators, validatorRewardAmount, rewardCount);
    }

    function deactivateValidator(address validator) private {
        for (uint256 i = 0; i < validatorSet.length && validatorSet.length > 1; i++) {
            if (validator == validatorSet[i]) {
                if (i != validatorSet.length-1) {
                    validatorSet[i] = validatorSet[validatorSet.length-1];
                }
                validatorSet.pop();
                break;
            }
        }
    }

    function getValidatorDescription(address validator) public view returns (string memory, string memory, string memory, string memory){
        Validator memory v = validatorInfo[validator];

        return (
            v.description.moniker,
            v.description.website,
            v.description.email,
            v.description.details
        );
    }

    function getValidatorInfo(address validator) public view returns (address payable, Status, uint256, uint256, uint256, uint256, address[] memory) {
        Validator memory v = validatorInfo[validator];

        return (
            v.rewardAddr,
            v.status,
            v.stakingAmount,
            v.rewardAmount,
            v.slashAmount,
            v.lastWithdrawRewardBlock,
            v.stakers
        );
    }

    function getStakingInfo(address staker, address validator) public view returns (uint256, uint256, uint256) {
        return (
            stakerInfo[staker][validator].amount,
            stakerInfo[staker][validator].unstakeBlock,
            stakerInfo[staker][validator].index
        );
    }

    function getValidatorCandidate() public view returns (address[] memory, uint256[] memory, uint256) {
        address[] memory candidates = new address[](validatorCandidateSet.length);
        uint256[] memory stakings = new uint256[](validatorCandidateSet.length);
        uint256 count = 0;
        for (uint256 i = 0; i < validatorCandidateSet.length; i++) {
            if (validatorInfo[validatorCandidateSet[i]].status == Status.Staked) {
                candidates[count] = validatorCandidateSet[i];
                stakings[count] = validatorInfo[validatorCandidateSet[i]].stakingAmount;
                count++;
            }
        }
        return (candidates, stakings, count);
    }

    function updateActivatedValidators() public 
        onlyCoinbase
        onlyNotUpdated
        onlyInitialized
        onlyBlockEpoch() returns (address[] memory)
    {
        require(validatorCandidateSet.length > 0, "validator set empty");
        require(validatorCandidateSet.length <= MaxValidatorNum, "validator can't more than 101");
        validatorSet = validatorCandidateSet;
        emit ValidatorSetUpdated(validatorSet);
        return validatorSet;
    }

    function isValidatorCandidate(address who) public view returns (bool) {
        for (uint256 i = 0; i < validatorCandidateSet.length; i++) {
            if (validatorCandidateSet[i] == who) {
                return true;
            }
        }

        return false;
    }

    function isValidatorActivated(address validator) public view returns (bool) {
        for (uint256 i = 0; i < validatorSet.length; i++) {
            if (validatorSet[i] == validator) {
                return true;
            }
        }

        return false;
    }

    function isJailed(address validator) public view returns (bool) {
        if (validatorInfo[validator].status == Status.Jailed) {
            return true;
        }
        return false;
    }

    function getActivatedValidators() public view returns (address[] memory) {
        return validatorSet;
    }

    function validateDescription(
        string memory moniker,
        string memory website,
        string memory email,
        string memory details
    ) public pure returns (bool) {
        require(bytes(moniker).length <= 128, "invalid moniker length");
        require(bytes(website).length <= 256, "invalid website length");
        require(bytes(email).length <= 256, "invalid email length");
        require(bytes(details).length <= 1024, "invalid details length");

        return true;
    }

    function addToValidatorCandidate(address validator, uint256 staking) internal returns (bool){
        for (uint256 i = 0; i < validatorCandidateSet.length; i++) {
            if (validatorCandidateSet[i] == validator) {
                return true;
            }
        }

        if (validatorCandidateSet.length < MaxValidatorNum) {
            validatorCandidateSet.push(validator);
            emit AddToValidatorCandidate(validator);
            return true;
        }

        uint256 lowestStaking = validatorInfo[validatorCandidateSet[0]].stakingAmount;
        uint256 lowestIndex = 0;
        for (uint256 i = 1; i < validatorCandidateSet.length; i++) {
            if (validatorInfo[validatorCandidateSet[i]].stakingAmount < lowestStaking) {
                lowestStaking = validatorInfo[validatorCandidateSet[i]].stakingAmount;
                lowestIndex = i;
            }
        }

        if (staking <= lowestStaking) {
            return false;
        }

        emit RemoveFromValidatorCandidate(validatorCandidateSet[lowestIndex]);
        emit AddToValidatorCandidate(validator);
        validatorCandidateSet[lowestIndex] = validator;
        return true;
    }

    function removeFromValidatorCandidate(address validator) internal {
        for (uint256 i = 0; i < validatorCandidateSet.length && validatorCandidateSet.length > 1; i++) {
            if (validatorCandidateSet[i] == validator) {
                if (i != validatorCandidateSet.length - 1) {
                    validatorCandidateSet[i] = validatorCandidateSet[validatorCandidateSet.length - 1];
                }
                validatorCandidateSet.pop();
                emit RemoveFromValidatorCandidate(validator);
                break;
            }
        }
    }
}
