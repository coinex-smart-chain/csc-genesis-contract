const Validators = artifacts.require('Validators');
const Slash = artifacts.require("Slash");

const {
    constants,
    expectRevert,
    expectEvent,
    time,
    ether,
    BN
} = require('@openzeppelin/test-helpers');

const { expect } = require('chai');

const Created = new BN("1");
const Staked = new BN("2");
const Unstaked = new BN("3");
const Jailed = new BN("4");
const slashThreshold = 48;
const BlockEpoch = 10;
const MaxValidatorNum = 101;
const MinimalStakingCoin = 10000;

async function slashValidator(slashIns, coinbase, validator) {
    let slashEvent = await slashIns.slash(validator, {from: coinbase});
    expectEvent(
        slashEvent,
        'ValidatorMissedBlock',
        {
            validator: validator
        }
    );
}

async function createValidator(valsIns, validator, rewardAddr, value) {
    let txObj = {from: validator}
    if ( value ) {
        txObj['value'] = value;
    }

    let createEvent = await valsIns.create(validator, rewardAddr, "", "", "", txObj);
    expectEvent(
        createEvent,
        'ValidatorCreated',
        {
            validator: validator,
            rewardAddr: validator
        }
    );
}

contract("Slash contract test", function (accounts) {
    var valsIns, slashIns, initValidators;
    var coinbase = accounts[0];

    before(async function () {
        valsIns = await Validators.new();
        slashIns = await Slash.new();

        initValidators = accounts.slice(0, 1);
        await valsIns.setContracts(valsIns.address, slashIns.address);
        await slashIns.setContracts(valsIns.address, slashIns.address);

        // init validator contract
        await valsIns.initialize(initValidators);
        await valsIns.setCoinbase(coinbase);
        await valsIns.setEpoch(BlockEpoch);

        // init slash contract
        await slashIns.initialize();
        await slashIns.setCoinbase(coinbase)
        await slashIns.setEpoch(BlockEpoch);
    })

    it("can only init once", async function () {
        await expectRevert(slashIns.initialize(), "the contract already initialized");
    })

    describe("slash", async function(){
        // it("can't call slash contract if the sender is not the block producer", async function(){
        //     let validator = accounts[1];
        //     await expectRevert(slashIns.slash(validator, {
        //         from: validator
        //     }), "the message sender must be the block producer");
        // })

        // it("can't call slash multi-times in same blocks", async function(){
        //     await slashValidator(slashIns, coinbase, coinbase);
        //     let missedBlockCounter = await slashIns.getSlashRecord(coinbase);
        //     expect(missedBlockCounter.toNumber()).to.equal(1);
        //     let randCount = Math.floor(Math.random() * 50);
        //     for (let i = 0; i < randCount; i++) {
        //         await slashValidator(slashIns, coinbase, coinbase);
        //     }
        //     missedBlockCounter = await slashIns.getSlashRecord(coinbase);
        //     expect(missedBlockCounter.toNumber()).to.equal(randCount + 1);
        // })

        it ("jailed validator", async function(){
            for (let i = 1; i < 10; i++) {
                let stakingAmount = ether(String(MinimalStakingCoin * (i + 1)));
                await createValidator(valsIns, accounts[i], accounts[i], stakingAmount);
            }
            
            let currentBlockNumber = await time.latestBlock();
            currentBlockNumber = currentBlockNumber.toNumber();
            if (currentBlockNumber % BlockEpoch != 0) {
                let advanceBlock = BlockEpoch - currentBlockNumber % BlockEpoch - 1;
                await time.advanceBlockTo(new BN(String(currentBlockNumber + advanceBlock)));
            }
            let validatorUpdateEvent = await valsIns.updateActivatedValidators({
                from: coinbase
            });
            let result = await valsIns.getValidatorCandidate.call();
            let validatorAddresses = result[0];
            let stakings = result[1];
            let count = result[2].toNumber();
            let validators = [];
            for (let i = 0; i < count; i++) {
                validators.push({
                    'address': validatorAddresses[i],
                    'staking': stakings[i]
                });
            }
            if (count > MaxValidatorNum) {
                count = MaxValidatorNum;
            }
            validators.sort(function(a, b){
                return -1 * a.staking.cmp(b);
            })

            let newSet = []
            for (let i = 0; i < count; i++) {
                newSet.push(validators[i].address);
            }

            let slashVal = newSet[1];
            let missedBlockCounter = await slashIns.getSlashRecord(slashVal);
            expect(missedBlockCounter.toNumber()).to.equal(0);
            let slashValidatorCount = await slashIns.getSlashValidatorsLen();
            expect(slashValidatorCount.toNumber()).to.equal(0);
            for (let i = 0; i < slashThreshold; i++) {
                missedBlockCounter = await slashIns.getSlashRecord(slashVal);
                expect(missedBlockCounter.toNumber()).to.equal(i);
                await slashValidator(slashIns, coinbase, slashVal);
                slashValidatorCount = await slashIns.getSlashValidatorsLen();
                expect(slashValidatorCount.toNumber()).to.equal(1);
            }
            missedBlockCounter = await slashIns.getSlashRecord(slashVal);
            expect(missedBlockCounter.toNumber()).to.equal(0);
            let validatoInfo = await valsIns.getValidatorInfo(slashVal);
            console.log(validatoInfo);
            let status = validatoInfo[1];
            expect(Jailed.eq(status)).to.equal(true);
        })
    })
})

