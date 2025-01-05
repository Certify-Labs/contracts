// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./LearnAndEarnToken.sol";
import "./CourseVault.sol";
import "./CertificateNFT.sol";

contract LearnAndEarnPlatform is ERC4626, Ownable, ReentrancyGuard {
    using Strings for uint256;

    LearnAndEarnToken public letToken;
    IERC20 public eduToken;
    CertificateNFT public certificateNFT;

    struct Course {
        address publisher;
        address vault;
        string name;
        string metadataURI;
        bool isPremium;
        uint256 minPurchaseAmount;
        uint256 certificatePrice;
        uint256 basePrice;
        uint256 scalingFactor;
    }

    struct Bet {
        address better;
        uint256 courseId;
        uint256 betAmount;
        string hiddenMetadataURI;
        bool isActive;
        address acceptedBy;
    }

    uint256 public nextCourseId = 1;
    uint256 public nextBetId = 1;
    mapping(uint256 => Course) public courses;
    mapping(uint256 => Bet) public bets;
    mapping(address => bool) public hasEduId;
    mapping(address => mapping(uint256 => bool)) public hasBurnedTokensForCourse;
    address public agent;

    event CourseCreated(
        uint256 indexed courseId,
        address indexed publisher,
        string name,
        address vault,
        string metadataURI,
        bool isPremium,
        uint256 minPurchaseAmount,
        uint256 certificatePrice
    );

    event BetPlaced(
        uint256 indexed betId,
        address indexed better,
        uint256 indexed courseId,
        uint256 betAmount,
        string hiddenMetadataURI
    );

    event BetAccepted(uint256 indexed betId, address indexed acceptedBy);

    event BetResolved(uint256 indexed betId, address indexed winner, uint256 winnings);

    event TokensPurchased(address indexed buyer, uint256 indexed courseId, uint256 amount, uint256 price);

    event TokensMinted(address indexed user, uint256 amount);

    constructor(IERC20 _eduToken) ERC4626(_eduToken) ERC20("LearnAndEarnVault", "LEV") Ownable(msg.sender) {
        eduToken = _eduToken;
        letToken = new LearnAndEarnToken();
        certificateNFT = new CertificateNFT();
    }

    modifier onlyAgent() {
        require(msg.sender == agent, "Caller is not the agent");
        _;
    }

    function setAgent(address _agent) external onlyOwner {
        agent = _agent;
    }

    function mintLearnAndEarnTokens(address user) external onlyAgent {
        require(!hasEduId[user], "User already has an EDU ID");
        hasEduId[user] = true;
        letToken.mint(user, 100 * 10 ** letToken.decimals());
        emit TokensMinted(user, 100 * 10 ** letToken.decimals());
    }

    function createCourse(
        string memory name,
        string memory metadataURI,
        bool isPremium,
        uint256 minPurchaseAmount,
        uint256 certificatePrice,
        uint256 basePrice,
        uint256 scalingFactor
    ) external {
        require(!isPremium || minPurchaseAmount > 0, "Premium courses must have a minimum purchase amount");

        CourseVault vault = new CourseVault(IERC20(address(letToken)), name);

        courses[nextCourseId] = Course({
            publisher: msg.sender,
            vault: address(vault),
            name: name,
            metadataURI: metadataURI,
            isPremium: isPremium,
            minPurchaseAmount: minPurchaseAmount,
            certificatePrice: certificatePrice,
            basePrice: basePrice,
            scalingFactor: scalingFactor
        });

        emit CourseCreated(
            nextCourseId,
            msg.sender,
            name,
            address(vault),
            metadataURI,
            isPremium,
            minPurchaseAmount,
            certificatePrice
        );
        nextCourseId++;
    }

    function calculateTokenPrice(uint256 courseId, uint256 amount) public view returns (uint256) {
        Course memory course = courses[courseId];
        CourseVault vault = CourseVault(course.vault);
        uint256 currentSupply = vault.totalAssets();
        return course.basePrice + (course.scalingFactor * (currentSupply + amount) ** 2);
    }

    function buyCourseTokensWithLET(uint256 courseId, uint256 amount) external nonReentrant {
        Course memory course = courses[courseId];
        require(course.vault != address(0), "Course does not exist");

        uint256 price = calculateTokenPrice(courseId, amount);
        uint256 totalCost = price * amount;
        require(letToken.balanceOf(msg.sender) >= totalCost, "Insufficient LET balance");

        letToken.transferFrom(msg.sender, address(this), totalCost);
        CourseVault(course.vault).deposit(totalCost, msg.sender);

        emit TokensPurchased(msg.sender, courseId, amount, price);
    }

    function buyCourseTokensWithEDU(uint256 courseId, uint256 courseTokenAmount) external nonReentrant {
        Course memory course = courses[courseId];
        require(course.vault != address(0), "Course does not exist");

        // Step 1: Calculate the LET tokens needed for the desired course tokens
        uint256 courseTokenPrice = calculateTokenPrice(courseId, courseTokenAmount);
        uint256 requiredLET = courseTokenPrice * courseTokenAmount;

        // Step 2: Calculate the EDU tokens needed to mint the required LET tokens
        uint256 requiredEDU = previewDeposit(requiredLET); // ERC4626 function to calculate EDU required for LET

        // Step 3: Deposit EDU tokens to mint LET tokens
        deposit(requiredEDU, msg.sender); // Automatically transfers EDU and mints LET

        // Step 4: Deposit LET tokens into the course vault to mint course tokens
        CourseVault vault = CourseVault(course.vault);
        vault.deposit(requiredLET, msg.sender); // Automatically transfers LET and mints course tokens

        emit TokensPurchased(msg.sender, courseId, courseTokenAmount, courseTokenPrice);
    }

    function burnTokensForCertificate(uint256 courseId, uint256 amount) external nonReentrant {
        Course memory course = courses[courseId];
        require(course.vault != address(0), "Course does not exist");
        require(!hasBurnedTokensForCourse[msg.sender][courseId], "Tokens already burned for this course");

        CourseVault vault = CourseVault(course.vault);
        vault.transferFrom(msg.sender, address(this), amount);
        ERC20(address(vault)).transfer(address(0), amount);
        hasBurnedTokensForCourse[msg.sender][courseId] = true;

        uint256 currentSupply = vault.totalAssets();
        course.basePrice += course.scalingFactor * ((currentSupply - amount) ** 2);
    }

    function mintCertificate(uint256 courseId, string memory metadataURI) external onlyAgent {
        require(hasBurnedTokensForCourse[msg.sender][courseId], "Tokens not burned for this course");
        certificateNFT.mintCertificate(msg.sender, metadataURI);
    }

    function placeBet(uint256 courseId, uint256 betAmount, string memory hiddenMetadataURI) external nonReentrant {
        Course memory course = courses[courseId];
        require(course.vault != address(0), "Course does not exist");
        require(betAmount > 0, "Bet amount must be greater than zero");

        CourseVault vault = CourseVault(course.vault);
        vault.transferFrom(msg.sender, address(this), betAmount);

        bets[nextBetId] = Bet({
            better: msg.sender,
            courseId: courseId,
            betAmount: betAmount,
            hiddenMetadataURI: hiddenMetadataURI,
            isActive: true,
            acceptedBy: address(0)
        });

        emit BetPlaced(nextBetId, msg.sender, courseId, betAmount, hiddenMetadataURI);
        nextBetId++;
    }

    function acceptBet(uint256 betId) external nonReentrant {
        Bet storage bet = bets[betId];
        require(bet.isActive, "Bet is not active");
        require(bet.acceptedBy == address(0), "Bet already accepted");
        require(bet.better != msg.sender, "Cannot accept your own bet");

        Course memory course = courses[bet.courseId];
        require(course.vault != address(0), "Course does not exist");

        CourseVault vault = CourseVault(course.vault);
        vault.transferFrom(msg.sender, address(this), bet.betAmount);

        bet.acceptedBy = msg.sender;
        emit BetAccepted(betId, msg.sender);
    }

    function resolveBet(uint256 betId, address winner) external onlyOwner nonReentrant {
        Bet storage bet = bets[betId];
        require(bet.isActive, "Bet is not active");
        require(bet.acceptedBy != address(0), "Bet has not been accepted");
        require(winner == bet.better || winner == bet.acceptedBy, "Invalid winner");

        Course memory course = courses[bet.courseId];
        CourseVault vault = CourseVault(course.vault);
        vault.transfer(winner, bet.betAmount * 2);

        bet.isActive = false;
        emit BetResolved(betId, winner, bet.betAmount * 2);
    }
}
