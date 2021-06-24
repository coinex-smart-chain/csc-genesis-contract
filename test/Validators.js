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

const monikerLength = 128;
const websiteLength = 256;
const emailLength = 256;
const detailLength = 1024;
const MinimalStakingCoin = 10000;
const MinimalOfStaking = 1000;
const StakingLockPeriod = 86400;
const WithdrawRewardPeriod = 28800;
const MaxValidatorNum = 101;
const ValidatorSlashAmount = 500;
const BlockEpoch = 10;
const BlockReward = new BN("1000000000000000000");
const Ether = new BN("1000000000000000000");

function generateRandomString(strSize) {
    strSize = strSize || 32;
    let base = "ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz0123456789";
    let str = "";
    for (let i = 0; i < strSize; i++) {
        str += base.charAt(Math.floor(Math.random() * base.length));
    }
    return str;
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

async function stakingValidator(valsIns, staker, validator, amount) {
    let stakingAmount = ether(String(amount));
    let stakingEvent = await valsIns.stake(validator, {
        from: staker,
        value: stakingAmount
    });

    expectEvent(
        stakingEvent,
        "Staking",
        {
            staker: staker,
            validator: validator,
            amount: stakingAmount
        }
    )
}

contract("Validators test", function (accounts) {
    var valsIns, slashIns, initValidators;
    var coinbase = accounts[0];
    var totalStake = new BN("0");

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

        // create validator
        //// unstaking test validator 
        await createValidator(valsIns, accounts[179], accounts[179], 0);
        //// withdraw reward validator
        await createValidator(valsIns, accounts[169], accounts[169], 0);
    })

    it("can only init once", async function () {
        await expectRevert(valsIns.initialize(initValidators), "the contract already initialized");
    })

    it("check const vals", async function () {
        let maxValidatorNum = await valsIns.MaxValidatorNum();
        expect(maxValidatorNum.toString()).to.equal(String(MaxValidatorNum));
        let stakingLockPeriod = await valsIns.StakingLockPeriod();
        expect(stakingLockPeriod.toString()).to.equal(String(StakingLockPeriod));
        let withdrawRewardPeriod = await valsIns.WithdrawRewardPeriod();
        expect(withdrawRewardPeriod.toString()).to.equal(String(WithdrawRewardPeriod));
        let minimalStakingCoin = await valsIns.MinimalStakingCoin();
        let stakingCoin = new BN(String(MinimalStakingCoin));
        stakingCoin = stakingCoin.mul(new BN('1000000000000000000'));
        expect(minimalStakingCoin.toString()).to.equal(stakingCoin.toString());
        let minimalOfStaking = await valsIns.MinimalOfStaking();
        let staking = new BN(String(MinimalOfStaking));
        staking = staking.mul(new BN('1000000000000000000'));
        expect(minimalOfStaking.toString()).to.equal(staking.toString());
    })

    describe("create validator", async function() {
        let validator = accounts[199];
        it("can't create validator if reward address == address(0)", async function () {
            await expectRevert(valsIns.create(constants.ZERO_ADDRESS, "", "", "", "", {
                from: validator
            }), "invalid receive reward address");
        })

        it("can't create validator if validator's first staking amount less than minimal staking amount", async function(){
            await expectRevert(valsIns.create(validator, "", "", "", "", {
                from: validator,
                value: ether(String(MinimalStakingCoin - 1))
            }), "staking amount must more than 10000cet");
        })

        it ("can't create validator if validator's moniker length longer than 70", async function() {
            let moniker = generateRandomString(monikerLength + 1);
            await expectRevert(valsIns.create(validator, moniker, "", "", "", {
                from: validator
            }), "invalid moniker length");
        })

        it ("can't create validator if validator's website length longer than 140", async function() {
            let website = generateRandomString(websiteLength + 1);
            await expectRevert(valsIns.create(validator, "", website, "", "", {
                from: validator
            }), "invalid website length");
        })

        it ("can't create validator if validator's email length longer than 140", async function() {
            let email = generateRandomString(emailLength + 1);
            await expectRevert(valsIns.create(validator, "", "", email, "", {
                from: validator
            }), "invalid email length");
        })

        it ("can't create validator if validator's details length longer than 280", async function() {
            let detail = generateRandomString(detailLength + 1);
            await expectRevert(valsIns.create(validator, "", "", "", detail, {
                from: validator
            }), "invalid details length");
        })

        it("can't create validator if validator has already exist", async function(){
            let moniker = generateRandomString(monikerLength);
            let website = generateRandomString(websiteLength);
            let email = generateRandomString(emailLength);
            let detail = generateRandomString(detailLength);
            let createEvent = await valsIns.create(
                validator, moniker, website, email, detail,
                { from: validator}
            );
            expectEvent(
                createEvent,
                'ValidatorCreated',
                {
                    validator: validator,
                    rewardAddr: validator
                }
            );

            await expectRevert(valsIns.create(validator, moniker, website, email, detail, {
                from: validator
            }), "validator already exist");
        })
    })

    describe("edit validator", async function() {
        let validator = accounts[0];
        it ("can't edit validator if validator not exist", async function () {
            let validator = accounts[198];
            await expectRevert(valsIns.edit(validator, "", "", "", "", {
                from: validator
            }), "validator isn't exist");
        })

        it("can't edit validator if reward address == address(0)", async function () {
            await expectRevert(valsIns.edit(constants.ZERO_ADDRESS, "", "", "", "", {
                from: validator
            }), "invalid receive reward address");
        })

        it("can't edit validator if validator init staking amount less than minimal staking amount", async function(){
            await expectRevert.unspecified(valsIns.edit(constants.ZERO_ADDRESS, "", "", "", "", {
                from: validator,
                value: ether(String(MinimalStakingCoin - 1))
            }));
        })

        it ("can't edit validator if validator's moniker length longer than 70", async function() {
            let moniker = generateRandomString(monikerLength + 1);
            await expectRevert(valsIns.edit(validator, moniker, "", "", "", {
                from: validator
            }), "invalid moniker length");
        })

        it ("can't edit validator if validator's website length longer than 140", async function() {
            let website = generateRandomString(websiteLength + 1);
            await expectRevert(valsIns.edit(validator, "", website, "", "", {
                from: validator
            }), "invalid website length");
        })

        it ("can't edit validator if validator's email length longer than 140", async function() {
            let email = generateRandomString(emailLength + 1);
            await expectRevert(valsIns.edit(validator, "", "", email, "", {
                from: validator
            }), "invalid email length");
        })

        it ("can't edit validator if validator's details length longer than 280", async function() {
            let detail = generateRandomString(detailLength + 1);
            await expectRevert(valsIns.edit(validator, "", "", "", detail, {
                from: validator
            }), "invalid details length");
        })
    })

    describe("stake", async function(){
        let validator = accounts[197];
        it ("can't stake a validator if validator is not exist", async function() {
            await expectRevert(valsIns.stake(validator, {
                from: validator,
                value: ether(String(MinimalStakingCoin))
            }), "validator is not exist");
        })

        it ("first staking must more than minimal staking amount", async function() {
            let createEvent = await valsIns.create(
                validator, "", "", "", "",
                { from: validator}
            );
            expectEvent(
                createEvent,
                'ValidatorCreated',
                {
                    validator: validator,
                    rewardAddr: validator
                }
            );

            await expectRevert(valsIns.stake(validator, {
                from: validator,
                value: ether(String(MinimalStakingCoin-1))
            }), "staking amount must more than 10000cet");
        })

        it ("can't stake when you are unstaking", async function() {
            let validator = accounts[196];
            let createEvent = await valsIns.create(
                validator, "", "", "", "",
                { from: validator}
            );
            expectEvent(
                createEvent,
                'ValidatorCreated',
                {
                    validator: validator,
                    rewardAddr: validator
                }
            );

            let stakingAmount = ether(String(MinimalStakingCoin));
            let stakingEvent = await valsIns.stake(validator, {
                from: validator,
                value: stakingAmount
            });

            expectEvent(
                stakingEvent,
                "Staking",
                {
                    staker: validator,
                    validator: validator,
                    amount: stakingAmount
                }
            )

            let unstakingEvent = await valsIns.unstake(validator, {
                from: validator
            });

            expectEvent(
                unstakingEvent,
                "Unstake",
                {
                    staker: validator,
                    validator: validator,
                    amount: stakingAmount
                }
            )

            await expectRevert(valsIns.stake(validator, {
                from: validator,
                value: ether(String(MinimalStakingCoin))
            }), "can't stake when you are unstaking");
        })

        it ("every staking must more than minimal of staking", async function() {
            let validator = accounts[195];
            let createEvent = await valsIns.create(
                validator, "", "", "", "",
                {
                    from: validator,
                    value: ether(String(MinimalStakingCoin))
                }
            );
            expectEvent(
                createEvent,
                'ValidatorCreated',
                {
                    validator: validator,
                    rewardAddr: validator
                }
            );

            await expectRevert(valsIns.stake(validator, {
                from: validator,
                value: ether(String(MinimalOfStaking-1))
            }), "staking amount must more than 1000cet");
        })
    })

    describe("unstake", async function(){
        let validator = accounts[189];
        it ("can't unstake if validator is not exist", async function() {
            await expectRevert(valsIns.unstake(validator, {
                from: validator
            }), "validator is not exist");
        })

        it ("can't unstake if staking amount is 0", async function() {
            let createEvent = await valsIns.create(
                validator, "", "", "", "",
                { from: validator}
            );
            expectEvent(
                createEvent,
                'ValidatorCreated',
                {
                    validator: validator,
                    rewardAddr: validator
                }
            );
            await expectRevert(valsIns.unstake(validator, {
                from: validator
            }), "you don't have any stake");
        })

        it ("can't unstake when your last unstaking hasn't finished", async function() {
            let validator = accounts[188];
            let createEvent = await valsIns.create(
                validator, "", "", "", "",
                { from: validator}
            );
            expectEvent(
                createEvent,
                'ValidatorCreated',
                {
                    validator: validator,
                    rewardAddr: validator
                }
            );

            let stakingAmount = ether(String(MinimalStakingCoin));
            let stakingEvent = await valsIns.stake(validator, {
                from: validator,
                value: stakingAmount
            });

            expectEvent(
                stakingEvent,
                "Staking",
                {
                    staker: validator,
                    validator: validator,
                    amount: stakingAmount
                }
            )

            let unstakingEvent = await valsIns.unstake(validator, {
                from: validator
            });

            expectEvent(
                unstakingEvent,
                "Unstake",
                {
                    staker: validator,
                    validator: validator,
                    amount: stakingAmount
                }
            )

            await expectRevert(valsIns.unstake(validator, {
                from: validator
            }), "you are already in unstaking status");
        })
    })

    describe("withdraw stake", async function(){
        let validator = accounts[179];
        it("can't withdraw staking if validator is not exist", async function() {
            let notExistValidator = accounts[178];
            await expectRevert(valsIns.withdrawStaking(notExistValidator, {
                from: notExistValidator
            }), "validator not exist");
        })

        it("can't withdraw staking if you haven't unstaked", async function() {
            let stakingAmount = ether(String(MinimalStakingCoin));
            let staker = accounts[178];
            let stakingEvent = await valsIns.stake(validator, {
                from: staker,
                value: stakingAmount
            });

            expectEvent(
                stakingEvent,
                "Staking",
                {
                    staker: staker,
                    validator: validator,
                    amount: stakingAmount
                }
            )

            let unstakingEvent = await valsIns.unstake(validator, {
                from: staker
            });

            expectEvent(
                unstakingEvent,
                "Unstake",
                {
                    staker: staker,
                    validator: validator,
                    amount: stakingAmount
                }
            );
            await expectRevert(valsIns.withdrawStaking(validator, {
                from: staker
            }), "your staking haven't unlocked yet");
        })

        it("can't withdraw staking if your last unstaking hasn't unlocked yet", async function() {
            let stakingAmount = ether(String(MinimalStakingCoin));
            let staker = accounts[177];
            let stakingEvent = await valsIns.stake(validator, {
                from: staker,
                value: stakingAmount
            });

            expectEvent(
                stakingEvent,
                "Staking",
                {
                    staker: staker,
                    validator: validator,
                    amount: stakingAmount
                }
            )
            await expectRevert(valsIns.withdrawStaking(validator, {
                from: staker
            }), "you have to unstake first");
        })

        it("can't withdraw staking if staking is 0", async function() {
            let staker = accounts[179];
            let validator = accounts[0];
            await expectRevert(valsIns.withdrawStaking(validator, {
                from: staker
            }), "you have to unstake first");
        })
    })

    describe("distributeBlockReward", async function(){
        it("distribute to validator contract with no stake(at genesis period)", async function () {
            let currentBlockNumber = await time.latestBlock();
            currentBlockNumber = currentBlockNumber.toNumber();
            if (currentBlockNumber % BlockEpoch != BlockEpoch - 1) {
                let advanceBlock = BlockEpoch - currentBlockNumber % BlockEpoch - 1;
                await time.advanceBlockTo(new BN(String(currentBlockNumber + advanceBlock)));
            }

            currentBlockNumber = await time.latestBlock();
            currentBlockNumber = currentBlockNumber.toNumber();
            expect(currentBlockNumber % BlockEpoch).to.equal(BlockEpoch - 1);

            let txFee = new BN("1");
            txFee = txFee.mul(Ether);
            let reward = txFee.add(BlockReward);
            reward = reward.mul(new BN(BlockEpoch));
            let activatedValidators = await valsIns.getActivatedValidators();
            let validatorCount = activatedValidators.length;
            let validatorRewards = {}
            for (let i = 0; i < validatorCount; i++) {
                let validatorInfo = await valsIns.getValidatorInfo(activatedValidators[i])
                validatorRewards[activatedValidators[i]] = {
                    'rewardAmount': validatorInfo[3]
                }
            }

            let rewardDistributedEvent = await valsIns.distributeBlockReward({
                from: coinbase,
                value: reward
            });

            let rewardAverage = reward.div(new BN(String(validatorCount)));
            let eventResult = expectEvent(rewardDistributedEvent, 'RewardDistributed');
            let distributedValidators = eventResult.args[0];
            let distributedRewards = eventResult.args[1];
            let distributeCount = eventResult.args[2];

            expect(distributeCount.toNumber()).to.equal(validatorCount);
            for (let i = 0; i < validatorCount; i ++) {
                let validator = distributedValidators[0];
                let validatorInfo = await valsIns.getValidatorInfo(validator);
                let rewardAmount = validatorInfo[3];
                let addReward = rewardAmount.sub(validatorRewards[validator]['rewardAmount']);
                expect(addReward.eq(rewardAverage)).to.equal(true);
            }
        })

        it("can't distribute block reward if the validator is not the block producer", async function(){
            let validator = accounts[1];
            await expectRevert(valsIns.distributeBlockReward({
                from: validator,
                value: ether('1')
            }), "the message sender must be the block producer");
        })
    })

    describe("withdraw block reward", async function() {
        it("can't withdraw reward if validator is not exist", async function() {
            let notExistValidator = accounts[168];
            await expectRevert(valsIns.withdrawRewards(notExistValidator, {
                from: notExistValidator
            }), "validator not exist");
        })

        it("can't withdraw reward if you are not the reward receiver of validator", async function() {
            let receiver = accounts[168];
            let validator = accounts[169];
            await expectRevert(valsIns.withdrawRewards(validator, {
                from: receiver
            }), "you are not the reward receiver of this validator");
        })

        it("can't withdraw reward too often", async function() {
            let receiver = accounts[169];
            let validator = accounts[169];
            await expectRevert(valsIns.withdrawRewards(validator, {
                from: receiver
            }), "you must wait enough blocks to withdraw your reward after latest withdraw of this validator");
        })

        it("can't withdraw reward if reward is 0", async function() {
            let receiver = accounts[169];
            let validator = accounts[169];
            // let currentBlockNumber = await time.latestBlock();
            // if (currentBlockNumber.toNumber() < WithdrawRewardPeriod) {
            //     await time.advanceBlockTo(new BN(String(WithdrawRewardPeriod)));
            // }
            // await expectRevert(valsIns.withdrawRewards(validator, {
            //     from: receiver
            // }), "you don't have any reward");
        })
    })

    describe("update set", async function () {
        it("update active validator set", async function () {
            let newValidators = [];
            for (let i = 1; i < 120; i++) {
                let stakingAmount = ether(String(MinimalStakingCoin * (i + 1)));
                await createValidator(valsIns, accounts[i], accounts[i], stakingAmount);
                if(i >= 120 - MaxValidatorNum) {
                    newValidators.push(accounts[i]);
                }
            }
            newValidators.sort()
    
            let result = await valsIns.getValidatorCandidate.call();
            let validatorAddresses = result[0];
            let count = result[2].toNumber();
            let validators = [];
            expect(count).to.equal(MaxValidatorNum);
            for (let i = 0; i < count; i++) {
                validators.push(validatorAddresses[i]);
            }
            validators.sort();
            for (let i = 0; i < MaxValidatorNum; i ++) {
                expect(validators[i]).to.equal(newValidators[i]);
            }

            let currentBlockNumber = await time.latestBlock();
            currentBlockNumber = currentBlockNumber.toNumber();
            if (currentBlockNumber % BlockEpoch != BlockEpoch - 1) {
                let advanceBlock = BlockEpoch - currentBlockNumber % BlockEpoch - 1;
                await time.advanceBlockTo(new BN(String(currentBlockNumber + advanceBlock)));
            }

            currentBlockNumber = await time.latestBlock();
            currentBlockNumber = currentBlockNumber.toNumber();
            expect(currentBlockNumber % BlockEpoch).to.equal(BlockEpoch - 1);

            let validatorUpdateEvent = await valsIns.updateActivatedValidators({
                from: coinbase
            });
        
            let activatedValidators = await valsIns.getActivatedValidators();
            expect(activatedValidators.length).to.equal(MaxValidatorNum);

            let newActivatedValidators = [];
            for (let i = 0; i < MaxValidatorNum; i++) {
                newActivatedValidators.push(activatedValidators[i]);
            }
            newActivatedValidators.sort();
    
            for (let i = 0; i < MaxValidatorNum; i ++) {
                expect(newActivatedValidators[i]).to.equal(newValidators[i]);
            }
            for (let i = 0; i < newActivatedValidators.length; i++) {
                let isActivated = await valsIns.isValidatorActivated(newActivatedValidators[i]);
                expect(isActivated).to.equal(true);
            }
        })

        it ("distribute reward to validator contract with stake", async function(){
            let currentBlockNumber = await time.latestBlock();
            currentBlockNumber = currentBlockNumber.toNumber();
            if (currentBlockNumber % BlockEpoch != BlockEpoch - 1) {
                let advanceBlock = BlockEpoch - currentBlockNumber % BlockEpoch - 1;
                await time.advanceBlockTo(new BN(String(currentBlockNumber + advanceBlock)));
            }

            currentBlockNumber = await time.latestBlock();
            currentBlockNumber = currentBlockNumber.toNumber();
            expect(currentBlockNumber % BlockEpoch).to.equal(BlockEpoch - 1);

            let txFee = new BN("1");
            txFee = txFee.mul(Ether);
            let reward = txFee.add(BlockReward);
            reward = reward.mul(new BN(BlockEpoch));
            let activatedValidators = await valsIns.getActivatedValidators();
            let validatorCount = activatedValidators.length;
            let validatorRewards = {}
            let totalStake = new BN("0");
            for (let i = 0; i < validatorCount; i++) {
                let validatorInfo = await valsIns.getValidatorInfo(activatedValidators[i])
                validatorRewards[activatedValidators[i]] = {
                    'rewardAmount': validatorInfo[3],
                    'stakingAmount': validatorInfo[2]
                }
                totalStake = totalStake.add(validatorInfo[2]);
            }

            let rewardDistributedEvent = await valsIns.distributeBlockReward({
                from: coinbase,
                value: reward
            });

            let eventResult = expectEvent(rewardDistributedEvent, 'RewardDistributed');
            let distributedValidators = eventResult.args[0];
            let distributedRewards = eventResult.args[1];
            let distributeCount = eventResult.args[2];

            expect(distributeCount.toNumber()).to.equal(validatorCount);
            let distributedAmount = new BN('0');
            for (let i = 0; i < validatorCount; i ++) {
                let validator = distributedValidators[i];
                let stakingReward = validatorRewards[validator]['stakingAmount'].mul(reward);
                stakingReward = stakingReward.div(totalStake);
                distributedAmount = distributedAmount.add(stakingReward);
                if ( i == validatorCount - 1) {
                    let remain = reward.sub(distributedAmount);
                    stakingReward = stakingReward.add(remain);
                }
                let addReward = distributedRewards[i];
                expect(addReward.eq(stakingReward)).to.equal(true);
            }
        })
    })
})

