// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CertificateNFT is ERC721URIStorage, Ownable {
    uint256 private nextCertificateId;

    constructor() ERC721("LearnAndEarnCertificate", "LEC") Ownable(msg.sender) {
        nextCertificateId = 1;
    }

    function mintCertificate(address to, string memory metadataURI) external onlyOwner {
        uint256 newCertificateId = nextCertificateId;
        _mint(to, newCertificateId);
        _setTokenURI(newCertificateId, metadataURI);
        nextCertificateId++;
    }
}
