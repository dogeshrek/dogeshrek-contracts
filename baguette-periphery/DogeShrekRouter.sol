pragma solidity =0.6.6;

import '../baguette-core/interfaces/IDogeShrekFactory.sol';
import '../baguette-lib/libraries/TransferHelper.sol';

import './interfaces/IDogeShrekRouter.sol';
import './libraries/BaguetteLibrary.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWAVAX.sol';

contract DogeShrekRouter is IDogeShrekRouter {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WAVAX;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'DogeShrekRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WWDOGE) public {

        // WAVAX is WWDOGE

        factory = _factory;
        WAVAX = _WWDOGE;

        
    }

    receive() external payable {
        assert(msg.sender == WAVAX); // only accept AVAX via fallback from the WAVAX contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IDogeShrekFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IDogeShrekFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = BaguetteLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = BaguetteLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'DogeShrekRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = BaguetteLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'DogeShrekRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = BaguetteLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IDogeShrekPair(pair).mint(to);
    }
    function addLiquidityAVAX(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountAVAXMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountAVAX, uint liquidity) {
        (amountToken, amountAVAX) = _addLiquidity(
            token,
            WAVAX,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountAVAXMin
        );
        address pair = BaguetteLibrary.pairFor(factory, token, WAVAX);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWAVAX(WAVAX).deposit{value: amountAVAX}();
        assert(IWAVAX(WAVAX).transfer(pair, amountAVAX));
        liquidity = IDogeShrekPair(pair).mint(to);
        // refund dust AVAX, if any
        if (msg.value > amountAVAX) TransferHelper.safeTransferAVAX(msg.sender, msg.value - amountAVAX);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = BaguetteLibrary.pairFor(factory, tokenA, tokenB);
        IDogeShrekPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IDogeShrekPair(pair).burn(to);
        (address token0,) = BaguetteLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'DogeShrekRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'DogeShrekRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityAVAX(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountAVAXMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountAVAX) {
        (amountToken, amountAVAX) = removeLiquidity(
            token,
            WAVAX,
            liquidity,
            amountTokenMin,
            amountAVAXMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWAVAX(WAVAX).withdraw(amountAVAX);
        TransferHelper.safeTransferAVAX(to, amountAVAX);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = BaguetteLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IDogeShrekPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityAVAXWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountAVAXMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountAVAX) {
        address pair = BaguetteLibrary.pairFor(factory, token, WAVAX);
        uint value = approveMax ? uint(-1) : liquidity;
        IDogeShrekPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountAVAX) = removeLiquidityAVAX(token, liquidity, amountTokenMin, amountAVAXMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityAVAXSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountAVAXMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountAVAX) {
        (, amountAVAX) = removeLiquidity(
            token,
            WAVAX,
            liquidity,
            amountTokenMin,
            amountAVAXMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWAVAX(WAVAX).withdraw(amountAVAX);
        TransferHelper.safeTransferAVAX(to, amountAVAX);
    }
    function removeLiquidityAVAXWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountAVAXMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountAVAX) {
        address pair = BaguetteLibrary.pairFor(factory, token, WAVAX);
        uint value = approveMax ? uint(-1) : liquidity;
        IDogeShrekPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountAVAX = removeLiquidityAVAXSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountAVAXMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = BaguetteLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? BaguetteLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IDogeShrekPair(BaguetteLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = BaguetteLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'DogeShrekRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BaguetteLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = BaguetteLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'DogeShrekRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BaguetteLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactAVAXForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WAVAX, 'DogeShrekRouter: INVALID_PATH');
        amounts = BaguetteLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'DogeShrekRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWAVAX(WAVAX).deposit{value: amounts[0]}();
        assert(IWAVAX(WAVAX).transfer(BaguetteLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactAVAX(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WAVAX, 'DogeShrekRouter: INVALID_PATH');
        amounts = BaguetteLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'DogeShrekRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BaguetteLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWAVAX(WAVAX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferAVAX(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForAVAX(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WAVAX, 'DogeShrekRouter: INVALID_PATH');
        amounts = BaguetteLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'DogeShrekRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BaguetteLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWAVAX(WAVAX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferAVAX(to, amounts[amounts.length - 1]);
    }
    function swapAVAXForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WAVAX, 'DogeShrekRouter: INVALID_PATH');
        amounts = BaguetteLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'DogeShrekRouter: EXCESSIVE_INPUT_AMOUNT');
        IWAVAX(WAVAX).deposit{value: amounts[0]}();
        assert(IWAVAX(WAVAX).transfer(BaguetteLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust AVAX, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferAVAX(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = BaguetteLibrary.sortTokens(input, output);
            IDogeShrekPair pair = IDogeShrekPair(BaguetteLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = BaguetteLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? BaguetteLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BaguetteLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'DogeShrekRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactAVAXForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WAVAX, 'DogeShrekRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWAVAX(WAVAX).deposit{value: amountIn}();
        assert(IWAVAX(WAVAX).transfer(BaguetteLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'DogeShrekRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForAVAXSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WAVAX, 'DogeShrekRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BaguetteLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WAVAX).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'DogeShrekRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWAVAX(WAVAX).withdraw(amountOut);
        TransferHelper.safeTransferAVAX(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return BaguetteLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return BaguetteLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return BaguetteLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return BaguetteLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return BaguetteLibrary.getAmountsIn(factory, amountOut, path);
    }
}
