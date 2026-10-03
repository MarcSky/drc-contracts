// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IDataRacingNFT {
    event MinterUpdated(address indexed previousMinter, address indexed newMinter);
    event BaseURIUpdated(string previousBaseURI, string newBaseURI);
    event MetadataUpdate(uint256 _tokenId);

    error ZeroAddress();
    error EmptyBatch();
    error BatchTooLarge(uint256 size, uint256 max);
    error NotMinter(address caller);
    error TokenDoesNotExist(uint256 tokenId);

    function safeMint(address to) external returns (uint256 tokenId);
    function safeMintBatch(address[] calldata recipients) external returns (uint256 firstTokenId);
    function burn(uint256 tokenId) external;

    function setMinter(address newMinter) external;
    function setBaseURI(string calldata newBaseURI) external;
    function announceMetadataUpdate(uint256 tokenId) external;

    function minter() external view returns (address);
    function baseURI() external view returns (string memory);
    function nextTokenId() external view returns (uint256);
    function exists(uint256 tokenId) external view returns (bool);

    function MAX_BATCH() external view returns (uint256);
}
