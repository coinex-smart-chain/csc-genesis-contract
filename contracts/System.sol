// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

contract System {
    bool public initialized;

    address public constant ValidatorContractAddr = 0x0000000000000000000000000000000000001000;
    address public constant SlashContractAddr = 0x0000000000000000000000000000000000001001;


    modifier onlyCoinbase() {
        require(msg.sender == block.coinbase, "the message sender must be the block producer");
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

}
