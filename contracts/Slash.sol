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
        uint256 decreasePrevNumber;
        bool exist;
    }

    Validators validatorContract;

    mapping(address => SlashRecord) slashRecords;
    address[] public slashValidators;

    uint256 slashPrevNumber;
    uint256 decreasePrevNumber;

    event ValidatorMissedBlock(address indexed validator);
    event ValidatorDecreasedMissedBlockCounter(address []validators, uint256 []missedBlockCounters, uint256 decreasedCount);

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
        decreaseRate = 48;
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
        emit ValidatorMissedBlock(validator);
    }

    function decreaseMissedBlocksCounter()
        external
        onlyCoinbase
        onlyNotDecreased
        onlyInitialized
        onlyBlockEpoch()
    {
        if (slashValidators.length == 0) {
            return;
        }

        address[] memory decreasedValidators = new address[](slashValidators.length);
        uint256[] memory missedBlockCounters = new uint256[](slashValidators.length);
        uint256 decreasedCount = 0;
        for (uint256 i = 0; i < slashValidators.length; i++) {
            if (slashRecords[slashValidators[i]].exist && slashRecords[slashValidators[i]].decreasePrevNumber < block.number) {
                slashRecords[slashValidators[i]].decreasePrevNumber = block.number;
                if (slashRecords[slashValidators[i]].missedBlocksCounter > slashThreshold / decreaseRate) {
                    slashRecords[slashValidators[i]].missedBlocksCounter =
                        slashRecords[slashValidators[i]].missedBlocksCounter -
                        slashThreshold /
                        decreaseRate;
                } else {
                    slashRecords[slashValidators[i]].missedBlocksCounter = 0;
                }
                decreasedValidators[decreasedCount] = slashValidators[i];
                missedBlockCounters[decreasedCount] = slashRecords[slashValidators[i]].missedBlocksCounter;
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
                address lastValidator = slashValidators[slashValidators.length - 1];
                slashValidators[slashRecords[validator].index] = lastValidator;

                slashRecords[lastValidator].index = slashRecords[validator].index;
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
