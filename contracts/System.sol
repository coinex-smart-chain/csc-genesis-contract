// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

contract System {
    bool public initialized;

    address public ValidatorContractAddr;
    address public SlashContractAddr;
    // just for test
    address public coinbase;


    modifier onlyCoinbase() {
        require(msg.sender == coinbase, "the message sender must be the block producer");
        _;
    }

    modifier onlyNotInitialized() {
        require(!initialized, "the contract already initialized");
        _;
    }

    modifier onlyInitialized() {
        require(initialized, "the contract not init yet");
        _;
    }

    modifier onlySlashContract() {
        require(msg.sender == SlashContractAddr, "the message sender must be slash contract");
        _;
    }

    modifier onlyValidatorsContract() {
        require(msg.sender == ValidatorContractAddr, "the message sender must be validator contract");
        _;
    }

    modifier onlyBlockEpoch(uint256 epoch) {
        require(block.number % epoch == 0, "Block epoch only");
        _;
    }

    function setContracts(address valAddr, address slashAddr) public {
        ValidatorContractAddr = valAddr;
        SlashContractAddr = slashAddr;
    }

    function setCoinbase(address _coinbase) public {
        coinbase = _coinbase;
    }

}
