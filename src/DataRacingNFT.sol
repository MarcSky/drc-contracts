// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IDataRacingNFT} from "./interfaces/IDataRacingNFT.sol";

contract DataRacingNFT is IDataRacingNFT, ERC721, ERC721Burnable, ERC2981, Ownable2Step {
    uint256 public constant MAX_BATCH = 100;
    uint96 public constant DEFAULT_ROYALTY_BPS = 500;
    bytes4 private constant ERC4906_INTERFACE_ID = bytes4(0x49064906);

    address public minter;
    string private _baseTokenURI;
    uint256 private _nextTokenId = 1;

    modifier onlyMinter() {
        _checkMinter();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address initialOwner,
        address initialMinter
    ) ERC721(name_, symbol_) Ownable(initialOwner) {
        if (initialMinter == address(0)) revert ZeroAddress();
        minter = initialMinter;
        _baseTokenURI = baseURI_;
        _setDefaultRoyalty(initialOwner, DEFAULT_ROYALTY_BPS);
        emit MinterUpdated(address(0), initialMinter);
        emit BaseURIUpdated("", baseURI_);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return interfaceId == ERC4906_INTERFACE_ID || super.supportsInterface(interfaceId);
    }

    function safeMint(address to) external onlyMinter returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();
        tokenId = _nextTokenId;
        unchecked {
            _nextTokenId = tokenId + 1;
        }
        _safeMint(to, tokenId);
    }

    function safeMintBatch(address[] calldata recipients) external onlyMinter returns (uint256 firstTokenId) {
        uint256 len = recipients.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_BATCH) revert BatchTooLarge(len, MAX_BATCH);

        firstTokenId = _nextTokenId;
        unchecked {
            _nextTokenId = firstTokenId + len;
        }

        for (uint256 i = 0; i < len; ++i) {
            address to = recipients[i];
            if (to == address(0)) revert ZeroAddress();
            _safeMint(to, firstTokenId + i);
        }
    }

    function burn(uint256 tokenId) public override(ERC721Burnable, IDataRacingNFT) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        super.burn(tokenId);
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

    function announceMetadataUpdate(uint256 tokenId) external onlyMinter {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        emit MetadataUpdate(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist(tokenId);
        return super.tokenURI(tokenId);
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

    function _checkMinter() internal view {
        if (msg.sender != minter) revert NotMinter(msg.sender);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
