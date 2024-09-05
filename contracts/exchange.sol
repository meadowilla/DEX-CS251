// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'DEX';

    // TODO: paste token contract address here
    // e.g. tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3
    address tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    // Fee Pools 
    uint private token_fee_reserves;
    uint private eth_fee_reserves;

    // Liquidity pool shares
    mapping(address => uint) private lps;

    // For Extra Credit only: to loop through the keys of the lps mapping
    address[] private lp_providers;   
    mapping(address => uint) private token_reward;
    mapping(address => uint) private eth_reward;

    // Total Pool Shares
    uint private total_shares = 0;

    // liquidity rewards
    uint private swap_fee_numerator = 3;                
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;

    uint private multiplier = 10**5;

    constructor() {}
    

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value / 10**18;
        k = token_reserves * eth_reserves;

        // Pool shares set to a large value to minimize round-off errors
        total_shares = 10**5;
        // Pool creator has some low amount of shares to allow autograder to run
        lps[msg.sender] = 100;
    }

    // For use for ExtraCredit ONLY
    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // Function getReserves
    function getReserves() public view returns (uint, uint) {
        return (eth_reserves, token_reserves);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    
    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        // check the input
        require(msg.value > 0, "Need ETH to add Liquidity");
        uint tokenSupply = token.balanceOf(msg.sender);
        console.log("TokenSupply: ", tokenSupply);
        console.log("Max_exchange_rate: ", max_exchange_rate);
        console.log("Min_exchange_rate: ", min_exchange_rate);

        // check the actual exchange rate
        uint actual_exchange_rate = (token_reserves * multiplier) / eth_reserves; 
        console.log("actual_exchange_rate: ", actual_exchange_rate);
        require(actual_exchange_rate <= max_exchange_rate, "The exchange rate should be <= max_change_rate");
        require(actual_exchange_rate >= min_exchange_rate, "The exchange rate should be >= min_change_rate");

        // add liquidity
        uint amountTokens = ((token_reserves * msg.value) / eth_reserves) / 10**18;
        console.log("msgValue: ", msg.value);
        console.log("amountTokens: ", amountTokens);
        require(amountTokens <= tokenSupply, "Not have enough tokens to add liquidity");
        token.transferFrom(msg.sender, address(this), amountTokens);

        // update tokens and eth reserves and k
        uint token_reserves_old = token_reserves;
        token_reserves = token.balanceOf(address(this));
        console.log("Address.balance: ", address(this).balance);
        eth_reserves = address(this).balance / 10**18; // whether is = address(this).balance or += msg.value
        k = token_reserves * eth_reserves;

        // add new lp_provider
        bool wasLpProvider = false;
        for (uint i=0; i<lp_providers.length; i++){
            if (msg.sender == lp_providers[i]){
                wasLpProvider = true;
            }
        }
        if (!wasLpProvider){
            lp_providers.push(msg.sender);
        }

        // update total_shares and lp's shares
        uint total_shares_old = total_shares;
        total_shares = (total_shares_old * token_reserves) / token_reserves_old;
        lps[msg.sender] = (total_shares_old * amountTokens) / token_reserves_old;
        
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        // check the input
        require(lps[msg.sender] != 0, "You aren't the liquidity provider");
        require(amountETH > 0, "Need remove more ETH");
        console.log("Remove ", amountETH, " wei");

        // calculate the fraction f
        uint amountETHReward = (lps[msg.sender] * eth_reward[msg.sender]) / total_shares;
        uint amountTokensReward = (lps[msg.sender] * token_reward[msg.sender]) / total_shares;
        console.log("amountETHReward: ", amountETHReward);
        console.log("amountTokensReward: ", amountTokensReward);
        
        // check the exchange rate and calculate the corresponding tokens
        uint actual_exchange_rate = (token_reserves * multiplier) / eth_reserves; // consider this exchange rate again
        console.log("Actual_exchange_rate: ", actual_exchange_rate);
        require(actual_exchange_rate <= max_exchange_rate, "Actual_exchange_rate should be <= max_exchange_rate"); 
        require(actual_exchange_rate >= min_exchange_rate, "Actual_exchange_rate should be >= min_exchange_rate");
        uint amountTokens = ((amountETH * actual_exchange_rate) / 10**18) / multiplier;
        console.log("receive ", amountTokens, " back");

        // send tokens-eth and rewards
        token.transfer(msg.sender, amountTokens + amountTokensReward);
        payable(msg.sender).transfer(amountETH + amountETHReward);

        // update token_reserves, eth_reserves and k
        uint token_reserves_old = token_reserves;
        token_reserves = token.balanceOf(address(this));
        eth_reserves = address(this).balance / 10**18;
        k = token_reserves * eth_reserves;

        // update total_share and lp's shares
        uint total_shares_old = total_shares;
        total_shares = (total_shares_old * token_reserves) / token_reserves_old;
        uint delta_lps = (total_shares_old * amountTokens) / token_reserves_old;
        lps[msg.sender] -= delta_lps;

        // update lp_providers
        if (lps[msg.sender] == 0){
            uint idx;
            for (uint i=0; i<lp_providers.length; i++){
                if (lp_providers[i] == msg.sender){
                    idx = i;
                    break;
                }
            }
            removeLP(idx);
        }
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        uint total_shares_old = total_shares;
        uint amountETH = (lps[msg.sender] * eth_reserves * 10**18) / total_shares_old;
        removeLiquidity(amountETH, max_exchange_rate, min_exchange_rate);    
    }
    /***  Define additional functions for liquidity fees here as needed ***/

    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
        require(amountTokens > 0, "Need more tokens to swap");
        require(amountTokens <= token.balanceOf(msg.sender), "Swap <= your tokens");

        // update token_fee_reserves and amountTokens for swap
        uint tokenFee = (amountTokens * swap_fee_numerator) / swap_fee_denominator;
        token_fee_reserves += tokenFee;
        // uint amountTokensForSwap = amountTokens * (multiplier - ((swap_fee_numerator * multiplier)/swap_fee_denominator)) / multiplier;
        uint amountTokensForSwap = amountTokens - tokenFee;
        console.log("Swap ", amountTokensForSwap, "tokens");

        // swap
        uint actual_exchange_rate = eth_reserves * multiplier / (token_reserves + amountTokensForSwap);
        console.log("with eth/token rate: ", actual_exchange_rate);
        if (multiplier > actual_exchange_rate){
            require(multiplier - actual_exchange_rate <= max_exchange_rate, 
                        "Slippage should be avoided");
        }
        uint amountETH = (amountTokensForSwap * actual_exchange_rate * 10**18) / multiplier;
        console.log("receive ", amountETH, "wei");
        require(eth_reserves - (amountETH / 10**18) >= 1, "Cannot swap all eth");
        payable(msg.sender).transfer(amountETH);
        token.transferFrom(msg.sender, address(this), amountTokens);

        // distribute token rewards for lps and update token_fee_reserves
        for (uint i=0; i<lp_providers.length; i++){
            uint tokenReward = (lps[lp_providers[i]] * tokenFee) / total_shares;
            token_reward[lp_providers[i]] += tokenReward;
        }

        // update token & eth reserves
        token_reserves = token.balanceOf(address(this)) - token_fee_reserves;
        eth_reserves = (address(this).balance - eth_fee_reserves) / 10**18;

        console.log("token_fee_reserves: ", token_fee_reserves);
        console.log("eth_fee_reserves: ", eth_fee_reserves);

        console.log("new token_reserve: ", token_reserves);
        console.log("new eth_reserve: ", eth_reserves);

    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        require(msg.value > 0, "Need more ETH to swap");
        require(msg.value <= msg.sender.balance, "Swap <= your balance");

        // update eth_fee_reserves and amountETH for swap
        uint ethFee = (msg.value * swap_fee_numerator) / swap_fee_denominator;
        eth_fee_reserves += ethFee;
        uint amountETH = msg.value - ethFee;
        console.log("Swap ", amountETH, "wei");
        
        // swap
        uint actual_exchange_rate = (token_reserves * multiplier) / (eth_reserves + (amountETH / 10**18));
        console.log("with token/eth rate: ", actual_exchange_rate);
        if (multiplier > actual_exchange_rate){
            require(multiplier - actual_exchange_rate <= max_exchange_rate, 
                        "Slippage should be avoided");
        }
        uint amountTokens = (actual_exchange_rate * (amountETH / 10**18)) / multiplier;
        console.log("receive ", amountTokens, " tokens");
        require(token_reserves - amountTokens >= 1, "Cannot swap all tokens");
        token.transfer(msg.sender, amountTokens);

        // distribute eth rewards for lps and update eth_fee_reserves
        for (uint i=0; i<lp_providers.length; i++){
            uint ethReward = (lps[lp_providers[i]] * ethFee) / total_shares;
            eth_reward[lp_providers[i]] += ethReward;
        }

        // update token & eth reserves
        token_reserves = token.balanceOf(address(this)) - token_fee_reserves;
        eth_reserves = (address(this).balance - eth_fee_reserves) / 10**18;

        console.log("token_fee_reserves: ", token_fee_reserves);
        console.log("eth_fee_reserves: ", eth_fee_reserves);

        console.log("new token_reserve: ", token_reserves);
        console.log("new eth_reserve: ", eth_reserves);
    }
}