// https://github.com/uniswapfoundation/v4-template/blob/main/test/utils/HookMiner.sol// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

/// @title CurrencyCloneMiner - a library for mining currency clone addresses
/// @dev This library is intended for `forge test` environments. There may be gotchas when using salts in `forge script` or `forge create`
library CurrencyCloneMiner {
    // Maximum number of iterations to find a salt, avoid infinite loops
    uint256 constant MAX_LOOP = 5_000;

    /// @notice Find 2 salts which ensure ordered ERC20 clones ... such that first has lower address than second
    /// @param deployer The address that will deploy the hook
    /// @param creationCode The creation code of an ERC20 contract
    /// @param constructorArgs_0 The encoded constructor arguments for first ERC20 clone
    /// @param constructorArgs_1 The encoded constructor arguments for second ERC20 clone
    /// @return mockERC20_clone_0 First ERC20 clone address
    /// @return mockERC20_clone_1 Second ERC20 clone address
    /// @return salt_0 Salt for first clone
    /// @return salt_1 Salt for second clone
    function find(
        address deployer,
        bytes memory creationCode,
        bytes memory constructorArgs_0,
        bytes memory constructorArgs_1
    ) internal pure returns (address mockERC20_clone_0, address mockERC20_clone_1, bytes32 salt_0, bytes32 salt_1) {
        bytes memory creationCodeWithArgs_0 = abi.encodePacked(
            creationCode,
            constructorArgs_0
        );
        bytes memory creationCodeWithArgs_1 = abi.encodePacked(
            creationCode,
            constructorArgs_1
        );

        uint256 salt;
        uint160 CURRENCY_MASK = 0xFFF;
        bool found_salt_0 = false;
        bool found_salt_1 = false;
        for (salt; salt < MAX_LOOP; salt++) {
            mockERC20_clone_0 = computeAddress(deployer, salt, creationCodeWithArgs_0);
            mockERC20_clone_1 = computeAddress(deployer, salt + 1, creationCodeWithArgs_1);
            
            if (uint160(mockERC20_clone_0) & CURRENCY_MASK == 0) {
                salt_0 = bytes32(salt);
                found_salt_0 = true;
            }
            if (uint160(mockERC20_clone_1) & CURRENCY_MASK == 1) {
                salt_1 = bytes32(salt);
                found_salt_1 = true;
            }
            if (found_salt_0 && found_salt_1) {
                return (mockERC20_clone_0, mockERC20_clone_1, salt_0, salt_1);
            }
        }

        revert("HookMiner: could not find salt");
    }

    /// @notice Precompute a contract address deployed via CREATE2
    /// @param deployer The address that will deploy the hook. In `forge test`, this will be the test contract `address(this)` or the pranking address
    ///                 In `forge script`, this should be `0x4e59b44847b379578588920cA78FbF26c0B4956C` (CREATE2 Deployer Proxy)
    /// @param salt The salt used to deploy the mockERC20 clone
    /// @param creationCode The creation code of a mockERC20 clone
    function computeAddress(
        address deployer,
        uint256 salt,
        bytes memory creationCode
    ) internal pure returns (address mockERC20_clone) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xFF),
                                deployer,
                                salt,
                                keccak256(creationCode)
                            )
                        )
                    )
                )
            );
    }
}