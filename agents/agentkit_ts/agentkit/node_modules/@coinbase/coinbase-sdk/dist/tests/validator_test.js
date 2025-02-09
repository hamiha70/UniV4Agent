"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const validator_1 = require("../coinbase/validator");
const types_1 = require("../coinbase/types");
const coinbase_1 = require("../coinbase/coinbase");
const api_1 = require("../client/api");
describe("Validator", () => {
    let validator;
    beforeEach(() => {
        const mockModel = {
            validator_id: "123",
            status: api_1.ValidatorStatus.Active,
            network_id: coinbase_1.Coinbase.networks.EthereumHolesky,
            asset_id: coinbase_1.Coinbase.assets.Eth,
            details: {
                effective_balance: {
                    amount: "100",
                    asset: { network_id: coinbase_1.Coinbase.networks.EthereumHolesky, asset_id: coinbase_1.Coinbase.assets.Eth },
                },
                balance: {
                    amount: "200",
                    asset: { network_id: coinbase_1.Coinbase.networks.EthereumHolesky, asset_id: coinbase_1.Coinbase.assets.Eth },
                },
                exitEpoch: "epoch-1",
                activationEpoch: "epoch-0",
                index: "0",
                public_key: "public-key-123",
                slashed: false,
                withdrawableEpoch: "epoch-2",
                withdrawal_address: "withdrawal-address-123",
            },
        };
        validator = new validator_1.Validator(mockModel);
    });
    test("getValidatorId should return the correct validator ID", () => {
        expect(validator.getValidatorId()).toBe("123");
    });
    test("getStatus should return the correct status", () => {
        expect(validator.getStatus()).toBe(types_1.ValidatorStatus.ACTIVE);
    });
    test("getNetworkId should return the correct network ID", () => {
        expect(validator.getNetworkId()).toBe(coinbase_1.Coinbase.networks.EthereumHolesky);
    });
    test("getAssetId should return the correct asset ID", () => {
        expect(validator.getAssetId()).toBe(coinbase_1.Coinbase.assets.Eth);
    });
    test("getActivationEpoch should return the correct activation epoch", () => {
        expect(validator.getActivationEpoch()).toBe("epoch-0");
    });
    test("getExitEpoch should return the correct exit epoch", () => {
        expect(validator.getExitEpoch()).toBe("epoch-1");
    });
    test("getIndex should return the correct index", () => {
        expect(validator.getIndex()).toBe("0");
    });
    test("getPublicKey should return the correct public key", () => {
        expect(validator.getPublicKey()).toBe("public-key-123");
    });
    test("isSlashed should return the correct slashed status", () => {
        expect(validator.isSlashed()).toBe(false);
    });
    test("getWithdrawableEpoch should return the correct withdrawable epoch", () => {
        expect(validator.getWithdrawableEpoch()).toBe("epoch-2");
    });
    test("getWithdrawalAddress should return the correct withdrawal address", () => {
        expect(validator.getWithdrawalAddress()).toBe("withdrawal-address-123");
    });
    test("getEffectiveBalance should return the correct effective balance", () => {
        expect(validator.getEffectiveBalance()).toEqual({
            amount: "100",
            asset: { network_id: coinbase_1.Coinbase.networks.EthereumHolesky, asset_id: coinbase_1.Coinbase.assets.Eth },
        });
    });
    test("getBalance should return the correct balance", () => {
        expect(validator.getBalance()).toEqual({
            amount: "200",
            asset: { network_id: coinbase_1.Coinbase.networks.EthereumHolesky, asset_id: coinbase_1.Coinbase.assets.Eth },
        });
    });
});
