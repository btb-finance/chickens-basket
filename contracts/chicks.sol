//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CHICKS is ERC20Burnable, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    address public FEE_ADDRESS;
    address public immutable USDC_TOKEN;

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

    uint128 public constant maxSupply = 10e28;
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

    constructor(address _usdcToken) ERC20("Chicks", "CHICKS") Ownable(msg.sender) {
        require(_usdcToken != address(0), "USDC token address cannot be zero");
        USDC_TOKEN = _usdcToken;
        lastLiquidationDate = getMidnightTimestamp(block.timestamp);
    }

    function setStart(uint256 usdcAmount) public onlyOwner {
        require(FEE_ADDRESS != address(0x0), "Must set fee address");
        require(usdcAmount >= 1 * 10**6, "Must provide at least 1 USDC");
        
        IERC20(USDC_TOKEN).safeTransferFrom(msg.sender, address(this), usdcAmount);
        
        uint256 teamMint = usdcAmount * MIN;
        mint(msg.sender, teamMint);

        _transfer(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            1 * 10**6
        );
        start = true;
        emit Started(true);
    }

    function mint(address to, uint256 value) private {
        require(to != address(0x0), "Can't mint to 0x0 address");
        totalMinted = totalMinted + value;
        require(totalMinted <= maxSupply, "NO MORE CHICKS");

        _mint(to, value);
    }

    function setFeeAddress(address _address) external onlyOwner {
        require(
            _address != address(0x0),
            "Can't set fee address to 0x0 address"
        );
        FEE_ADDRESS = _address;
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

    function buy(address receiver, uint256 usdcAmount) external nonReentrant {
        liquidate();
        require(start, "Trading must be initialized");
        require(receiver != address(0x0), "Receiver cannot be 0x0 address");

        IERC20(USDC_TOKEN).safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Mint Chicks to receiver
        uint256 chicks = USDCtoCHICKS(usdcAmount);
        mint(receiver, (chicks * getBuyFee()) / FEE_BASE_1000);

        // Team fee
        uint256 feeAddressAmount = usdcAmount / FEES_BUY;
        require(feeAddressAmount > MIN, "must trade over min");
        sendUSDC(FEE_ADDRESS, feeAddressAmount);

        safetyCheck(eggsAmount);
    }

    function sell(uint256 chicks) external nonReentrant {
        liquidate();

        // Total USDC to be sent
        uint256 usdc = CHICKStoUSDC(chicks);

        // Burn CHICKS
        uint256 feeAddressAmount = usdc / FEES_SELL;
        _burn(msg.sender, chicks);

        // Payment to sender
        sendUSDC(msg.sender, (usdc * sell_fee) / FEE_BASE_1000);

        // Team fee
        require(feeAddressAmount > MIN, "must trade over min");
        sendUSDC(FEE_ADDRESS, feeAddressAmount);

        safetyCheck(eggs);
    }

    // Calculation may be off if liqudation is due to occur
    function getBuyAmount(uint256 amount) public view returns (uint256) {
        uint256 chicks = EGGStoCHICKSNoTrade(amount);
        return ((chicks * getBuyFee()) / FEE_BASE_1000);
    }

    function leverageFee(
        uint256 eggs,
        uint256 numberOfDays
    ) public view returns (uint256) {
        uint256 mintFee = (eggs * buy_fee_leverage) / FEE_BASE_1000;
        uint256 interest = getInterestFee(eggs, numberOfDays);
        return (mintFee + interest);
    }

    function leverage(
        uint256 eggs,
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

        uint256 eggsFee = leverageFee(eggs, numberOfDays);
        uint256 userEggs = eggs - eggsFee;

        uint256 feeAddressAmount = (eggsFee * 3) / 10;
        uint256 userBorrow = (userEggs * 99) / 100;
        uint256 overCollateralizationAmount = (userEggs) / 100;
        uint256 totalFee = eggsFee + overCollateralizationAmount;

        IERC20(EGGS_TOKEN).safeTransferFrom(msg.sender, address(this), totalFee);

        // CHICKS to user
        uint256 userChicks = EGGStoCHICKSLev(userEggs, feeAddressAmount + overCollateralizationAmount);
        mint(address(this), userChicks);

        require(feeAddressAmount > MIN, "Fees must be higher than min.");
        sendEggs(FEE_ADDRESS, feeAddressAmount);

        IERC20(EGGS_TOKEN).safeTransfer(msg.sender, userBorrow);

        addLoansByDate(userBorrow, userChicks, endDate);
        Loans[msg.sender] = Loan({
            collateral: userChicks,
            borrowed: userBorrow,
            endDate: endDate,
            numberOfDays: numberOfDays
        });

        safetyCheck(eggs);
    }

    function getInterestFee(
        uint256 amount,
        uint256 numberOfDays
    ) public pure returns (uint256) {
        uint256 interest = Math.mulDiv(0.039e18, numberOfDays, 365) + 0.001e18;
        return Math.mulDiv(amount, interest, 1e18);
    }

    function borrow(uint256 eggs, uint256 numberOfDays) public nonReentrant {
        require(
            numberOfDays < 366,
            "Max borrow/extension must be 365 days or less"
        );
        require(eggs != 0, "Must borrow more than 0");
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

        uint256 eggsFee = getInterestFee(eggs, numberOfDays);
        uint256 feeAddressFee = (eggsFee * 3) / 10;

        // CHICKS required from user
        uint256 userChicks = EGGStoCHICKSNoTradeCeil(eggs);
        uint256 newUserBorrow = (eggs * 99) / 100;

        Loans[msg.sender] = Loan({
            collateral: userChicks,
            borrowed: newUserBorrow,
            endDate: endDate,
            numberOfDays: numberOfDays
        });

        _transfer(msg.sender, address(this), userChicks);
        require(feeAddressFee > MIN, "Fees must be higher than min.");

        sendEggs(msg.sender, newUserBorrow - eggsFee);
        sendEggs(FEE_ADDRESS, feeAddressFee);

        addLoansByDate(newUserBorrow, userChicks, endDate);

        safetyCheck(eggsFee);
    }

    function borrowMore(uint256 eggs) public nonReentrant {
        require(!isLoanExpired(msg.sender), "Loan expired use borrow");
        require(eggs != 0, "Must borrow more than 0");
        liquidate();
        uint256 userBorrowed = Loans[msg.sender].borrowed;
        uint256 userCollateral = Loans[msg.sender].collateral;
        uint256 userEndDate = Loans[msg.sender].endDate;

        uint256 todayMidnight = getMidnightTimestamp(block.timestamp);
        uint256 newBorrowLength = (userEndDate - todayMidnight) / 1 days;

        uint256 eggsFee = getInterestFee(eggs, newBorrowLength);

        uint256 userChicks = EGGStoCHICKSNoTradeCeil(eggs);
        uint256 userBorrowedInChicks = EGGStoCHICKSNoTrade(userBorrowed);
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

        uint256 feeAddressFee = (eggsFee * 3) / 10;
        uint256 newUserBorrow = (eggs * 99) / 100;

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
        sendEggs(FEE_ADDRESS, feeAddressFee);
        sendEggs(msg.sender, newUserBorrow - eggsFee);

        addLoansByDate(newUserBorrow, requireCollateralFromUser, userEndDate);

        safetyCheck(eggsFee);
    }

    function removeCollateral(uint256 amount) public nonReentrant {
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        liquidate();
        uint256 collateral = Loans[msg.sender].collateral;
        
        require(
            Loans[msg.sender].borrowed <=
                (CHICKStoEGGS(collateral - amount) * 99) / 100,
            "Require 99% collateralization rate"
        );
        Loans[msg.sender].collateral = Loans[msg.sender].collateral - amount;
        _transfer(address(this), msg.sender, amount);
        subLoansByDate(0, amount, Loans[msg.sender].endDate);

        safetyCheck(0);
    }

    function repay(uint256 eggsAmount) public nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        require(borrowed > eggsAmount, "Must repay less than borrowed amount");
        require(eggsAmount != 0, "Must repay something");

        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, cannot repay"
        );
        
        IERC20(EGGS_TOKEN).safeTransferFrom(msg.sender, address(this), eggsAmount);
        
        uint256 newBorrow = borrowed - eggsAmount;
        Loans[msg.sender].borrowed = newBorrow;
        subLoansByDate(eggsAmount, 0, Loans[msg.sender].endDate);

        safetyCheck(0);
    }

    function closePosition(uint256 eggsAmount) public nonReentrant {
        uint256 borrowed = Loans[msg.sender].borrowed;
        uint256 collateral = Loans[msg.sender].collateral;
        require(
            !isLoanExpired(msg.sender),
            "Your loan has been liquidated, no collateral to remove"
        );
        require(borrowed == eggsAmount, "Must return entire borrowed amount");
        
        IERC20(EGGS_TOKEN).safeTransferFrom(msg.sender, address(this), eggsAmount);
        
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

        uint256 collateralInUSDC = CHICKStoUSDC(collateral);
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
        uint256 eggsAmount
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
        require(loanFee == eggsAmount, "Loan extension fee incorrect");
        
        IERC20(EGGS_TOKEN).safeTransferFrom(msg.sender, address(this), eggsAmount);
        
        uint256 feeAddressFee = (loanFee * 3) / 10;
        require(feeAddressFee > MIN, "Fees must be higher than min.");
        sendEggs(FEE_ADDRESS, feeAddressFee);
        subLoansByDate(borrowed, collateral, oldEndDate);
        addLoansByDate(borrowed, collateral, newEndDate);
        Loans[msg.sender].endDate = newEndDate;
        Loans[msg.sender].numberOfDays = numberOfDays + _numberOfDays;
        require(
            (newEndDate - block.timestamp) / 1 days < 366,
            "Loan must be under 365 days"
        );

        safetyCheck(eggsAmount);
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

    function getTotalBorrowed() public view returns (uint256) {
        return totalBorrowed;
    }

    function getTotalCollateral() public view returns (uint256) {
        return totalCollateral;
    }

    function getBacking() public view returns (uint256) {
        return IERC20(USDC_TOKEN).balanceOf(address(this)) + getTotalBorrowed();
    }

    function safetyCheck(uint256 eggs) private {
        uint256 newPrice = (getBacking() * 1 ether) / totalSupply();
        uint256 _totalColateral = balanceOf(address(this));
        require(
            _totalColateral >= totalCollateral,
            "The chicks balance of the contract must be greater than or equal to the collateral"
        );
        require(lastPrice <= newPrice, "The price of chicks cannot decrease");
        lastPrice = newPrice;
        emit Price(block.timestamp, newPrice, eggs);
    }

    function CHICKStoUSDC(uint256 value) public view returns (uint256) {
        return Math.mulDiv(value, getBacking(), totalSupply());
    }

    function USDCtoCHICKS(uint256 value) public view returns (uint256) {
        return Math.mulDiv(value, totalSupply(), getBacking() - value);
    }

    function USDCtoCHICKSLev(
        uint256 value,
        uint256 fee
    ) public view returns (uint256) {
        uint256 backing = getBacking() - fee;
        return (value * totalSupply() + (backing - 1)) / backing;
    }

    function USDCtoCHICKSNoTradeCeil(
        uint256 value
    ) public view returns (uint256) {
        uint256 backing = getBacking();
        return (value * totalSupply() + (backing - 1)) / backing;
    }

    function USDCtoCHICKSNoTrade(uint256 value) public view returns (uint256) {
        uint256 backing = getBacking();
        return Math.mulDiv(value, totalSupply(), backing);
    }

    function sendUSDC(address _address, uint256 _value) internal {
        IERC20(USDC_TOKEN).safeTransfer(_address, _value);
        emit SendUSDC(_address, _value);
    }

    //utils
    function getBuyChicks(uint256 amount) external view returns (uint256) {
        return
            (amount * (totalSupply()) * (buy_fee)) /
            (getBacking()) /
            (FEE_BASE_1000);
    }
}