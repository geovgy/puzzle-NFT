// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface KeeperCompatibleInterface {
    function checkUpkeep(bytes calldata checkData)
        external
        returns (bool upkeepNeeded, bytes memory performData);

    function performUpkeep(bytes calldata performData) external;
}

contract Trickle is KeeperCompatibleInterface {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /* ============ Structs ========== */

    // This struct represents a single recurring order set by a user
    struct RecurringOrder {
        address user;
        uint256 sellAmount;
        uint256 lastExecution;
        uint256 interval;
    }

    // This struct represents the combination of sell / buy token and all the orders for that pair
    struct TokenPair {
        address sellToken;
        address buyToken;
        mapping(bytes32 => RecurringOrder) orders;
        EnumerableSet.Bytes32Set registeredOrders;
    }

    // Data structure to return in checkUpkeep defining which orders will need to get executed
    struct TokenPairPendingOrders {
        bytes32 tokenPairHash;
        bytes32[] orders;
    }

    struct OrderDetails {
        bytes32 tokenPairHash;
        address sellToken;
        address buyToken;
        bytes32 orderHash;
        uint256 sellAmount;
        uint256 lastExecution;
        uint256 interval;
    }

    /* ============ Events ========== */
    event TokenPairCreated(address sellToken, address buyToken);

    event RecurringOrderUpdated(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 interval,
        uint256 startTimestamp
    );

    event SwapFailed(bytes32 tokenPairHash, bytes32 orderHash);
    event SwapSucceeded(bytes32 tokenPairHash, bytes32 orderHash);

    /* ============ State Varibles ========== */
    // Enumerable mappings to be able to later iterate over the orders of a single user
    mapping(address => EnumerableSet.Bytes32Set) userToTokenPairList;
    mapping(address => mapping(bytes32 => EnumerableSet.Bytes32Set)) userToOrderHash;

    // Mapping of a hash of sell / buy token on the TokenPair data
    mapping(bytes32 => TokenPair) tokenPairs;
    // Register initialized pairs in an enumerable set to be able to iterate over them
    EnumerableSet.Bytes32Set initializedTokenPairs;

    uint256 public minimumUpkeepInterval;
    uint256 lastUpkeep;

    /* ============ Public Methods ========== */

    /**
     * Creates new instance of Trickle contract
     *
     * @param _minimumUpkeepInterval   Minimum interval between upkeeps independent of users orders
     *
     */
    constructor(
        uint256 _minimumUpkeepInterval
    ) {
        minimumUpkeepInterval = _minimumUpkeepInterval;
    }

    /**
     * Creates a new recurring order for the given User starting immediately.
     *
     * @param _sellToken        Address of token to sell
     * @param _buyToken         Address of token to buy
     * @param _sellAmount       Amount of sell token to sell in each trade
     * @param _interval         Interval of execution in ms
     *
     */
    function setRecurringOrder(
        address _sellToken,
        address _buyToken,
        uint256 _sellAmount,
        uint256 _interval
    ) public {
        setRecurringOrderWithStartTimestamp(
            _sellToken,
            _buyToken,
            _sellAmount,
            _interval,
            0
        );
    }

    /**
     * Creates a new recurring order for the given User starting from the given block timestamp.
     *
     * @param _sellToken        Address of token to sell
     * @param _buyToken         Address of token to buy
     * @param _sellAmount       Amount of sell token to sell in each trade
     * @param _interval         Interval of execution in ms
     * @param _startTimestamp   Block timestamp from which to start the execution of this order
     *
     */
    function setRecurringOrderWithStartTimestamp(
        address _sellToken,
        address _buyToken,
        uint256 _sellAmount,
        uint256 _interval,
        uint256 _startTimestamp
    ) public {
        require(_sellAmount > 0, "amount cannot be 0");
        require(_sellToken != address(0), "sellToken cannot be zero address");
        require(_buyToken != address(0), "buyToken cannot be zero address");
        require(
            _interval > minimumUpkeepInterval,
            "interval has to be greater than minimumUpkeepInterval"
        );
        bytes32 tokenPairHash = keccak256(
            abi.encodePacked(_sellToken, _buyToken)
        );

        TokenPair storage tokenPair = tokenPairs[tokenPairHash];
        if (!initializedTokenPairs.contains(tokenPairHash)) {
            tokenPair.sellToken = _sellToken;
            tokenPair.buyToken = _buyToken;
            initializedTokenPairs.add(tokenPairHash);
            emit TokenPairCreated(_sellToken, _buyToken);
        }
        userToTokenPairList[msg.sender].add(tokenPairHash);

        bytes32 orderHash = keccak256(
            abi.encodePacked(
                msg.sender,
                _sellAmount,
                _interval,
                _startTimestamp
            )
        );
        RecurringOrder storage order = tokenPair.orders[orderHash];
        if (!tokenPair.registeredOrders.contains(orderHash)) {
            order.user = msg.sender;
            tokenPair.registeredOrders.add(orderHash);
        }
        userToOrderHash[msg.sender][tokenPairHash].add(orderHash);

        order.sellAmount = _sellAmount;
        order.lastExecution = _startTimestamp;
        order.interval = _interval;
        emit RecurringOrderUpdated(
            _sellToken,
            _buyToken,
            _sellAmount,
            _interval,
            _startTimestamp
        );
    }

    /**
     * Delete a given recurring order
     *
     * @param _tokenPairHash    Hash of sell and buyToken addresses identifying the tokenPair.
     * @param _orderHash        Hash of remaining order data (user address, amount, interval)
     *
     */
    function deleteRecurringOrder(bytes32 _tokenPairHash, bytes32 _orderHash)
        external
    {
        TokenPair storage tokenPair = tokenPairs[_tokenPairHash];
        require(
            tokenPair.registeredOrders.contains(_orderHash),
            "ORDER TO DELETE DOES NOT EXIST"
        );
        require(
            tokenPair.orders[_orderHash].user == msg.sender,
            "CANNOT DELETE ORDER OF DIFFERENT USER"
        );
        tokenPair.registeredOrders.remove(_orderHash);
        userToOrderHash[msg.sender][_tokenPairHash].remove(_orderHash);
        if(userToOrderHash[msg.sender][_tokenPairHash].length() == 0){
            userToTokenPairList[msg.sender].remove(_tokenPairHash);
        }

    }

    /**
     * Utility function for frontend to get data on a given order
     *
     * @param _tokenPairHash    Hash of sell and buyToken addresses identifying the tokenPair.
     * @param _orderHash        Hash of remaining order data (user address, amount, interval)
     *
     * @return Instance of RecurringOrder struct containing amount interval etc.
     *
     */
    function getOrderData(bytes32 _tokenPairHash, bytes32 _orderHash)
        external
        view
        returns (RecurringOrder memory)
    {
        TokenPair storage tokenPair = tokenPairs[_tokenPairHash];
        require(
            tokenPair.registeredOrders.contains(_orderHash),
            "ORDER DOES NOT EXIST"
        );
        return tokenPair.orders[_orderHash];
    }

    function getAllOrders(address _user)
        external
        view
        returns (OrderDetails[] memory orders)
    {
        uint256 numOrders = getNumOrders(_user);
        orders = new OrderDetails[](numOrders);
        bytes32[] memory tokenPairHashes = getTokenPairs(_user);
        uint256 k;
        for (uint256 i; i < tokenPairHashes.length; i++) {
            bytes32 tokenPairHash = tokenPairHashes[i];
            TokenPair storage tokenPair = tokenPairs[tokenPairHash];
            bytes32[] memory orderHashes = getOrders(_user, tokenPairHash);
            for (uint256 j; j < orderHashes.length; j++) {
                bytes32 orderHash = orderHashes[j];
                RecurringOrder storage recurringOrder = tokenPair.orders[orderHash];
                OrderDetails memory orderDetails = OrderDetails(
                    tokenPairHash,
                    tokenPair.sellToken,
                    tokenPair.buyToken,
                    orderHash,
                    recurringOrder.sellAmount,
                    recurringOrder.lastExecution,
                    recurringOrder.interval
                );
                orders[k] = orderDetails;
                k++;
            }
        }
    }

    function getNumOrders(address _user)
        public
        view
        returns (uint256 numOrders)
    {
        uint256 numTokenPairs = userToTokenPairList[_user].length();
        for (uint256 i; i < numTokenPairs; i++) {
            bytes32 tokenPairHash = userToTokenPairList[_user].at(i);
            numOrders += userToOrderHash[_user][tokenPairHash].length();
        }
    }

    /**
     * Utility function for frontend to get data on a given token pair
     *
     * @param _tokenPairHash    Hash of sell and buyToken addresses identifying the tokenPair.
     *
     * @return Address of token to be sold
     * @return Address of token to be bought
     *
     */
    function getTokenPairData(bytes32 _tokenPairHash)
        external
        view
        returns (address, address)
    {
        TokenPair storage tokenPair = tokenPairs[_tokenPairHash];
        return (tokenPair.sellToken, tokenPair.buyToken);
    }

    /**
     * Utility function for frontend to get all token pairs for which the given user has set orders
     *
     * @param _user    Address of the user for which to query active token pairs
     *
     * @return Array of tokenPair-hashes identifying combinations of sell / buyToken for which the user has active orders
     *
     */
    function getTokenPairs(address _user)
        public
        view
        returns (bytes32[] memory)
    {
        uint256 numTokenPairs = userToTokenPairList[_user].length();
        bytes32[] memory tokenPairHashes = new bytes32[](numTokenPairs);
        for (uint256 i; i < numTokenPairs; i++) {
            tokenPairHashes[i] = userToTokenPairList[_user].at(i);
        }
        return tokenPairHashes;
    }

    /**
     * List hashes of active orders for given tokenPair and user
     *
     * @param _user             Address of the user for which to query active token pairs
     * @param _tokenPairHash    Hash of sell and buyToken addresses identifying the tokenPair.
     *
     * @return Array of order-hashes identifying the orders set for given user and token pair
     *
     */
    function getOrders(address _user, bytes32 _tokenPairHash)
        public
        view
        returns (bytes32[] memory)
    {
        uint256 numOrders = userToOrderHash[_user][_tokenPairHash].length();
        bytes32[] memory orderHashes = new bytes32[](numOrders);
        for (uint256 i; i < numOrders; i++) {
            orderHashes[i] = userToOrderHash[_user][_tokenPairHash].at(i);
        }
        return orderHashes;
    }

    /**
     * Check if Upkeep is needed and generate performData
     *
     *
     * @return upkeepNeeded     Boolean indicating wether upkeep needs to be performed
     * @return performData      Serialized array of structs identifying orders to be executed in next upkeep
     *
     */
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        if (block.timestamp < lastUpkeep + minimumUpkeepInterval) {
            return (upkeepNeeded, performData);
        }

        uint256 numPairs = initializedTokenPairs.length();
        TokenPairPendingOrders[]
            memory ordersToExecute = new TokenPairPendingOrders[](numPairs);
        uint256 l;
        for (uint256 i = 0; i < numPairs; i++) {
            bytes32 tokenPairHash = initializedTokenPairs.at(i);
            uint256 numOrders = tokenPairs[tokenPairHash]
                .registeredOrders
                .length();
            if (numOrders > 0) {
                bytes32[] memory orders = new bytes32[](numOrders);
                uint256 k;
                for (uint256 j; j < numOrders; j++) {
                    bytes32 orderHash = tokenPairs[tokenPairHash]
                        .registeredOrders
                        .at(j);
                    RecurringOrder memory order = tokenPairs[tokenPairHash]
                        .orders[orderHash];
                    if (
                        block.timestamp > (order.lastExecution + order.interval)
                    ) {
                        orders[k] = orderHash;
                        k++;
                        upkeepNeeded = true;
                    }
                }
                ordersToExecute[l] = TokenPairPendingOrders(
                    tokenPairHash,
                    orders
                );
                l++;
            }
        }
        performData = abi.encode(ordersToExecute);
    }

    /**
     * Perform Upkeep executing all pending orders
     *
     * @param performData      Serialized array of structs identifying orders to be executed as returned by checkUpkeep
     *
     */
    function performUpkeep(bytes calldata performData) external override {
        TokenPairPendingOrders[] memory ordersToExecute = abi.decode(
            performData,
            (TokenPairPendingOrders[])
        );
        if (ordersToExecute.length > 0) {
            _executeOrdersForAllTokenPairs(ordersToExecute);
        }
    }

    /**
     * Internal helper function to execute all pending orders for all token pairs
     *
     * @param allPendingOrders   Array of structs with one element for each token pair that has pending orders. Each element contains a list of order hashes that need to be executed for this token pair
     *
     */
    function _executeOrdersForAllTokenPairs(
        TokenPairPendingOrders[] memory allPendingOrders
    ) internal {
        for (uint256 i; i < allPendingOrders.length; i++) {
            TokenPairPendingOrders
                memory tokenPairPendingOrders = allPendingOrders[i];
            if (tokenPairPendingOrders.tokenPairHash == bytes32(0)) break;
            _executeOrdersForSingleTokenPair(tokenPairPendingOrders);
        }
    }

    /**
     * Execute orders for one token pair
     *
     * @param pendingOrders   Struct containing tokenPair hash and list of order hashes that need to be executed for this token pair.
     *
     */
    function _executeOrdersForSingleTokenPair(
        TokenPairPendingOrders memory pendingOrders
    ) internal {
        if (pendingOrders.orders.length == 0) return;
        if (!initializedTokenPairs.contains(pendingOrders.tokenPairHash))
            return;

        TokenPair storage tokenPair = tokenPairs[pendingOrders.tokenPairHash];
        IERC20 sellToken = IERC20(tokenPair.sellToken);
        IERC20 buyToken = IERC20(tokenPair.buyToken);

        for (uint256 i; i < pendingOrders.orders.length; i++) {
            bytes32 orderHash = pendingOrders.orders[i];

            // ZeroHash signals last order to be executed
            if (orderHash == bytes32(0)) break;
            // Check that order is registered / not deleted
            if (!tokenPair.registeredOrders.contains(orderHash)) break;

            RecurringOrder storage recurringOrder = tokenPair.orders[orderHash];

            //Check that order is actually ready to be excuted
            if (
                block.timestamp <=
                (recurringOrder.lastExecution + recurringOrder.interval)
            ) break;

            uint256 sellAmount = recurringOrder.sellAmount;
            address user = recurringOrder.user;
            bool success = swapExactTokensForTokens(
                sellToken,
                buyToken,
                sellAmount,
                user
            );
            if (success) {
                recurringOrder.lastExecution = block.timestamp;
                emit SwapSucceeded(pendingOrders.tokenPairHash, orderHash);
            } else {
                emit SwapFailed(pendingOrders.tokenPairHash, orderHash);
            }
        }
    }
}
