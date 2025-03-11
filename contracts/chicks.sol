//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";

contract CHICKS is ERC20Burnable, ERC20Permit, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // USDC token address
    IERC20 public usdcToken;
    address payable public FEE_ADDRESS;
    
    // AAVE integration
    IPool public aavePool;
    bool public aaveEnabled = false;
    uint256 public minLiquidityBuffer; // Minimum amount of USDC to keep in contract
    IERC20 public aUsdcToken; // aUSDC token from AAVE (interest-bearing token)

    uint256 private constant MIN = 1000;

    uint16 public sell_fee = 975;
    uint16 public buy_fee = 975;
    uint16 public buy_fee_leverage = 10;
    uint16 private constant FEE_BASE_1000 = 1000;

    uint16 private constant FEES_BUY = 125;
    uint16 private constant FEES_SELL = 125;

    bool public start = false;

    uint128 private constant USDCinWEI = 1 * 10 ** 6;

    uint256 private totalBorrowed = 0;
    uint256 private totalCollateral = 0;

    uint128 public constant maxSupply = 100 * 10 ** 9 * 10 ** 6; // 100 billion tokens with 6 decimals
    uint256 public totalMinted;
    uint256 public lastPrice = 0;

    struct Loan {
        uint256 collateral; // shares of token staked
        uint256 borrowed; // user reward per token paid
        uint256 endDate;
        uint256 numberOfDays;
    }

    mapping(address => Loan) public Loans;

    mapping(uint256 => uint256) public BorrowedByDate;
    mapping(uint256 => uint256) public CollateralByDate;
    uint256 public lastLiquidationDate;
    event Price(uint256 time, uint256 price, uint256 volumeInUSDC);
    event MaxUpdated(uint256 max);
    event SellFeeUpdated(uint256 sellFee);
    event FeeAddressUpdated(address _address);
    event BuyFeeUpdated(uint256 buyFee);
    event LeverageFeeUpdated(uint256 leverageFee);
    event Started(bool started);
    event Liquidate(uint256 time, uint256 amount);
    event LoanDataUpdate(
        uint256 collateralByDate,
        uint256 borrowedByDate,
        uint256 totalBorrowed,
        uint256 totalCollateral
    );
    event SendUSDC(address to, uint256 amount);
    event AaveSupply(uint256 amount, uint256 timestamp);
    event AaveWithdraw(uint256 amount, uint256 timestamp);
    event AaveEnabled(bool enabled);
    event MinLiquidityBufferUpdated(uint256 amount);
    event AaveYieldWithdrawn(address to, uint256 amount, uint256 timestamp);

    constructor(address _usdcToken) ERC20("CHICKS", "CHICKS") ERC20Permit("CHICKS") Ownable(msg.sender) {
        usdcToken = IERC20(_usdcToken);
        lastLiquidationDate = getMidnightTimestamp(block.timestamp);
        minLiquidityBuffer = 1000 * 10**6; // Default 1000 USDC as buffer
    }
    function setStart(uint256 _usdcAmount) public onlyOwner {
        require(FEE_ADDRESS != address(0x0), "Must set fee address");
        uint256 teamMint = _usdcAmount * MIN;
        require(teamMint >= 1 * 10 ** 6);
        mint(msg.sender, teamMint);

        _transfer(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            1 * 10 ** 6
        );
        start = true;
        emit Started(true);
    }

    function mint(address to, uint256 value) private {
        require(to != address(0x0), "Can't mint to to 0x0 address");
        totalMinted = totalMinted + value;
        require(totalMinted <= maxSupply, "NO MORE CHICKS");

        _mint(to, value);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function setFeeAddress(address _address) external onlyOwner {
        require(
            _address != address(0x0),
            "Can't set fee address to 0x0 address"
        );
        FEE_ADDRESS = payable(_address);
        emit FeeAddressUpdated(_address);
    }

    function setBuyFee(uint16 amount) external onlyOwner {
        require(amount <= 992, "buy fee must be greater than FEES_BUY");
        require(amount >= 975, "buy fee must be less than 2.5%");
        buy_fee = amount;
        emit BuyFeeUpdated(amount);
    }
    function setBuyFeeLeverage(uint16 amount) external onlyOwner {
        require(amount <= 25, "leverage buy fee must be less 2.5%");
        require(amount >= 0, "leverage buy fee must be greater than 0%");
        buy_fee_leverage = amount;
        emit LeverageFeeUpdated(amount);
    }
    function setSellFee(uint16 amount) external onlyOwner {
        require(amount <= 992, "sell fee must be greater than FEES_SELL");
        require(amount >= 975, "sell fee must be less than 2.5%");
        sell_fee = amount;
        emit SellFeeUpdated(amount);
    }
    function buy(address receiver, uint256 _usdcAmount) external nonReentrant {
        liquidate();
        require(start, "Trading must be initialized");

        require(receiver != address(0x0), "Reciever cannot be 0x0 address");

        // Mint CHICKS to sender
        // AUDIT: to user round down
        uint256 chicks = USDCtoChicks(_usdcAmount);
        
        // Transfer USDC from sender to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), _usdcAmount);

        mint(receiver, (chicks * getBuyFee()) / FEE_BASE_1000);

        // Team fee
        uint256 feeAddressAmount = _usdcAmount / FEES_BUY;
        require(feeAddressAmount > MIN, "must trade over min");
        sendUSDC(FEE_ADDRESS, feeAddressAmount);

        safetyCheck(_usdcAmount);
    }
    function sell(uint256 chicks) external nonReentrant {
        liquidate();

        // Total Eth to be sent
        // AUDIT: to user round down
        uint256 usdc = ChicksToUSDC(chicks);

        // Burn of JAY
        uint256 feeAddressAmount = usdc / FEES_SELL;
        _burn(msg.sender, chicks);

        // Payment to sender
        sendUSDC(msg.sender, (usdc * sell_fee) / FEE_BASE_1000);

        // Team fee

        require(feeAddressAmount > MIN, "must trade over min");
        sendUSDC(FEE_ADDRESS, feeAddressAmount);

        safetyCheck(usdc);
    }

    // Calculation may be off if liqudation is due to occur
    function getBuyAmount(uint256 amount) public view returns (uint256) {
        uint256 chicks = USDCtoChicksNoTrade(amount);
        return ((chicks * getBuyFee()) / FEE_BASE_1000);
    }
    function leverageFee(
        uint256 usdc,
        uint256 numberOfDays
    ) public view returns (uint256) {
        uint256 mintFee = (usdc * buy_fee_leverage) / FEE_BASE_1000;

        uint256 interest = getInterestFee(usdc, numberOfDays);

        return (mintFee + interest);
    }

    function leverage(
        uint256 usdc,
        uint256 numberOfDays
    ) public nonReentrant {
        require(start, "Trading must be initialized");
        require(
            numberOfDays < 366,
            "Max borrow/extension must be 365 days or less"
        );

        Loan memory userLoan = Loans[msg.sender];
        if (userLoan.borrowed != 0) {
            if (isLoanExpired(msg.sender)) {
                delete Loans[msg.sender];
            }
            require(
                Loans[msg.sender].borrowed == 0,
                "Use account with no loans"
            );
        }
        liquidate();
        uint256 endDate = getMidnightTimestamp(
            (numberOfDays * 1 days) + block.timestamp
        );

        uint256 usdcFee = leverageFee(usdc, numberOfDays);

        uint256 userUSDC = usdc - usdcFee;

        uint256 feeAddressAmount = (usdcFee * 3) / 10;
        uint256 userBorrow = (userUSDC * 99) / 100;
        uint256 overCollateralizationAmount = (userUSDC) / 100;
        uint256 subValue = feeAddressAmount + overCollateralizationAmount;
        uint256 totalFee = (usdcFee + overCollateralizationAmount);
        // Transfer USDC from sender to contract
        usdcToken.safeTransferFrom(msg.sender, address(this), totalFee);

        // AUDIT: to user round down
        uint256 userChicks = USDCtoChicksLev(userUSDC, subValue);
        mint(address(this), userChicks);

        require(feeAddressAmount > MIN, "Fees must be higher than min.");
        sendUSDC(FEE_ADDRESS, feeAddressAmount);

        addLoansByDate(userBorrow, userChicks, endDate);
        Loans[msg.sender] = Loan({
            collateral: userChicks,
            borrowed: userBorrow,
            endDate: endDate,
            numberOfDays: numberOfDays
        });

        safetyCheck(usdc);
    }

    function getInterestFee(uint256 amount, uint256 numberOfDays) public pure returns (uint256) {
    uint256 interest = Math.mulDiv(39000, numberOfDays, 365) + 1000;
    return Math.mulDiv(amount, interest, 1e6);
}


    function borrow(uint256 usdc, uint256 numberOfDays) public nonReentrant {
        require(
            numberOfDays < 366,
            "Max borrow/extension must be 365 days or less"
        );
        require(usdc != 0, "Must borrow more than 0");
        if (isLoanExpired(msg.sender)) {
            delete Loans[msg.sender];
        }
        require(
            Loans[msg.sender].borrowed == 0,
            "Use borrowMore to borrow more"
        );
        liquidate();
        uint256 endDate = getMidnightTimestamp(
            (numberOfDays * 1 days) + block.timestamp
        );

        uint256 usdcFee = getInterestFee(usdc, numberOfDays);

        uint256 feeAddressFee = (usdcFee * 3) / 10;

        //AUDIT: chicks required from user round up?
        uint256 userChicks = USDCtoChicksNoTradeCeil(usdc);

        uint256 newUserBorrow = (usdc * 99) / 100;

        Loans[msg.sender] = Loan({
            collateral: userChicks,
            borrowed: newUserBorrow,
            endDate: endDate,
            numberOfDays: numberOfDays
        });

        _transfer(msg.sender, address(this), userChicks);
        require(feeAddressFee > MIN, "Fees must be higher than min.");

        sendUSDC(msg.sender, newUserBorrow - usdcFee);
        sendUSDC(FEE_ADDRESS, feeAddressFee);

        addLoansByDate(newUserBorrow, userChicks, endDate);

        safetyCheck(usdcFee);
    }
    function borrowMore(uint256 usdc) public nonReentrant {
        require(!isLoanExpired(msg.sender), "Loan expired use borrow");
        require(usdc != 0, "Must borrow more than 0");
        liquidate();
        uint256 userBorrowed = Loans[msg.sender].borrowed;
        uint256 userCollateral = Loans[msg.sender].collateral;
        uint256 userEndDate = Loans[msg.sender].endDate;

        uint256 todayMidnight = getMidnightTimestamp(block.timestamp);
        uint256 newBorrowLength = (userEndDate - todayMidnight) / 1 days;

        uint256 usdcFee = getInterestFee(usdc, newBorrowLength);

        //AUDIT: chicks required from user round up?
        uint256 userChicks = USDCtoChicksNoTradeCeil(usdc);
        uint256 userBorrowedInChicks = USDCtoChicksNoTrade(userBorrowed);
        uint256 userExcessInChicks = ((userCollateral) * 99) /
            100 -
            userBorrowedInChicks;

        uint256 requireCollateralFromUser = userChicks;
        if (userExcessInChicks >= userChicks) {
            requireCollateralFromUser = 0;
        } else {
            requireCollateralFromUser =
                requireCollateralFromUser -
                userExcessInChicks;
        }

        uint256 feeAddressFee = (usdcFee * 3) / 10;

        uint256 newUserBorrow = (usdc * 99) / 100;

        uint256 newUserBorrowTotal = userBorrowed + newUserBorrow;
        uint256 newUserCollateralTotal = userCollateral +
            requireCollateralFromUser;

        Loans[msg.sender] = Loan({
            collateral: newUserCollateralTotal,
            borrowed: newUserBorrowTotal,
            endDate: userEndDate,
            numberOfDays: newBorrowLength
        });

        if (requireCollateralFromUser != 0) {
            _transfer(msg.sender, address(this), requireCollateralFromUser);
        }

        require(feeAddressFee > MIN, "Fees must be higher than min.");
        sendUSDC(FEE_ADDRESS, feeAddressFee);
        sendUSDC(msg.sender, newUserBorrow - usdcFee);

        addLoansByDate(newUserBorrow, requireCollateralFromUser, userEndDate);

        safetyCheck(usdcFee);
    }

    function removeCollateral(uint256 amount) public nonReentrant {
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        liquidate();
        uint256 collateral = Loans[msg.sender].collateral;
        // AUDIT: to user round down
        require(
            Loans[msg.sender].borrowed <=
                (ChicksToUSDC(collateral - amount) * 99) / 100,
            "Require 99% collateralization rate"
        );
        Loans[msg.sender].collateral = Loans[msg.sender].collateral - amount;
        _transfer(address(this), msg.sender, amount);
        subLoansByDate(0, amount, Loans[msg.sender].endDate);

        safetyCheck(0);
    }
    function repay(uint256 repayAmount) public nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        require(borrowed > repayAmount, "Must repay less than borrowed amount");
        require(repayAmount != 0, "Must repay something");

        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, cannot repay"
        );
        uint256 newBorrow = borrowed - repayAmount;
        
        // Transfer USDC from sender to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), repayAmount);
        Loans[msg.sender].borrowed = newBorrow;
        subLoansByDate(repayAmount, 0, Loans[msg.sender].endDate);

        safetyCheck(0);
    }
    function closePosition(uint256 repayAmount) public nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        uint256 collateral = Loans[msg.sender].collateral;
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        require(borrowed == repayAmount, "Must return entire borrowed amount");
        
        // Transfer USDC from sender to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), repayAmount);
        _transfer(address(this), msg.sender, collateral);
        subLoansByDate(borrowed, collateral, Loans[msg.sender].endDate);

        delete Loans[msg.sender];
        safetyCheck(0);
    }
    function flashClosePosition() public nonReentrant {
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        liquidate();
        uint256 borrowed = Loans[msg.sender].borrowed;

        uint256 collateral = Loans[msg.sender].collateral;

        // AUDIT: from user round up
        uint256 collateralInUSDC = ChicksToUSDC(collateral);
        _burn(address(this), collateral);

        uint256 collateralInUSDCAfterFee = (collateralInUSDC * 99) / 100;

        uint256 fee = collateralInUSDC / 100;
        require(
            collateralInUSDCAfterFee >= borrowed,
            "You do not have enough collateral to close position"
        );

        uint256 toUser = collateralInUSDCAfterFee - borrowed;
        uint256 feeAddressFee = (fee * 3) / 10;

        sendUSDC(msg.sender, toUser);

        require(feeAddressFee > MIN, "Fees must be higher than min.");
        sendUSDC(FEE_ADDRESS, feeAddressFee);
        subLoansByDate(borrowed, collateral, Loans[msg.sender].endDate);

        delete Loans[msg.sender];
        safetyCheck(borrowed);
    }

    function extendLoan(
        uint256 numberOfDays,
        uint256 extensionFee
    ) public nonReentrant returns (uint256) {
        uint256 oldEndDate = Loans[msg.sender].endDate;
        uint256 borrowed = Loans[msg.sender].borrowed;
        uint256 collateral = Loans[msg.sender].collateral;
        uint256 _numberOfDays = Loans[msg.sender].numberOfDays;

        uint256 newEndDate = oldEndDate + (numberOfDays * 1 days);

        uint256 loanFee = getInterestFee(borrowed, numberOfDays);
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        require(loanFee == extensionFee, "Loan extension fee incorrect");
        
        // Transfer USDC from sender to this contract
        usdcToken.safeTransferFrom(msg.sender, address(this), extensionFee);
        uint256 feeAddressFee = (loanFee * 3) / 10;
        require(feeAddressFee > MIN, "Fees must be higher than min.");
        sendUSDC(FEE_ADDRESS, feeAddressFee);
        subLoansByDate(borrowed, collateral, oldEndDate);
        addLoansByDate(borrowed, collateral, newEndDate);
        Loans[msg.sender].endDate = newEndDate;
        Loans[msg.sender].numberOfDays = numberOfDays + _numberOfDays;
        require(
            (newEndDate - block.timestamp) / 1 days < 366,
            "Loan must be under 365 days"
        );

        safetyCheck(extensionFee);
        return loanFee;
    }

    function liquidate() public {
        uint256 borrowed;
        uint256 collateral;

        while (lastLiquidationDate < block.timestamp) {
            collateral = collateral + CollateralByDate[lastLiquidationDate];
            borrowed = borrowed + BorrowedByDate[lastLiquidationDate];
            lastLiquidationDate = lastLiquidationDate + 1 days;
        }
        if (collateral != 0) {
            totalCollateral = totalCollateral - collateral;
            _burn(address(this), collateral);
        }
        if (borrowed != 0) {
            totalBorrowed = totalBorrowed - borrowed;
            emit Liquidate(lastLiquidationDate - 1 days, borrowed);
        }
    }

    function addLoansByDate(
        uint256 borrowed,
        uint256 collateral,
        uint256 date
    ) private {
        CollateralByDate[date] = CollateralByDate[date] + collateral;
        BorrowedByDate[date] = BorrowedByDate[date] + borrowed;
        totalBorrowed = totalBorrowed + borrowed;
        totalCollateral = totalCollateral + collateral;
        emit LoanDataUpdate(
            CollateralByDate[date],
            BorrowedByDate[date],
            totalBorrowed,
            totalCollateral
        );
    }
    function subLoansByDate(
        uint256 borrowed,
        uint256 collateral,
        uint256 date
    ) private {
        CollateralByDate[date] = CollateralByDate[date] - collateral;
        BorrowedByDate[date] = BorrowedByDate[date] - borrowed;
        totalBorrowed = totalBorrowed - borrowed;
        totalCollateral = totalCollateral - collateral;
        emit LoanDataUpdate(
            CollateralByDate[date],
            BorrowedByDate[date],
            totalBorrowed,
            totalCollateral
        );
    }

    // utility fxns
    function getMidnightTimestamp(uint256 date) public pure returns (uint256) {
        uint256 midnightTimestamp = date - (date % 86400); // Subtracting the remainder when divided by the number of seconds in a day (86400)
        return midnightTimestamp + 1 days;
    }

    function getLoansExpiringByDate(
        uint256 date
    ) public view returns (uint256, uint256) {
        return (
            BorrowedByDate[getMidnightTimestamp(date)],
            CollateralByDate[getMidnightTimestamp(date)]
        );
    }

    function getLoanByAddress(
        address _address
    ) public view returns (uint256, uint256, uint256) {
        if (Loans[_address].endDate >= block.timestamp) {
            return (
                Loans[_address].collateral,
                Loans[_address].borrowed,
                Loans[_address].endDate
            );
        } else {
            return (0, 0, 0);
        }
    }

    function isLoanExpired(address _address) public view returns (bool) {
        return Loans[_address].endDate < block.timestamp;
    }

    function getBuyFee() public view returns (uint256) {
        return buy_fee;
    }

    // Buy CHICKS

    function getTotalBorrowed() public view returns (uint256) {
        return totalBorrowed;
    }

    function getTotalCollateral() public view returns (uint256) {
        return totalCollateral;
    }

    function getBacking() public view returns (uint256) {
        return usdcToken.balanceOf(address(this)) + getTotalBorrowed() + getAaveSuppliedAmount();
    }

    function safetyCheck(uint256 usdc) private {
        uint256 newPrice = (getBacking() * USDCinWEI) / totalSupply();
        uint256 _totalColateral = balanceOf(address(this));
        require(
            _totalColateral >= totalCollateral,
            "The CHICKS balance of the contract must be greater than or equal to the collateral"
        );
        require(lastPrice <= newPrice, "The price of chicks cannot decrease");
        lastPrice = newPrice;
        emit Price(block.timestamp, newPrice, usdc);
        
        // After each operation, check if we can deposit to AAVE
        _optimizeYield();
    }

    function ChicksToUSDC(uint256 value) public view returns (uint256) {
        return Math.mulDiv(value, getBacking(), totalSupply());
    }

    function USDCtoChicks(uint256 value) public view returns (uint256) {
        return Math.mulDiv(value, totalSupply(), getBacking() - value);
    }

    function USDCtoChicksLev(
        uint256 value,
        uint256 fee
    ) public view returns (uint256) {
        uint256 backing = getBacking() - fee;
        return (value * totalSupply() + (backing - 1)) / backing;
    }

    function USDCtoChicksNoTradeCeil(
        uint256 value
    ) public view returns (uint256) {
        uint256 backing = getBacking();
        return (value * totalSupply() + (backing - 1)) / backing;
    }
    function USDCtoChicksNoTrade(uint256 value) public view returns (uint256) {
        uint256 backing = getBacking();
        return Math.mulDiv(value, totalSupply(), backing);
    }

    function sendUSDC(address _address, uint256 _value) internal {
        uint256 contractBalance = usdcToken.balanceOf(address(this));
        
        // If we don't have enough USDC in the contract but have deposits in AAVE
        if (contractBalance < _value && aaveEnabled && getAaveSuppliedAmount() > 0) {
            uint256 amountToWithdraw = _value - contractBalance;
            _withdrawFromAave(amountToWithdraw);
        }
        
        usdcToken.safeTransfer(_address, _value);
        emit SendUSDC(_address, _value);
    }

    //utils
    function getBuyChicks(uint256 amount) external view returns (uint256) {
        return
            (amount * (totalSupply()) * (buy_fee)) /
            (getBacking()) /
            (FEE_BASE_1000);
    }

    receive() external payable {}

    // ======== AAVE Integration Functions ========
    
    /**
     * @dev Set the AAVE pool address
     * @param _aavePool AAVE pool address
     */
    function setAavePool(address _aavePool) external onlyOwner {
        require(_aavePool != address(0), "Invalid AAVE pool address");
        aavePool = IPool(_aavePool);
    }
    
    /**
     * @dev Set the aUSDC token address
     * @param _aUsdcToken aUSDC token address
     */
    function setAUsdcToken(address _aUsdcToken) external onlyOwner {
        require(_aUsdcToken != address(0), "Invalid aUSDC token address");
        aUsdcToken = IERC20(_aUsdcToken);
    }
    
    /**
     * @dev Enable or disable AAVE integration
     * @param _enabled Whether AAVE integration is enabled
     */
    function setAaveEnabled(bool _enabled) external onlyOwner {
        aaveEnabled = _enabled;
        emit AaveEnabled(_enabled);
    }
    
    /**
     * @dev Set the minimum USDC liquidity buffer
     * @param _minLiquidityBuffer Minimum amount of USDC to keep in contract
     */
    function setMinLiquidityBuffer(uint256 _minLiquidityBuffer) external onlyOwner {
        minLiquidityBuffer = _minLiquidityBuffer;
        emit MinLiquidityBufferUpdated(_minLiquidityBuffer);
    }
    
    /**
     * @dev Get amount of USDC supplied to AAVE
     * @return uint256 Amount of USDC supplied to AAVE
     */
    function getAaveSuppliedAmount() public view returns (uint256) {
        if (!aaveEnabled || address(aavePool) == address(0)) {
            return 0;
        }
        
        (uint256 aaveCollateral, , , , , ) = aavePool.getUserAccountData(address(this));
        return aaveCollateral;
    }
    
    /**
     * @dev Get the current aUSDC token balance (directly from the token)
     * @return uint256 Current aUSDC token balance
     */
    function getAUsdcBalance() public view returns (uint256) {
        if (!aaveEnabled || address(aUsdcToken) == address(0)) {
            return 0;
        }
        
        return aUsdcToken.balanceOf(address(this));
    }
    
    /**
     * @dev Supply USDC to AAVE to earn yield
     * @param _amount Amount of USDC to supply
     */
    function supplyToAave(uint256 _amount) external onlyOwner {
        _supplyToAave(_amount);
    }
    
    /**
     * @dev Withdraw USDC from AAVE
     * @param _amount Amount of USDC to withdraw
     */
    function withdrawFromAave(uint256 _amount) external onlyOwner {
        _withdrawFromAave(_amount);
    }
    
    /**
     * @dev Internal function to supply USDC to AAVE
     * @param _amount Amount of USDC to supply
     */
    function _supplyToAave(uint256 _amount) internal {
        require(aaveEnabled, "AAVE integration not enabled");
        require(address(aavePool) != address(0), "AAVE pool not set");
        require(_amount > 0, "Amount must be greater than 0");
        
        uint256 balance = usdcToken.balanceOf(address(this));
        require(balance >= _amount + minLiquidityBuffer, "Insufficient balance or would go below buffer");
        
        // Approve AAVE pool to spend USDC
        usdcToken.approve(address(aavePool), _amount);
        
        // Supply to AAVE
        aavePool.supply(address(usdcToken), _amount, address(this), 0);
        
        emit AaveSupply(_amount, block.timestamp);
    }
    
    /**
     * @dev Internal function to withdraw USDC from AAVE
     * @param _amount Amount of USDC to withdraw
     */
    function _withdrawFromAave(uint256 _amount) internal {
        require(aaveEnabled, "AAVE integration not enabled");
        require(address(aavePool) != address(0), "AAVE pool not set");
        require(_amount > 0, "Amount must be greater than 0");
        
        // Withdraw from AAVE
        aavePool.withdraw(address(usdcToken), _amount, address(this));
        
        emit AaveWithdraw(_amount, block.timestamp);
    }
    
    /**
     * @dev Automatically optimize yield by supplying excess USDC to AAVE
     */
    function _optimizeYield() internal {
        if (!aaveEnabled || address(aavePool) == address(0)) {
            return;
        }
        
        uint256 balance = usdcToken.balanceOf(address(this));
        uint256 excessLiquidity = 0;
        
        // Calculate excess liquidity (anything above buffer)
       if (balance > minLiquidityBuffer) {
    excessLiquidity = balance - minLiquidityBuffer;
}

        
        // Supply excess liquidity to AAVE if it's significant
        if (excessLiquidity > MIN * 10) {
            _supplyToAave(excessLiquidity);
        }
    }
    
    /**
     * @dev Force optimization of yield (can be called by owner)
     */
    function optimizeYield() external onlyOwner {
        _optimizeYield();
    }
    
   function withdrawAaveYield(address _to, uint256 _withdrawAmount) external onlyOwner nonReentrant {
    require(_to != address(0), "Cannot withdraw to zero address");
    require(aaveEnabled, "AAVE integration not enabled");
    require(address(aavePool) != address(0), "AAVE pool not set");
    require(address(aUsdcToken) != address(0), "aUSDC token not set");
    
    // Get the ACTUAL principal amount from getAaveSuppliedAmount()
    uint256 principalAmount = getAaveSuppliedAmount();
    
    // Get actual aUSDC token balance
    uint256 currentAUsdcBalance = getAUsdcBalance();
    
    // Check if we have more aUSDC than our principal (meaning we have yield)
    require(currentAUsdcBalance > principalAmount, "No yield available");
    
    // Calculate ACTUAL available yield in aUSDC tokens
    uint256 availableYield = currentAUsdcBalance - principalAmount;
    
    // If _withdrawAmount is 0, withdraw all available yield
    uint256 withdrawAmount = _withdrawAmount == 0 ? availableYield : _withdrawAmount;
    require(withdrawAmount <= availableYield, "Withdrawal exceeds available yield");
    
    // Record USDC balance before withdrawal
    uint256 usdcBefore = usdcToken.balanceOf(address(this));
    
    // Withdraw from AAVE - this will convert aUSDC to USDC
    aUsdcToken.approve(address(aavePool), withdrawAmount);
    aavePool.withdraw(address(usdcToken), withdrawAmount, address(this));
    
    // Calculate how much USDC we received
    uint256 usdcReceived = usdcToken.balanceOf(address(this)) - usdcBefore;
    
    // Send the yield in USDC to the specified address
    usdcToken.safeTransfer(_to, usdcReceived);
    
    emit AaveYieldWithdrawn(_to, usdcReceived, block.timestamp);

}
function withdrawAllAaveYield(address _to) external onlyOwner nonReentrant {
    require(_to != address(0), "Cannot withdraw to zero address");
    require(aaveEnabled, "AAVE integration not enabled");
    require(address(aavePool) != address(0), "AAVE pool not set");
    require(address(aUsdcToken) != address(0), "aUSDC token not set");
    
    // Get the ACTUAL principal amount from getAaveSuppliedAmount()
    uint256 principalAmount = getAaveSuppliedAmount();
    
    // Get actual aUSDC token balance
    uint256 currentAUsdcBalance = getAUsdcBalance();
    
    // Check if we have more aUSDC than our principal (meaning we have yield)
    require(currentAUsdcBalance > principalAmount, "No yield available");
    
    // Calculate ACTUAL available yield in aUSDC tokens
    uint256 availableYield = currentAUsdcBalance - principalAmount;
    
    // Record USDC balance before withdrawal
    uint256 usdcBefore = usdcToken.balanceOf(address(this));
    
    // Withdraw from AAVE - this will convert aUSDC to USDC
    aUsdcToken.approve(address(aavePool), availableYield);
    aavePool.withdraw(address(usdcToken), availableYield, address(this));
    
    // Calculate how much USDC we received
    uint256 usdcReceived = usdcToken.balanceOf(address(this)) - usdcBefore;
    
    // Send the yield in USDC to the specified address
    usdcToken.safeTransfer(_to, usdcReceived);
    
    emit AaveYieldWithdrawn(_to, usdcReceived, block.timestamp);
}
}