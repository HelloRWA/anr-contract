// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC721Receiver.sol";
import "../storage/Auction3StorageFacet.sol";

contract Auction3 is ERC721StorageFacet, IERC721 {
    function construct() external returns (bool) {
        ERC721FacetStorage storage _ds = erc721Storage();
        _ds._name = "Auction3";
        _ds._symbol = "AUCT3";
        _ds._baseURI = "http://localhost:3000/";
        _ds.auctionExtensionTime = 5 minutes;
        _ds.auctionFeePercentage = 5;
        return true;
    }

    // application functions start
    function createToken(address to_) external returns (uint256) {
        return _mint(to_);
    }

    function listToAuction(
        uint256 tokenID_,
        uint256 startPrice_,
        uint256 duration_
    ) external {
        _requireMinted(tokenID_);
        _requireOwner(msg.sender, tokenID_);

        ERC721FacetStorage storage _ds = erc721Storage();
        Auction storage auction = _ds.auctions[tokenID_];
        require(!auction.active, "Auction already active");

        auction.startPrice = startPrice_;
        auction.endTime = block.timestamp + duration_;
        auction.active = true;
        auction.highestBid = 0;
        auction.highestBidder = address(0);
    }

    function placeBid(uint256 tokenID_) external payable {
        ERC721FacetStorage storage _ds = erc721Storage();

        Auction storage auction = _ds.auctions[tokenID_];
        require(auction.active, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.value > auction.highestBid, "Bid too low");

        // Extend auction if bid is placed near end
        if (auction.endTime - block.timestamp < _ds.auctionExtensionTime) {
            auction.endTime = block.timestamp + _ds.auctionExtensionTime;
        }

        // Refund previous highest bidder
        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        auction.bids[msg.sender] = msg.value;
    }

    function finalizeAuction(uint256 tokenID_) external {
        ERC721FacetStorage storage _ds = erc721Storage();
        Auction storage auction = _ds.auctions[tokenID_];
        require(auction.active, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction not ended");

        auction.active = false;

        if (auction.highestBidder != address(0)) {
            uint256 fee = (auction.highestBid * _ds.auctionFeePercentage) / 100;
            uint256 sellerAmount = auction.highestBid - fee;

            address seller = _owner(tokenID_);
            payable(seller).transfer(sellerAmount);
            payable(LibDiamond.contractOwner()).transfer(fee);

            _transferTo(seller, auction.highestBidder, tokenID_);
        }
    }
    // application functions end

    // base functions
    function updateERC721(string memory baseURI_) external returns (bool) {
        LibDiamond.enforceIsContractOwner();
        ERC721FacetStorage storage _ds = erc721Storage();
        _ds._baseURI = baseURI_;
        return true;
    }

    function symbol() public view virtual returns (string memory) {
        ERC721FacetStorage storage _ds = erc721Storage();
        return _ds._symbol;
    }

    function name() public view virtual returns (string memory) {
        ERC721FacetStorage storage _ds = erc721Storage();
        return _ds._name;
    }

    function tokenURI(uint256 tokenID_) public view returns (string memory) {
        _requireMinted(tokenID_);
        ERC721FacetStorage storage _ds = erc721Storage();
        string memory _base = _ds._baseURI;
        return string(abi.encodePacked(_base, tokenID_));
    }

    // ERC721 INTERFACE FUNCTIONS

    function balanceOf(address account_) external view returns (uint256) {
        ERC721FacetStorage storage _ds = erc721Storage();
        return _ds._balances[account_];
    }

    function ownerOf(uint256 tokenID_) public view virtual returns (address) {
        _requireMinted(tokenID_);
        return _owner(tokenID_);
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        return _transfer(msg.sender, to_, amount_);
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 tokenID_
    ) external {
        _requireAuth(from_, tokenID_);
        _transfer(from_, to_, tokenID_);
    }

    function approve(address operator_, uint256 tokenID_) external {
        _approve(msg.sender, operator_, tokenID_);
    }

    function setApprovalForAll(address operator_, bool approved_) external {
        _setApprovalForAll(msg.sender, operator_, approved_);
    }

    function getApproved(
        uint256 tokenId
    ) external view returns (address operator) {
        ERC721FacetStorage storage _ds = erc721Storage();
        return _ds._tokenApprovals[tokenId];
    }

    function isApprovedForAll(
        address owner_,
        address operator_
    ) public view returns (bool) {
        ERC721FacetStorage storage _ds = erc721Storage();
        return _ds._operatorApprovals[owner_][operator_];
    }

    function safeTransferFrom(
        address from_,
        address to_,
        uint256 tokenID_,
        bytes memory data_
    ) public {
        _requireAuth(msg.sender, tokenID_);
        _safeTransfer(from_, to_, tokenID_, data_);
    }

    function safeTransferFrom(
        address from_,
        address to_,
        uint256 tokenID_
    ) external {
        safeTransferFrom(from_, to_, tokenID_, "");
    }

    // PRIVATE FUNCTIONS

    function _setApprovalForAll(
        address owner_,
        address operator_,
        bool approved_
    ) internal virtual {
        require(owner_ != operator_, "ERC721: approve to caller");

        ERC721FacetStorage storage _ds = erc721Storage();
        _ds._operatorApprovals[owner_][operator_] = approved_;

        emit ApprovalForAll(owner_, operator_, approved_);
    }

    function _approve(
        address owner_,
        address operator_,
        uint256 tokenID_
    ) private returns (bool) {
        require(
            ownerOf(tokenID_) != operator_,
            "ERC721: Approval to current owner"
        );
        _requireAuth(owner_, tokenID_);

        ERC721FacetStorage storage _ds = erc721Storage();
        _ds._tokenApprovals[tokenID_] = operator_;

        emit Approval(ownerOf(tokenID_), operator_, tokenID_);
        return true;
    }

    function _mint(address to_) private returns (uint256) {
        require(to_ != address(0), "ERC721: Cannot transfer to 0 address");
        ERC721FacetStorage storage _ds = erc721Storage();
        _ds._idx += 1;
        uint256 _tokenID = _ds._idx;
        _ds._balances[to_] += 1;
        _ds._owners[_tokenID] = to_;

        emit Transfer(address(0), to_, _tokenID);
        return _tokenID;
    }

    function _transferTo(
        address from_,
        address to_,
        uint256 tokenID_
    ) private returns (bool) {
        ERC721FacetStorage storage _ds = erc721Storage();
        require(!_ds.auctions[tokenID_].active, "Auction still active");

        delete _ds._tokenApprovals[tokenID_];
        _ds._owners[tokenID_] = to_;
        _ds._balances[from_] -= 1;
        _ds._balances[to_] += 1;

        emit Transfer(from_, to_, tokenID_);
        return true;
    }

    function _transfer(
        address from_,
        address to_,
        uint256 tokenID_
    ) private returns (bool) {
        require(to_ != address(0), "ERC721: Cannot transfer to 0 address");
        _requireMinted(tokenID_);
        _requireOwner(from_, tokenID_);
        /* _requireAuth(from_, tokenID_); */

        _transferTo(from_, to_, tokenID_);
        return true;
    }

    function _safeTransfer(
        address from_,
        address to_,
        uint256 tokenID_,
        bytes memory data_
    ) internal {
        _transfer(from_, to_, tokenID_);
        _requireReciever(from_, to_, tokenID_, data_);
    }

    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "ERC721: invalid token ID");
    }

    function _requireAuth(address from_, uint256 tokenID_) private view {
        require(
            _hasAuth(from_, tokenID_),
            "ERC721: Not token owner or approved"
        );
    }

    function _requireOwner(address from_, uint256 tokenID_) private view {
        require(_owner(tokenID_) == from_, "ERC721: Not token owner");
    }

    function _requireReciever(
        address from_,
        address to_,
        uint256 tokenID_,
        bytes memory data_
    ) private {
        require(
            _checkOnERC721Received(from_, to_, tokenID_, data_),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function _owner(uint256 tokenID_) internal view returns (address) {
        ERC721FacetStorage storage _ds = erc721Storage();
        return _ds._owners[tokenID_];
    }

    function _hasAuth(
        address from_,
        uint256 tokenID_
    ) internal view returns (bool) {
        address _ownerAddress = _owner(tokenID_);
        return _ownerAddress == from_ || isApprovedForAll(_ownerAddress, from_);
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owner(tokenId) != address(0);
    }

    function _hasContract(address account_) private view returns (bool) {
        return account_.code.length > 0;
    }

    function _checkOnERC721Received(
        address from_,
        address to_,
        uint256 tokenID_,
        bytes memory data_
    ) private returns (bool) {
        if (_hasContract(to_)) {
            try
                IERC721Receiver(to_).onERC721Received(
                    msg.sender,
                    from_,
                    tokenID_,
                    data_
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}
