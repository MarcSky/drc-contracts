// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IGiftPackSBT, IERC5192, IERC4906} from "./interfaces/IGiftPackSBT.sol";

contract GiftPackSBT is IGiftPackSBT, IERC5192, IERC4906, ERC721, ERC721Burnable, Ownable2Step {
    uint256 public constant MAX_BATCH = 100;

    bytes4 private constant INTERFACE_ID_ERC5192 = 0xb45a3c0e;
    bytes4 private constant INTERFACE_ID_ERC4906 = 0x49064906;

    address public minter;

    mapping(address account => bool) public received;
    mapping(uint256 tokenId => bool) public opened;
    mapping(uint256 tokenId => uint16) public campaignOf;
    mapping(uint256 tokenId => uint8) public designOf;

    string private _baseTokenURI;
    string private _contractURI;
    uint256 private _nextTokenId = 1;

    modifier onlyMinter() {
        _checkMinter();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory contractURI_,
        address initialOwner,
        address initialMinter
    ) ERC721(name_, symbol_) Ownable(initialOwner) {
        if (initialMinter == address(0)) revert ZeroAddress();
        minter = initialMinter;
        _baseTokenURI = baseURI_;
        _contractURI = contractURI_;
        emit MinterUpdated(address(0), initialMinter);
        emit BaseURIUpdated("", baseURI_);
        emit ContractURIUpdated("", contractURI_);
    }

    function mintBatch(address[] calldata to, uint16 campaignId, uint8 designId)
        external
        onlyMinter
        returns (uint256 minted)
    {
        uint256 len = to.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_BATCH) revert BatchTooLarge(len, MAX_BATCH);

        uint256 tokenId = _nextTokenId;

        for (uint256 i = 0; i < len; ++i) {
            address account = to[i];
            if (account == address(0)) revert ZeroAddress();
            if (received[account]) continue;

            received[account] = true;
            campaignOf[tokenId] = campaignId;
            designOf[tokenId] = designId;

            emit GiftMinted(account, tokenId, campaignId, designId);
            emit Locked(tokenId);

            _safeMint(account, tokenId);

            unchecked {
                ++tokenId;
                ++minted;
            }
        }

        _nextTokenId = tokenId;
    }

    function markOpened(uint256 tokenId) external onlyMinter {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        if (opened[tokenId]) return;

        opened[tokenId] = true;

        emit Opened(tokenId);
        emit MetadataUpdate(tokenId);
    }

    function burn(uint256 tokenId) public override(ERC721Burnable, IGiftPackSBT) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        super.burn(tokenId);
    }

    function locked(uint256 tokenId) external view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);

        return true;
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) revert ZeroAddress();
        address previous = minter;
        minter = newMinter;
        emit MinterUpdated(previous, newMinter);
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        string memory previous = _baseTokenURI;
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(previous, newBaseURI);
    }

    function setContractURI(string calldata newContractURI) external onlyOwner {
        string memory previous = _contractURI;
        _contractURI = newContractURI;
        emit ContractURIUpdated(previous, newContractURI);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);

        return super.tokenURI(tokenId);
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == INTERFACE_ID_ERC5192 || interfaceId == INTERFACE_ID_ERC4906
            || super.supportsInterface(interfaceId);
    }

    function _checkMinter() internal view {
        if (msg.sender != minter) revert NotMinter(msg.sender);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert Soulbound();

        return super._update(to, tokenId, auth);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
