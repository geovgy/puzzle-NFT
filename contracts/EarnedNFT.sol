//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./RoyaltySplitter.sol";
import "./interfaces/IRoyaltySplitterFactory.sol";

contract EarnedNFT is ERC721URIStorage, Ownable, IERC2981 {
    mapping(uint256 => address) private _earners;
    uint256 private _earnerRoyalty = 1;
    uint256 private _ownerRoyalty = 4;
    mapping(uint256 => address) private _royaltyReceivers;
    IRoyaltySplitterFactory private immutable _royaltyFactory;

    mapping(uint256 => string[]) private _allTokenURIs;
    mapping(uint256 => string) private _baseTokenURIs;
    uint256 private _supply;

    uint256 private _generation;
    bool private _paused;
    
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string[] memory tokenURIs_,
        IRoyaltySplitterFactory factoryAddress_
    ) ERC721(name_, symbol_) {
        _setBaseURI(baseURI_);
        _allTokenURIs[_generation] = tokenURIs_;
        _royaltyFactory = factoryAddress_;
    }

    modifier notPaused() {
        require(!_paused, "Contract is paused at the moment.");
        _;
    }

    function maxSupply() external view returns (uint256) {
        return _allTokenURIs[_generation].length;
    }

    function mint(address to_) external onlyOwner notPaused {
        require(_supply < _allTokenURIs[_generation].length, "Max supply already reached.");
        uint256 tokenId = _supply + 1;
        _mint(to_, tokenId);
        _setTokenURI(tokenId, _allTokenURIs[_generation][_supply]);
        _supply++;
        _earners[tokenId] = to_;
        address[] memory payees = new address[](2);
        payees[0] = to_;
        payees[1] = owner();
        uint256[] memory royalties = new uint256[](2);
        royalties[0] = _earnerRoyalty;
        royalties[1] = _ownerRoyalty;
        address splitter = _royaltyFactory.create(payees, royalties);
        _royaltyReceivers[tokenId] = splitter;
    }

    function burn() external notPaused {
        require(_supply == _allTokenURIs[_generation].length, "Not all tokens minted yet.");
        require(super.balanceOf(msg.sender) == _allTokenURIs[_generation].length, "msg.sender does not own all tokens.");
        for(uint i=_generation + 1; _supply > i; i++) {
            uint256 tokenId = i;
            _burn(tokenId);
            delete _earners[tokenId];
            delete _royaltyReceivers[tokenId];

            // remove tokenURI from _allTokenURIs[_generation] array and reset length to 0
            // reset _supply to 0
        }

        _mint(msg.sender, _generation);
        _setTokenURI(_generation, _baseTokenURIs[_generation]);
        _generation++;
        _supply = _generation;
        _paused = true;
    }

    function _setBaseURI(string memory baseURI_) internal {
        _baseTokenURIs[_generation] = baseURI_;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURIs[_generation];
    }

    function setNewTokenURIs(string memory baseURI_, string[] memory tokenURIs_) external onlyOwner {
        require(_paused, "Contract is active.");
        _setBaseURI(baseURI_);
        _allTokenURIs[_generation] = tokenURIs_;
        _paused = false;
    }

    function royaltyReceiver(uint256 tokenId_) external view returns (address) {
        return _royaltyReceivers[tokenId_];
    }

    function royaltyInfo(
        uint256 tokenId, 
        uint256 salePrice
    ) external override view returns (
        address receiver, 
        uint256 royaltyAmount
    ) {
        receiver = _royaltyReceivers[tokenId];
        royaltyAmount = salePrice * (_earnerRoyalty + _ownerRoyalty) / 100;
    }
}