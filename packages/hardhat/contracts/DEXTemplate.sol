// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 💠 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this branch/repo. Also return variable names that may need to be specified exactly may be referenced (if you are confused, see solutions folder in this repo and/or cross reference with front-end code).
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    using SafeMath for uint256; //outlines use of SafeMath for uint256 variables
    IERC20 token; //instantiates the imported contract
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(
      address senderAddr,
      string transactionType,
      uint256 ethInput,
      uint256 tokenOutput
    );

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(
      address senderAddr,
      string transactionType,
      uint256 ethOutput,
      uint256 tokenInput
    );

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(
      address provider,
      uint256 liqMinted,
      uint256 eth_amount,
      uint256 token_amount
    );

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(
      address provider,
      uint256 eth_amount,
      uint256 withdrawn,
      uint256 token_amount
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
      // Ensures there is no liquidity before trying to initialize contract
      require(totalLiquidity == 0, "DEX: init - already has liquidity");
      // Assigns total liquidity to the current balance in the contract
      totalLiquidity = address(this).balance;
      // Assigns liquidity for the user deploying the contract equal to the total liquidity
      liquidity[msg.sender] = totalLiquidity;
      // Transfers the tokens sent by the deployer to this contract
      require(token.transferFrom(msg.sender, address(this), tokens), "DEX: init - transfer did not transact");
      // returns the total liquidity in the contract
      return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.

     Calculation: x * y = k (from https://www.youtube.com/watch?v=IL7cRj5vzEU)

     When there is a change in reserve and the change in another needs to be calculated (token swap) the following
     would be the update calculation:

     (x + dx)(y - dy) = k where dx is change in x (function input) and dy is change in y (function output)
     y - dy = k / (x - dx)
     dy = y - k / (x + dx)

     dy = y - xy / (x + dx)
        = (yx + ydx - xy) / (x + dx)
        = ydx / (x + dx)

      mul(997) in the numerator enables 0.3% trading fee
      it is balanced out by mul(1000) in the denominator
     */
     function price(
       uint256 xInput,
       uint256 xReserves,
       uint256 yReserves
     ) public view returns (uint256 yOutput) {
       uint256 xInputWithFee = xInput.mul(997);
       uint256 numerator = xInputWithFee.mul(yReserves); // ydx
       uint256 denominator = (xReserves.mul(1000)).add(xInputWithFee); // (x + dx)
       return (numerator / denominator);
     }


    /**
     * @notice returns liquidity for a user. Note this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL (user receives $BAL)
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
      // Ensures that there is some value being sent to this function
      require(msg.value > 0, "cannot swap 0 ETH");
      /*
      This is the amount of ETH in the contract minus what was just sent
      The calculation is created this way because it is a payable function and has
      received the ETH sent, therefore it must subtract the value of the ETH sent
      by the user to determine the amount in the reserves before calling this function
      */
      uint256 ethReserve = address(this).balance.sub(msg.value);
      // This is the amount of tokens in the contract
      uint256 token_reserve = token.balanceOf(address(this));
      // This is the token output given an amount of ETH sent to this function
      uint256 tokenOutput = price(msg.value, ethReserve, token_reserve);

      // Transfers the tokens to the user that calls this function
      require(token.transfer(msg.sender, tokenOutput), "ethToToken(): reverted swap.");
      // Emits an event that the ETH -> Token happened successfully
      emit EthToTokenSwap(msg.sender, "Eth to Balloons", msg.value, tokenOutput);
      // Returns amount of ETH sent out
      return tokenOutput;
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether (user receives ETH)
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
      // Ensures that the function is being called with some number of tokens that is not 0
      require(tokenInput > 0, "cannot swap 0 tokens");
      // This is the amount of tokens currently in the contract
      uint256 token_reserve = token.balanceOf(address(this));
      // This is the amount of ETH that should be returns for the amount of tokens in tokenInput
      uint256 ethOutput = price(tokenInput, token_reserve, address(this).balance);
      // Transfers tokens to the contract from user calling the function
      require(token.transferFrom(msg.sender, address(this), tokenInput), "tokenToEth(): reverted swap.");
      // Transfers ETH to user calling this function
      (bool sent, ) = msg.sender.call{ value: ethOutput }("");
      // Ensures that the ETH was sent successfully
      require(sent, "tokenToEth: revert in transferring eth to you!");
      // Emits event that the Token -> ETH happened successfully
      emit TokenToEthSwap(msg.sender, "Balloons to ETH", ethOutput, tokenInput);
      // Returns amount of ETH sent out
      return ethOutput;
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
      /*
      This is the amount of ETH in the contract minus what was just sent
      The calculation is created this way because it is a payable function and has
      received the ETH sent, therefore it must subtract the value of the ETH sent
      by the user to determine the amount in the reserves before calling this function
      */
      uint256 ethReserve = address(this).balance.sub(msg.value);
      // This is the amount of tokens in the contract
      uint256 tokenReserve = token.balanceOf(address(this));
      // This will be how much is deposited into the contract
      uint256 tokenDeposit;

      /*
      This is the price calculation (ydx) / (x + dx) on curent reserves
      dx has not changed so it is (ydx) / x - it will determine tokens
      that will be sent to the contract

      add(1) ensures that this is a nonzero number in the event that
      ETH and token reserves are both 0
      */
      tokenDeposit = (msg.value.mul(tokenReserve) / ethReserve).add(1);

      // This is the same as above, except that liquidityMinted is the total
      // liquidity pool when the contract was deployed so it gives you the
      // share of liquidity minted as a ratio of the whole liquidity ever minted
      uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;
      // Adds the liquidityMinted to the users total liquidity
      liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
      // Total liquidity is updated to include liquidityMinted
      totalLiquidity = totalLiquidity.add(liquidityMinted);

      // Transfers tokens to the contract (ETH has already been transferred to this contract)
      require(token.transferFrom(msg.sender, address(this), tokenDeposit));
      // Emits event of sender, how much liquidity has been added, how much ETH
      // has been sent to contracdt and how many tokens have been sent to contract
      emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
      // Returns total tokens added to the contract for the ETH sent
      return tokenDeposit;
    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount) public returns (uint256 eth_amount, uint256 token_amount) {
      // Ensures that the user has at least enough liquidity to satisfy withdrawal amount
      require(liquidity[msg.sender] >= amount, "withdraw: sender does not have enough liquidity to withdraw.");
      // This is the total ETH in the contract
      uint256 ethReserve = address(this).balance;
      // These are the total tokens in the contract
      uint256 tokenReserve = token.balanceOf(address(this));
      // This will be how much ETH is withdrawn
      uint256 ethWithdrawn;

      // Price calculation to determine amount of ETH that will be withdrawn
      // given a certain "amount" of tokens
      ethWithdrawn = amount.mul(ethReserve) / totalLiquidity;

      // Price calculation to determine amount of tokens that will be withdrawn
      // given a certain "amount" of ETH
      uint256 tokenAmount = amount.mul(tokenReserve) / totalLiquidity;
      // Resulting user liquidity is users liquidity minus "amount" withdrawn
      liquidity[msg.sender] = liquidity[msg.sender].sub(amount);
      // Total liquidity in the contract is liquidity minus "amount" withdrawn
      totalLiquidity = totalLiquidity.sub(amount);
      // Pays ETH to the user calling this contract
      (bool sent, ) = payable(msg.sender).call{ value: ethWithdrawn }("");
      // Ensures transaction was completed
      require(sent, "withdraw(): revert in transferring eth to you!");
      // Transfers tokens user
      require(token.transfer(msg.sender, tokenAmount));
      // Emits event of sender, amount requested, ETH withdrawn, and tokens withdrawn
      emit LiquidityRemoved(msg.sender, amount, ethWithdrawn, tokenAmount);
      return (ethWithdrawn, tokenAmount);
    }
}
