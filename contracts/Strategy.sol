// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/math/Math.sol";
import "@openzeppelinV3/contracts/utils/Address.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/mith/IBoardroom.sol";
import "./interfaces/mith/ITreasury.sol";
import "./interfaces/UniswapInterfaces/IUniswapV2Router02.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public MIS = IERC20(
        address(0x4b4D2e899658FB59b1D518b68fe836B100ee8958)
    );
    IERC20 public MIC = IERC20(
        address(0x368B3a58B5f49392e5C9E4C998cb0bB966752E51)
    );
    IERC20 public USDT = IERC20(
        address(0xdAC17F958D2ee523a2206206994597C13D831ec7)
    );
    IUniswapV2Router02 public router = IUniswapV2Router02(
        address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F)
    );
    IBoardroom public boardroom;
    ITreasury public treasury;
    uint256 public currentEpoch;

    constructor(address _vault, IBoardroom _boardroom, ITreasury _treasury) public BaseStrategy(_vault) {
        boardroom = _boardroom;
        treasury = _treasury;

        MIS.safeApprove(address(boardroom), uint256(-1));
        MIS.safeApprove(address(router), uint256(-1));
        MIC.safeApprove(address(router), uint256(-1));
        USDT.safeApprove(address(router), uint256(-1));

        currentEpoch = treasury.getCurrentEpoch();
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external override pure returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "Strategy<ProtocolName><TokenType>";
    }

    /*
     * Provide an accurate estimate for the total amount of assets (principle + return)
     * that this strategy is currently managing, denominated in terms of `want` tokens.
     * This total should be "realizable" e.g. the total value that could *actually* be
     * obtained from this strategy if it were to divest it's entire position based on
     * current on-chain conditions.
     *
     * NOTE: care must be taken in using this function, since it relies on external
     *       systems, which could be manipulated by the attacker to give an inflated
     *       (or reduced) value produced by this function, based on current on-chain
     *       conditions (e.g. this function is possible to influence through flashloan
     *       attacks, oracle manipulations, or other DeFi attack mechanisms).
     *
     * NOTE: It is up to governance to use this function in order to correctly order
     *       this strategy relative to its peers in order to minimize losses for the
     *       Vault based on sudden withdrawals. This value should be higher than the
     *       total debt of the strategy and higher than it's expected value to be "safe".
     */
    function estimatedTotalAssets() public override view returns (uint256) {
        // TODO: Build a more accurate estimate using the value of all positions in terms of `want`
        return want.balanceOf(address(this));
    }

    /*
     * Perform any strategy unwinding or other calls necessary to capture the "free return"
     * this strategy has generated since the last time it's core position(s) were adjusted.
     * Examples include unwrapping extra rewards. This call is only used during "normal operation"
     * of a Strategy, and should be optimized to minimize losses as much as possible. This method
     * returns any realized profits and/or realized losses incurred, and should return the total
     * amounts of profits/losses/debt payments (in `want` tokens) for the Vault's accounting
     * (e.g. `want.balanceOf(this) >= _debtPayment + _profit - _loss`).
     *
     * NOTE: `_debtPayment` should be less than or equal to `_debtOutstanding`. It is okay for it
     *       to be less than `_debtOutstanding`, as that should only used as a guide for how much
     *       is left to pay back. Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     */
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {

        _loss; //no loss

        if(_debtOutstanding > 0){
            boardroom.withdraw(_debtOutstanding);
            _debtPayment = Math.min(MIS.balanceOf(address(this)), _debtOutstanding);
        }
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position

        uint256 newEpoch = treasury.getCurrentEpoch();
        if(newEpoch > currentEpoch){
            if( boardroom.balanceOf(address(this)) > 0)
            {
                boardroom.claimReward();
                uint256 availableTokens = MIC.balanceOf(address(this));
                buyMisWithMic(availableTokens);


                _profit = MIS.balanceOf(address(this));
            }
            currentEpoch = newEpoch;
        }

        
    }

    /*
     * Perform any adjustments to the core position(s) of this strategy given
     * what change the Vault made in the "investable capital" available to the
     * strategy. Note that all "free capital" in the strategy after the report
     * was made is available for reinvestment. Also note that this number could
     * be 0, and you should handle that scenario accordingly.
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)

        _debtOutstanding; // handled in adjust position

        uint256 availableTokens = MIS.balanceOf(address(this));

        if(availableTokens > 0){
            boardroom.stake(availableTokens);
        }


    }

    /*
     * Make as much capital as possible "free" for the Vault to take. Some
     * slippage is allowed. The goal is for the strategy to divest as quickly as possible
     * while not suffering exorbitant losses. This function is used during emergency exit
     * instead of `prepareReturn()`. This method returns any realized losses incurred, and
     * should also return the amount of `want` tokens available to repay outstanding debt
     * to the Vault.
     */
    function exitPosition(uint256 _debtOutstanding)
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        // TODO: Do stuff here to free up as much as possible of all positions back into `want`
        // TODO: returns any realized profit/losses incurred, and should also return the amount
        // of `want` tokens available to repay back to the Vault.
    }

    /*
     * Liquidate as many assets as possible to `want`, irregardless of slippage,
     * up to `_amountNeeded`. Any excess should be re-invested here as well.
     */
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _amountFreed)
    {
        boardroom.withdraw(_amountNeeded);
        _amountFreed = Math.min(MIS.balanceOf(address(this)), _amountNeeded);
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    /*
     * Do anything necesseary to prepare this strategy for migration, such
     * as transfering any reserve or LP tokens, CDPs, or other tokens or stores of value.
     */
    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
        boardroom.exit();
        MIC.safeTransfer(_newStrategy, MIC.balanceOf(address(this)));
        MIS.safeTransfer(_newStrategy, MIS.balanceOf(address(this)));

    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        override
        view
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = address(MIS);
        protected[1] = address(MIC);
        return protected;

    }

    function buyMisWithMic(uint256 _amount) internal {
       
        address[] memory path = new address[](3);
        path[0] = address(MIC);
        path[1] = address(USDT);
        path[2] = address(MIS);

        // Market buy BAS with all available DAI
        router.swapExactTokensForTokens(
            _amount,
            0,
            path,
            address(this),
            now
        );
    }
}
