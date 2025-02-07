"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const wallet_1 = require("../coinbase/wallet");
const wallet_address_1 = require("../coinbase/address/wallet_address");
const utils_1 = require("./utils");
const __1 = require("..");
describe("Wallet Transfer", () => {
    let wallet;
    let walletModel;
    let defaultAddress;
    const walletId = "test-wallet-id";
    const addressId = "0x123abc...";
    beforeEach(() => {
        const addressModel = (0, utils_1.newAddressModel)(walletId, addressId);
        defaultAddress = new wallet_address_1.WalletAddress(addressModel);
        walletModel = {
            id: walletId,
            network_id: __1.Coinbase.networks.BaseSepolia,
            default_address: addressModel,
            feature_set: {},
        };
        wallet = wallet_1.Wallet.init(walletModel, "");
        // Mock getDefaultAddress to return our test address
        jest.spyOn(wallet, "getDefaultAddress").mockResolvedValue(defaultAddress);
        // Mock the createTransfer method on the default address
        jest.spyOn(defaultAddress, "createTransfer").mockResolvedValue({});
    });
    afterEach(() => {
        jest.restoreAllMocks();
    });
    describe("#createTransfer", () => {
        it("should pass through skipBatching to defaultAddress.createTransfer", async () => {
            const assetId = "eth";
            await wallet.createTransfer({
                amount: 1,
                assetId,
                destination: "0x123abc...",
                gasless: true,
                skipBatching: true,
            });
            expect(defaultAddress.createTransfer).toHaveBeenCalledWith({
                amount: 1,
                assetId,
                destination: "0x123abc...",
                gasless: true,
                skipBatching: true,
            });
            await wallet.createTransfer({
                amount: 1,
                assetId,
                destination: "0x123abc...",
                gasless: true,
                skipBatching: false,
            });
            expect(defaultAddress.createTransfer).toHaveBeenCalledWith({
                amount: 1,
                assetId,
                destination: "0x123abc...",
                gasless: true,
                skipBatching: false,
            });
        });
    });
});
