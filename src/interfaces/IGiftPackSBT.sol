// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);

    function locked(uint256 tokenId) external view returns (bool);
}

interface IERC4906 {
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
}

interface IGiftPackSBT {
    error NotMinter(address caller);
    error ZeroAddress();
    error EmptyBatch();
    error BatchTooLarge(uint256 size, uint256 max);
    error TokenDoesNotExist(uint256 tokenId);
    error Soulbound();

    event GiftMinted(address indexed to, uint256 indexed tokenId, uint16 indexed campaignId, uint8 designId);
    event Opened(uint256 indexed tokenId);
    event MinterUpdated(address indexed previousMinter, address indexed newMinter);
    event BaseURIUpdated(string previousBaseURI, string newBaseURI);
    event ContractURIUpdated(string previousContractURI, string newContractURI);

    function mintBatch(address[] calldata to, uint16 campaignId, uint8 designId) external returns (uint256 minted);

    function markOpened(uint256 tokenId) external;

    function burn(uint256 tokenId) external;

    function setMinter(address newMinter) external;

    function setBaseURI(string calldata newBaseURI) external;

    function setContractURI(string calldata newContractURI) external;

    function received(address account) external view returns (bool);

    function opened(uint256 tokenId) external view returns (bool);

    function campaignOf(uint256 tokenId) external view returns (uint16);

    function designOf(uint256 tokenId) external view returns (uint8);

    function contractURI() external view returns (string memory);

    function baseURI() external view returns (string memory);

    function nextTokenId() external view returns (uint256);

    function exists(uint256 tokenId) external view returns (bool);
}
