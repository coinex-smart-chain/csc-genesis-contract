// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

import "./System.sol";
import "./Validators.sol";

contract Slash is System {
    uint256 public slashThreshold;
    uint256 public decreaseRate;

    struct SlashRecord {
        uint256 missedBlocksCounter;
        uint256 index;
        bool exist;
    }

    Validators validatorContract;

    mapping(address => SlashRecord) slashRecords;
    address[] public slashValidators;

    uint256 slashPrevNumber;
    uint256 decreasePrevNumber;

    event ValidatorSlash(address indexed validator);
    event ValidatorDecreasedMissedBlockCounter(address []validators, uint256 []missedBlockCounters, uint256);

    modifier onlyNotSlashed() {
        require(block.number > slashPrevNumber, "Already slashed");
        _;
        slashPrevNumber = block.number;
    }

    modifier onlyNotDecreased() {
        require(block.number > decreasePrevNumber, "Already decreased");
        _;
        decreasePrevNumber = block.number;
    }

    function initialize() external onlyNotInitialized {
        validatorContract = Validators(ValidatorContractAddr);
        slashThreshold = 48;
        decreaseRate = 24;
        initialized = true;
    }

    function slash(address validator)
        external
        onlyCoinbase
        onlyInitialized
        onlyNotSlashed
    {
        if (!validatorContract.isValidatorActivated(validator)) {
            return;
        }

        if (!slashRecords[validator].exist) {
            slashRecords[validator].index = slashValidators.length;
            slashValidators.push(validator);
            slashRecords[validator].exist = true;
        }
        slashRecords[validator].missedBlocksCounter++;

        if (slashRecords[validator].missedBlocksCounter % slashThreshold == 0) {
            validatorContract.slashValidator(validator);
            slashRecords[validator].missedBlocksCounter = 0;
        }
        emit ValidatorSlash(validator);
    }

    function decreaseMissedBlocksCounter(address[] calldata validators, uint256 epoch)
        external
        onlyCoinbase
        onlyNotDecreased
        onlyInitialized
        onlyBlockEpoch(epoch)
    {
        if (slashValidators.length == 0 || validators.length == 0) {
            return;
        }

        address[] memory decreasedValidators = new address[](validators.length);
        uint256[] memory missedBlockCounters = new uint256[](validators.length);
        uint256 decreasedCount = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            if (slashRecords[validators[i]].exist) {
                if (slashRecords[validators[i]].missedBlocksCounter > slashThreshold / decreaseRate) {
                    slashRecords[validators[i]].missedBlocksCounter =
                        slashRecords[validators[i]].missedBlocksCounter -
                        slashThreshold /
                        decreaseRate;
                } else {
                    slashRecords[validators[i]].missedBlocksCounter = 0;
                }
                decreasedValidators[decreasedCount] = validators[i];
                missedBlockCounters[decreasedCount] = slashRecords[validators[i]].missedBlocksCounter;
                decreasedCount++;
            }
        }
        if (decreasedCount > 0) {
            emit ValidatorDecreasedMissedBlockCounter(decreasedValidators, missedBlockCounters, decreasedCount);
        }
    }

    // clean validator's slash record if one unjailed
    function clean(address validator)
        public
        onlyInitialized
        onlyValidatorsContract
        returns (bool)
    {
        if (slashRecords[validator].exist && slashRecords[validator].missedBlocksCounter != 0) {
            slashRecords[validator].missedBlocksCounter = 0;
        }

        // remove it out of array if exist
        if (slashRecords[validator].exist && slashValidators.length > 0) {
            if (slashRecords[validator].index != slashValidators.length - 1) {
                address val = slashValidators[slashValidators.length - 1];
                slashValidators[slashRecords[val].index] = val;

                slashRecords[val].index = slashRecords[val].index;
            }
            slashValidators.pop();
            slashRecords[validator].index = 0;
            slashRecords[validator].exist = false;
        }

        return true;
    }

    function getSlashValidatorsLen() public view returns (uint256) {
        return slashValidators.length;
    }

    function getSlashRecord(address validator) public view returns (uint256) {
        return slashRecords[validator].missedBlocksCounter;
    }
}
