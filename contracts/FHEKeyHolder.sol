// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";

contract EncryptedKeyManager is SepoliaZamaFHEVMConfig {
    // Structure for storing encrypted keys
    struct EncryptedKey {
        euint64 key; // The 8-byte (64-bit) encrypted key
        bool initialized; // Ensure the key is properly initialized
    }

    // Mapping from bytes32 (computed hash) to encrypted keys
    mapping(bytes32 => EncryptedKey) private keys;

    // Store a new encrypted key
    function storeKey(address userAddress, uint256 nftId, string calldata nftType, euint64 encryptedKey) external {
        // Generate the hash key
        bytes32 keyHash = keccak256(abi.encodePacked(userAddress, nftId, nftType));

        // Ensure the key is not already initialized
        require(!keys[keyHash].initialized, "Key already exists");

        // Store the key and mark it as initialized
        keys[keyHash] = EncryptedKey({ key: encryptedKey, initialized: true });

        // Allow the contract itself to access the key
        TFHE.allowThis(encryptedKey);
    }

    // Retrieve the encrypted key for a specific combination
    function getKey(address userAddress, uint256 nftId, string calldata nftType) external view returns (euint64) {
        // Generate the hash key
        bytes32 keyHash = keccak256(abi.encodePacked(userAddress, nftId, nftType));

        // Ensure the key exists
        require(keys[keyHash].initialized, "Key not found");

        return keys[keyHash].key;
    }

    // Re-encrypt the key for a specific user
    function addNewKey(address userAddress, uint256 nftId, string calldata nftType, address recipient) external {
        // Generate the hash key
        bytes32 keyHash = getDeterminsticKey(userAddress, nftId, nftType);

        // Ensure the key exists
        require(keys[keyHash].initialized, "Key not found");

        euint64 encryptedKey = keys[keyHash].key;

        // Re-encrypt the key for the recipient
        TFHE.allow(encryptedKey, recipient);
    }

    function getDeterminsticKey(
        address userAddress,
        uint256 nftId,
        string calldata nftType
    ) public pure returns (bytes32) {
        // Generate the hash key
        return keccak256(abi.encodePacked(userAddress, nftId, nftType));
    }
}
